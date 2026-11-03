"""ERP, READ ONLY, and OFF unless a human turns it on.

Auth is an open decision, so both adapters ship and `ERP_MODE` defaults to `off`:

  token  `Authorization: token key:secret` from a 0600 key file, plain GET against the
         resource API. The key is read at call time, held in a local, and never logged,
         put in argv, or written to any file.
  mcp    `claude -p` with a read-only tool allow-list. Spends tokens, so it runs only with
         the explicit `--erp-mcp` flag.

There is no POST, PUT or DELETE anywhere in this module, and the mcp allow-list comes from
work.conf (ERP_MCP_TOOLS) so no tool or company name is written in this public repo.
An allow-list alone is not enough, so the call also passes --disallowedTools from
ERP_MCP_DENY (every write-capable tool, by pattern) and --permission-mode default, and
refuses to run at all when ERP_MCP_DENY is empty.
"""
import datetime
import json
import os
import re
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request

from . import atomic, config

# doctype -> (ref prefix, srcstate kind, title field, closed statuses)
DOCTYPES = {
    "ToDo": ("todo:", "todo", "description", ("Closed", "Cancelled")),
    "HD Ticket": ("", "hd", "subject", ("Resolved", "Closed")),
    "Task": ("", "task", "subject", ("Completed", "Cancelled")),
}
CLOSED = {kind: closed for _, kind, _, closed in DOCTYPES.values()}
SAFE = re.compile(r"[^A-Za-z0-9 ,.:/_#()-]")


class ErpError(RuntimeError):
    pass


def state_for(cfg, mcp_ok=False):
    """('off'|'ready', detail): whether a fetch would even be attempted."""
    if cfg.erp_mode == "off":
        return "off", "ERP_MODE=off"
    if cfg.erp_mode == "token":
        return ("ready", "token") if cfg.erp_base_url and cfg.erp_key_file else ("off", "token mode needs ERP_BASE_URL and ERP_KEY_FILE")
    if cfg.erp_mode == "mcp":
        return ("ready", "mcp") if mcp_ok else ("off", "mcp mode needs the explicit --erp-mcp flag")
    return "off", f"unknown ERP_MODE {cfg.erp_mode!r}"


def _key(path):
    p = os.path.expanduser(path)
    st = os.stat(p)
    if st.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise ErpError("ERP_KEY_FILE must be mode 0600")
    with open(p, encoding="utf-8") as fh:
        return fh.read().strip()


def get(cfg, path, query, opener=urllib.request.urlopen):
    """GET base+path. The one HTTP primitive; tests replace `opener`."""
    url = cfg.erp_base_url.rstrip("/") + path + ("?" + urllib.parse.urlencode(query) if query else "")
    if not url.startswith("https://"):
        raise ErpError("ERP_BASE_URL must be https")
    req = urllib.request.Request(url, method="GET", headers={"Authorization": "token " + _key(cfg.erp_key_file)})
    try:
        with opener(req, timeout=20) as fh:
            return json.loads(fh.read())
    except (OSError, ValueError) as e:
        # the message can carry the URL but never a header, so the key cannot leak here
        raise ErpError(f"GET {path}: {type(e).__name__}") from e


def clean(s, n=120):
    return SAFE.sub("", " ".join(str(s or "").split()))[:n]


def _norm(doctype, row, cfg):
    prefix, kind, tfield, _ = DOCTYPES[doctype]
    name = str(row.get("name") or "")
    if not name or not re.fullmatch(r"[A-Za-z0-9_-]{1,60}", name):
        return None
    slug = doctype.lower().replace(" ", "-")
    return {"ref": prefix + name, "src": "erp", "kind": kind, "doctype": doctype,
            "url": f"{cfg.erp_base_url.rstrip('/')}/app/{slug}/{name}" if cfg.erp_base_url else None,
            "title": clean(row.get(tfield)) or name, "state": clean(row.get("status"), 30).lower() or "open",
            "updatedAt": row.get("modified"), "work": True}


def fetch_token(cfg, opener=urllib.request.urlopen):
    me = get(cfg, "/api/method/frappe.auth.get_logged_user", None, opener).get("message")
    if not me:
        raise ErpError("could not resolve the logged-in user")
    items = []
    for dt in cfg.erp_doctypes:
        if dt not in DOCTYPES:
            continue
        _, _, tfield, closed = DOCTYPES[dt]
        who = ["allocated_to", "=", me] if dt == "ToDo" else ["_assign", "like", f"%{me}%"]
        flt = [who, ["status", "not in", list(closed)]]
        q = {"fields": json.dumps(["name", tfield, "status", "modified"]), "filters": json.dumps(flt),
             "limit_page_length": "50"}
        for row in get(cfg, "/api/resource/" + urllib.parse.quote(dt), q, opener).get("data", []):
            it = _norm(dt, row, cfg)
            if it:
                items.append(it)
    return items


# The same guarantees dots-inbox gives its own spawns (nix/pkgs/dots-inbox/dots_inbox/llmrun.py), kept
# small and duplicated on purpose: this package cannot import that one. AGENT_OFF is the same file.
def agent_off():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.exists(os.path.join(base, "dots-mail", "AGENT_OFF"))


MCP_MODEL = "haiku"                  # never an unnamed default: that is a model the owner banned
MCP_RUNS_CAP = 8                     # a day; the 4 h timer wants 6
MCP_USD_CAP = 0.30                   # estimated dollars a day (est per run below)
MCP_EST_USD = 0.03                   # one narrowed haiku run; the old, unnarrowed one cost ~$0.76
MCP_TURNS, MCP_BUDGET = 12, 0.25     # claude stops itself at either


def _spend_file():
    return config.STATE_DIR / "erp-mcp-spend.json"


def reserve_mcp(now=None):
    """Raise ErpError when AGENT_OFF is set or today's cap is spent; else count this run first,
    so a crash or timeout still counts."""
    if agent_off():
        raise ErpError("agent switched off (AGENT_OFF)")
    day = (now or datetime.datetime.now()).strftime("%Y-%m-%d")
    st = atomic.read_json(_spend_file(), {}) or {}
    if st.get("day") != day:
        st = {"day": day, "runs": 0, "usd": 0.0}
    if st["runs"] >= MCP_RUNS_CAP or st["usd"] + MCP_EST_USD > MCP_USD_CAP:
        raise ErpError(f"daily cap reached ({st['runs']} runs, ~${st['usd']:.2f})")
    st["runs"] += 1
    st["usd"] = round(st["usd"] + MCP_EST_USD, 4)
    atomic.write_json(_spend_file(), st)


def _only_servers(tools, scratch):
    """A --mcp-config holding just the MCP servers the allow-list names (from the user's own
    ~/.claude.json), so the run is offered those tools and not the other ~950. None when a
    server is not defined there (a plugin's): then nothing can be narrowed."""
    names = {m.group(1) for t in tools if (m := re.match(r"mcp__(.+?)__", t))}
    try:
        with open(os.path.expanduser("~/.claude.json")) as f:
            have = json.load(f)["mcpServers"]
        picked = {n: have[n] for n in names}
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not picked:
        return None
    path = os.path.join(scratch, "mcp.json")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"mcpServers": picked}, f)
    return path


def fetch_mcp(cfg, runner=subprocess.run):
    """Ask `claude -p` for my open items, with only read tools allowed. Output is validated.
    Guarded like every other spawn: AGENT_OFF, a daily spend check, a pinned cheap model, the
    user's CLAUDE.md / memory / transcript cut, a turn and a dollar limit, only the ERP server."""
    if not cfg.raw.get("ERP_MCP_TOOLS"):
        raise ErpError("mcp mode needs ERP_MCP_TOOLS (the read-only tool names) in work.conf")
    if not cfg.raw.get("ERP_MCP_DENY", "").strip():
        raise ErpError("mcp mode needs ERP_MCP_DENY (the write-capable tool patterns) in work.conf")
    prompt = ("List my open items in these ERP doctypes: " + ", ".join(cfg.erp_doctypes) +
              ". Read only. Reply with ONLY a JSON array of objects with keys "
              "doctype, name, title, status, modified. No prose.")
    reserve_mcp()
    tools = cfg.raw["ERP_MCP_TOOLS"].split()
    argv = ["claude", "-p", prompt, "--model", MCP_MODEL, "--allowedTools", ",".join(tools),
            "--disallowedTools", ",".join(cfg.raw["ERP_MCP_DENY"].replace(",", " ").split()),
            "--permission-mode", "dontAsk", "--output-format", "text", "--no-session-persistence",
            "--max-turns", str(MCP_TURNS), "--max-budget-usd", f"{MCP_BUDGET:.2f}"]
    # this headless run is not an agent session: the task gate (dots-task-hook) must stand down
    env = {**{k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_PLUGIN_DIRS"},
           "DOTS_TASK_GATE": "off", "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
    try:
        with tempfile.TemporaryDirectory(prefix="dots-overview-erp-") as scratch:
            conf = _only_servers(tools, scratch)
            if conf:
                argv += ["--strict-mcp-config", "--setting-sources", "", "--mcp-config", conf]
            p = runner(argv, capture_output=True, text=True, timeout=180, stdin=subprocess.DEVNULL,
                       env=env, cwd=scratch)
        rows = json.loads(p.stdout[p.stdout.index("["):p.stdout.rindex("]") + 1])
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        raise ErpError(f"mcp fetch failed: {type(e).__name__}") from e
    items = []
    for r in rows if isinstance(rows, list) else []:
        if isinstance(r, dict) and r.get("doctype") in DOCTYPES:
            it = _norm(r["doctype"], {"name": r.get("name"), DOCTYPES[r["doctype"]][2]: r.get("title"),
                                      "status": r.get("status"), "modified": r.get("modified")}, cfg)
            if it:
                items.append(it)
    return items


def view_status(cfg, kind, ref, opener=urllib.request.urlopen):
    """Current status string of one ERP item (token mode), for the detectors."""
    for dt, (prefix, k, _, _) in DOCTYPES.items():
        if k == kind:
            name = ref[len(prefix):]
            row = get(cfg, f"/api/resource/{urllib.parse.quote(dt)}/{urllib.parse.quote(name)}", None, opener).get("data", {})
            return row.get("status")
    return None
