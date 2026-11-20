#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""launcher_cmds.py <verb> ...: the launcher's ">" mode (saved commands). Prints one JSON object.

  query [text]        rows for the launcher (fuzzy over name, tags, command; most used first)
  run <id>            run the command in a NEW herdr pane (typed into the pane's shell; placeholders
                      like <namespace> are typed but NOT submitted, so you fill them in)
  edit <id>           open commands.json in $EDITOR in a new herdr pane
  save "name :: command [:: tag, tag]"   append a saved command

Config   $DOTS_LAUNCHER_CONFIG or ~/.config/dots-launcher/commands.json   [{id,name,tags,cmd}]
State    $DOTS_LAUNCHER_STATE  or ~/.local/state/dots-launcher/command-uses.json   {id:{n,last}}
Nothing here is a shell string: herdr is called with an argv list. DOTS_LAUNCHER_EXEC_LOG=<file> logs the
argv (one JSON list per line) instead of running it, which is how the tests run.
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

HINT = "No saved commands yet. Type  name :: command  and pick Save a new command."
NEW_BODY = "Name it, tag it, add placeholders like <namespace>.\nType:  name :: command :: tag, tag"
PLACEHOLDER = re.compile(r"<[A-Za-z][A-Za-z0-9_-]*>")


def home():
    return os.path.expanduser("~")


def cfg_path():
    d = os.environ.get("DOTS_LAUNCHER_CONFIG") or os.path.join(home(), ".config", "dots-launcher")
    return os.path.join(d, "commands.json")


def state_path():
    d = os.environ.get("DOTS_LAUNCHER_STATE") or os.path.join(home(), ".local", "state", "dots-launcher")
    return os.path.join(d, "command-uses.json")


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj, mode=0o600):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def commands():
    raw = load_json(cfg_path(), [])
    out = []
    for c in raw if isinstance(raw, list) else []:
        if isinstance(c, dict) and c.get("name") and c.get("cmd"):
            out.append({"id": str(c.get("id") or slug(c["name"])), "name": str(c["name"]), "cmd": str(c["cmd"]),
                        "tags": [str(t) for t in c.get("tags", [])] if isinstance(c.get("tags"), list) else []})
    return out


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "cmd"


def fuzzy(q, s):
    """0..1: 1 exact, .9 prefix, .75 substring, up to .6 ordered subsequence, 0 none."""
    q, s = q.lower().strip(), s.lower()
    if not q:
        return 0.5
    if s == q:
        return 1.0
    if s.startswith(q):
        return 0.9
    if q in s:
        return 0.75
    i = 0
    for ch in s:
        if i < len(q) and ch == q[i]:
            i += 1
    return 0.3 + 0.3 * len(q) / max(len(s), 1) if i == len(q) else 0.0


def ago(ts):
    if not ts:
        return None
    d = max(0, time.time() - ts)
    for n, u in ((86400, "day"), (3600, "hour"), (60, "min")):
        if d >= n:
            k = int(d // n)
            return "%d %s%s ago" % (k, u, "" if k == 1 and u != "min" else ("s" if u != "min" else ""))
    return "just now"


def query(text):
    uses = load_json(state_path(), {})
    q = text.strip()
    rows = []
    for c in commands():
        s = max(fuzzy(q, c["name"]), fuzzy(q, " ".join(c["tags"])) * 0.9, fuzzy(q, c["cmd"]) * 0.6)
        if q and s <= 0:
            continue
        u = uses.get(c["id"], {})
        n = int(u.get("n", 0))
        used = "used %d time%s" % (n, "" if n == 1 else "s") if n else "never used"
        tags = ", ".join(c["tags"])
        body = c["cmd"] + ("\n\nFill in %s, then press Enter in the pane." % ", ".join(PLACEHOLDER.findall(c["cmd"]))
                           if PLACEHOLDER.search(c["cmd"]) else "\n\nRuns in a new herdr pane.")
        rows.append({"key": c["id"], "title": c["name"], "sub": (tags + ", " if tags else "") + used,
                     "icon": "terminal-window", "score": min(1.0, s + min(n, 50) / 500), "cmd": c["cmd"],
                     "preview": {"head": c["name"], "body": body},
                     "actions": [{"label": "Run in pane", "primary": True}, {"label": "Copy"}, {"label": "Edit"}]})
    rows.sort(key=lambda r: -r["score"])
    new_sub = "Tags, description"
    if "::" in q:
        new_sub = "Enter saves: " + q.split("::", 1)[0].strip()
    rows.append({"key": "__new", "title": "Save a new command", "sub": new_sub, "icon": "pencil-simple", "score": 0.1, "noAll": True,
                 "preview": {"head": "New command", "body": NEW_BODY}, "query": q,
                 "actions": [{"label": "Save", "primary": True}]})
    return {"rows": rows, "hint": HINT}


# ---- running in a herdr pane ---------------------------------------------------------------
def sh(argv):
    """Run (or, under test, log) an argv list; returns parsed JSON stdout or {}."""
    log = os.environ.get("DOTS_LAUNCHER_EXEC_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as f:
            f.write(json.dumps(argv) + "\n")
        return {"result": {"pane": {"pane_id": "test:p9"}, "panes": [{"pane_id": "test:p1", "focused": True}]}}
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return json.loads(p.stdout) if p.stdout.strip() else {}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


def find_key(o, key):
    if isinstance(o, dict):
        if isinstance(o.get(key), str):
            return o[key]
        for v in o.values():
            r = find_key(v, key)
            if r:
                return r
    elif isinstance(o, list):
        for v in o:
            r = find_key(v, key)
            if r:
                return r
    return None


def focused_pane():
    lst = sh(["herdr", "pane", "list"])
    panes = (lst.get("result") or {}).get("panes") or []
    for p in panes:
        if p.get("focused"):
            return p.get("pane_id")
    return panes[0].get("pane_id") if panes else None


def in_new_pane(text, submit=True):
    if not os.environ.get("DOTS_LAUNCHER_EXEC_LOG") and not shutil.which("herdr"):
        return "herdr is not installed"
    base = focused_pane()
    if not base:
        return "No herdr pane to split. Open herdr first."
    new = find_key(sh(["herdr", "pane", "split", "--pane", base, "--direction", "down", "--focus"]), "pane_id")
    if not new:
        return "herdr could not open a pane"
    sh(["herdr", "pane", "run", new, text] if submit else ["herdr", "pane", "send-text", new, text])
    return ""


def bump(cid):
    u = load_json(state_path(), {})
    e = u.get(cid, {})
    u[cid] = {"n": int(e.get("n", 0)) + 1, "last": int(time.time())}
    write_json(state_path(), u)


def run(cid):
    c = next((x for x in commands() if x["id"] == cid), None)
    if not c:
        return {"rows": [], "error": "No saved command %s" % cid}
    err = in_new_pane(c["cmd"], submit=not PLACEHOLDER.search(c["cmd"]))
    if err:
        return {"rows": [], "error": err}
    bump(cid)
    return {"rows": [], "toast": "Running in a new pane"}


def edit(_cid):
    path = cfg_path()
    if not os.path.exists(path):
        write_json(path, [], 0o600)
    editor = os.environ.get("VISUAL") or os.environ.get("EDITOR") or "nvim"
    err = in_new_pane(" ".join(shlex.quote(a) for a in shlex.split(editor) + [path]))
    return {"rows": [], "error": err} if err else {"rows": [], "toast": "Editing commands.json"}


def save(spec):
    parts = [p.strip() for p in spec.split("::")]
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return {"rows": [], "error": "Type  name :: command  first"}
    tags = [t.strip() for t in parts[2].split(",") if t.strip()] if len(parts) > 2 else []
    cur = load_json(cfg_path(), [])
    cur = cur if isinstance(cur, list) else []
    ids = {str(c.get("id") or slug(str(c.get("name", "")))) for c in cur if isinstance(c, dict)}
    cid, n = slug(parts[0]), 2
    while cid in ids:
        cid, n = "%s-%d" % (slug(parts[0]), n), n + 1
    cur.append({"id": cid, "name": parts[0], "cmd": parts[1], "tags": tags})
    write_json(cfg_path(), cur, 0o600)
    return {"rows": [], "toast": "Saved %s" % parts[0]}


def main(argv):
    verb = argv[0] if argv else ""
    rest = argv[1:]
    if verb == "query":
        out = query(" ".join(rest))
    elif verb == "run" and rest:
        out = run(rest[0])
    elif verb == "edit":
        out = edit(rest[0] if rest else "")
    elif verb == "save" and rest:
        out = save(" ".join(rest))
    else:
        out = {"rows": [], "error": "usage: launcher_cmds.py query|run|edit|save"}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
