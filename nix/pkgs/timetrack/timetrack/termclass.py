"""What terminal time was actually spent on.

About 92% of a day is one app, the terminal, so "by app" says nothing. herdr knows which
pane had focus (focuslog.py) and each pane knows the Claude session it hosts, the ticket
token it was given, its directory. This joins them to ActivityWatch and answers "which task".

Time is gated exactly as web.py gates browser time:

    terminal window has OS focus  AND  AW says not-afk

then cut by the focus log into pane segments. Time the focus log did not cover (before it
existed, or while clockd was down) falls back to the workspace named in the window title.

Each segment is resolved by a ladder, strongest evidence first, and the rung used is kept
as `labelled_by` so a number can always be traced to what it rests on:

    session   the Claude session in the pane -> the Taskwarrior task that session owns
              (`sess` UDA), or the ticket dots-track-hook recorded for it
    token     the ticket token reported on the pane (binding tier 1)
    branch    the ticket in the git branch of the pane's directory (binding tier 2)
    repo      the project the pane's repository maps to (binding tier 3): a project, no ticket
    llm       what is left goes to the local model, in batches, exactly like webclass.py
    title     history from before the focus log: the workspace name only
    none      nothing resolved and no model answered
    claim     not a rung: a segment with a project and no ticket that the user promoted to a
              task (untracked_claim) is relabelled with it when the day is written

The model is offered only OPEN tasks and may name only one it was offered, or a project that
is already known; anything else it says is dropped. Strings are redacted before they reach
it, and the answer is cached per context, so a pane's situation is asked about once.

Everything lands in private.db (term_segment, term_day). Pane titles, directories and
prompts never touch work.db and nothing here leaves the machine: Ollama is on loopback.
"""
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, time as dtime, timedelta

from . import binding, config, dbs, focuslog, herdr_proto, web, webclass
from .backfill import aw

OLLAMA = webclass.OLLAMA
DEFAULT_MODEL = webclass.DEFAULT_MODEL
BATCH = webclass.BATCH
MERGE_GAP = 60              # seconds: the same context resumed within this is one segment
LIVE_SLACK = 30             # an open span is trusted this long past its last heartbeat
OFFERED = 60                # open tasks shown to the model
TERMINAL_APP = re.compile(r"^(com\.mitchellh\.ghostty|ghostty|kitty|alacritty|foot|"
                          r"org\.wezfurlong\.wezterm|wezterm)", re.IGNORECASE)
VERDICTS = ("work", "delegated", "unproductive")
BY = ("session", "token", "branch", "repo", "llm", "title", "none", "claim")
redact = webclass.redact


# -- inputs ------------------------------------------------------------------------------

def window_segments(day, now=None):
    """[(start_unix, end_unix, window_title)]: terminal focused AND present, clipped.

    Reuses web.segments, the gate browser time already goes through, so the two can never
    disagree about what "present and focused" means."""
    t0 = datetime.combine(day, dtime.min).astimezone()
    t1 = t0 + timedelta(days=1)
    events = [(s, e, d) for s, e, d in web._events("currentwindow", t0, t1)
              if TERMINAL_APP.match(d.get("app") or "")]
    present = [(max(s, t0), min(e, t1)) for s, e in aw.not_afk(day, day, now)
               if max(s, t0) < min(e, t1)]
    out = [(int(lo.timestamp()), int(hi.timestamp()), d.get("title") or "")
           for lo, hi, d in web.segments(events, [(s, e) for s, e, _ in events], present)]
    return sorted(x for x in out if x[1] > x[0])


def load_spans(conn, t0, t1, now=None):
    """focus_span rows overlapping [t0, t1) as dicts with a concrete end. A span still open
    is trusted only to its last heartbeat (plus slack), so a crashed daemon cannot stretch it."""
    now = int(now or time.time())
    out = []
    for r in conn.execute("SELECT * FROM focus_span WHERE start_unix < ? AND"
                          " COALESCE(end_unix, COALESCE(seen_unix, start_unix) + ?) > ?"
                          " ORDER BY start_unix", (t1, LIVE_SLACK, t0)):
        d = dict(r)
        d["end"] = d["end_unix"] if d["end_unix"] is not None else \
            min(now, (d["seen_unix"] or d["start_unix"]) + LIVE_SLACK)
        out.append(d)
    return out


def cut(windows, spans):
    """Pieces of each window segment: covered by a focus span, or not (span None)."""
    pieces = []
    for s, e, title in windows:
        cur = s
        for sp in spans:
            lo, hi = max(sp["start_unix"], cur), min(sp["end"], e)
            if hi <= lo:
                continue
            if lo > cur:
                pieces.append({"start": cur, "end": lo, "span": None, "title": title})
            pieces.append({"start": lo, "end": hi, "span": sp, "title": title})
            cur = hi
        if cur < e:
            pieces.append({"start": cur, "end": e, "span": None, "title": title})
    return pieces


def load_sessions(path=None):
    """{session: [records]} from dots-track-hook's log, oldest first."""
    out = {}
    try:
        with open(path or config.SESSIONS_JSONL, encoding="utf-8") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if isinstance(r, dict) and r.get("sess"):
                    out.setdefault(r["sess"], []).append(r)
    except OSError:
        pass
    return out


def _task_export(*flt):
    try:
        out = subprocess.run([config.TASK, "rc.hooks=off", *flt, "export"],
                             capture_output=True, text=True, timeout=30,
                             stdin=subprocess.DEVNULL).stdout
        rows = json.loads(out or "[]")
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    return rows if isinstance(rows, list) else []


def load_tasks():
    """Open tasks plus any task that owns a Claude session, as plain dicts.

    `id` is the first 8 hex of the uuid: what the model sees and must echo back."""
    seen, tasks = set(), []
    for t in _task_export("status:pending") + _task_export("sess.any:"):
        if not isinstance(t, dict) or not t.get("uuid") or t["uuid"] in seen:
            continue
        seen.add(t["uuid"])
        refs = {str(v) for k, v in t.items()
                if isinstance(v, str) and (v.startswith("http") or re.fullmatch(binding.TICKET, v))}
        tasks.append({"id": t["uuid"][:8], "uuid": t["uuid"],
                      "desc": (t.get("description") or "")[:120], "ref": t.get("ref"),
                      "project": t.get("project"), "sess": t.get("sess"),
                      "agent": t.get("agent"), "open": t.get("status") == "pending",
                      "refs": refs})
    return tasks


_BRANCHES = {}


def git_branch(cwd):
    """The branch checked out in `cwd` NOW. HEAD at classification time, not at the time of
    the segment: a worktree that moved on since will answer for its current work."""
    if not cwd or not cwd.startswith("/"):
        return None
    if cwd not in _BRANCHES:
        try:
            p = subprocess.run(["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                               capture_output=True, text=True, timeout=5,
                               stdin=subprocess.DEVNULL)
            b = p.stdout.strip() if p.returncode == 0 else None
        except (OSError, subprocess.SubprocessError):
            b = None
        _BRANCHES[cwd] = None if b in (None, "", "HEAD") else b
    return _BRANCHES[cwd]


def live_snapshot():
    return focuslog.snapshot()


# -- the ladder --------------------------------------------------------------------------

def parse_title(title):
    """The workspace out of a window title: "ws · tab · pane" (ours) or "host: ws" (herdr's
    default, which is all the history before the focus log has)."""
    t = (title or "").strip()
    if " · " in t:
        return t.split(" · ", 1)[0].strip() or None
    if ": " in t:
        return t.split(": ", 1)[1].strip() or None
    return t or None


def _find_task(ticket, tasks):
    for t in tasks:
        if ticket and (t.get("ref") == ticket or ticket in t["refs"]
                       or (t.get("open") and ticket in t["desc"])):
            return t
    return None


def session_record(sessions, span, start, end):
    """The hook's last record for the span's session; else, with no session on the span,
    the last record for this PANE in a window around the piece -- time-bounded because pane
    ids are recycled across herdr restarts, so a bare pane_id match could be another life."""
    sess = span.get("agent_session")
    if sess:
        recs = sessions.get(sess) or []
        return recs[-1] if recs else None
    best = None
    if not span.get("pane_id"):
        return None
    for recs in sessions.values():
        for r in recs:
            if r.get("pane") == span.get("pane_id") and r.get("cwd") == span.get("cwd") \
                    and start - 1800 <= int(r.get("ts") or 0) <= end:
                if best is None or r["ts"] > best["ts"]:
                    best = r
    return best


def resolve(ctx, tasks, sessions, start=0, end=0):
    """Deterministic ladder for one context dict. Returns a dict or None.

    {task, ticket, project, agent_name, by}. Each rung may add what the one above could not:
    a session names an agent even when no task owns it."""
    by_sess = {t["sess"]: t for t in tasks if t.get("sess")}
    rec = session_record(sessions, ctx, start, end) if sessions is not None else None
    sess = ctx.get("agent_session") or (rec or {}).get("sess")
    agent = None
    task = by_sess.get(sess) if sess else None
    if task:
        agent = task.get("agent")
    if rec and not agent:
        agent = rec.get("agent")
    if task:
        return {"task": task, "ticket": task.get("ref"), "project": task.get("project"),
                "agent_name": agent, "by": "session"}
    rungs = [("session", (rec or {}).get("ticket")),
             ("token", ctx.get("ticket_token")),
             ("branch", binding.from_branch(git_branch(ctx.get("cwd")))[0])]
    for by, ticket in rungs:
        if ticket:
            t = _find_task(ticket, tasks)
            return {"task": t, "ticket": ticket, "project": t.get("project") if t else None,
                    "agent_name": agent, "by": by}
    project, _ = binding.from_repo(ctx.get("cwd"))
    if project:
        return {"task": None, "ticket": None, "project": project, "agent_name": agent,
                "by": "repo"}
    if agent:        # known agent, nothing else: keep the agent, leave the rest to the model
        return {"task": None, "ticket": None, "project": None, "agent_name": agent, "by": None}
    return None


def workspace_context(label, snap):
    """Best guess at a pane context for a bare workspace NAME, from the live snapshot.
    Only a unique workspace with a unique cwd / session is used; ambiguity yields nothing."""
    if not label or not snap:
        return {}
    ws = [w for w in snap.get("workspaces", []) if w.get("label") == label]
    if len(ws) != 1:
        return {}
    panes = [p for p in snap.get("panes", []) if p.get("workspace_id") == ws[0]["workspace_id"]]
    cwds = Counter(p.get("foreground_cwd") or p.get("cwd") for p in panes
                   if p.get("foreground_cwd") or p.get("cwd"))
    sessions = {focuslog._session(p) for p in panes if focuslog._session(p)}
    tokens = {binding.from_metadata(p)[0] for p in panes if binding.from_metadata(p)[0]}
    return {"cwd": cwds.most_common(1)[0][0] if cwds else None,
            "agent_session": next(iter(sessions)) if len(sessions) == 1 else None,
            "ticket_token": next(iter(tokens)) if len(tokens) == 1 else None}


# -- the model ---------------------------------------------------------------------------

def _basename(cwd):
    return os.path.basename((cwd or "").rstrip("/")) or ""


def summary_of(snap, ctx):
    """The pane's terminal title without its status glyph -- for a Claude pane that is the
    session's own summary line. Live data: only for a pane still there with the same session."""
    for p in (snap or {}).get("panes", []):
        if p.get("terminal_id") and p.get("terminal_id") == ctx.get("terminal_id") \
                and focuslog._session(p) == ctx.get("agent_session"):
            t = p.get("terminal_title_stripped") or p.get("terminal_title") or ""
            return t.lstrip("".join(chr(c) for c in range(0x2800, 0x2900)) + "◐◑◒◓"
                            + herdr_proto.TITLE_IDLE_GLYPH + " ").strip()
    return ""


def prompts_in(sessions, ctx, start, end):
    """Up to three distinct prompt heads the hook saw for this pane's session in the window."""
    recs = sessions.get(ctx.get("agent_session")) or []
    out = []
    for r in recs:
        if r.get("action") == "prompt" and start - 600 <= int(r.get("ts") or 0) <= end \
                and r.get("prompt_head") and r["prompt_head"] not in out:
            out.append(r["prompt_head"])
    return [redact(p)[:120] for p in out[:3]]


def item_of(ctx, summary, prompts, ws_label=None):
    """What the model sees about one context. Redacted, short, no paths: a directory NAME."""
    return {"cwd": redact(_basename(ctx.get("cwd")))[:60],
            "workspace": redact(ctx.get("ws_label") or ws_label or "")[:60],
            "tab": redact(ctx.get("tab_label") or "")[:60],
            "pane": redact(ctx.get("pane_label") or "")[:60],
            "summary": redact(summary)[:120], "prompts": prompts}


def item_key(item):
    return hashlib.sha1(json.dumps(item, sort_keys=True).encode()).hexdigest()[:16]


SYSTEM = (
    "You label terminal sessions for one person's private productivity log. The person is a "
    "DevOps / platform engineer working in a terminal, often with AI coding agents. For EACH "
    "item return an object with: k (copy the item's k), "
    "task (the id of the TASK this session is clearly about, or null; only ids from the TASKS "
    "list), project (one of PROJECTS if the session clearly belongs to it, else null), "
    "activity (max 10 words, specific: what was being done), "
    "verdict (exactly one of: work, delegated, unproductive; work if it is part of the job). "
    'Reply with JSON only: {"items": [ ... ]}'
)


def llm_label(batch, tasks, projects, model):
    """{k: label} from the local model, or {} if it is unavailable. Loopback only.

    The task must be one that was offered and the project one that is already known; the
    verdict one of three words. Anything else is dropped rather than repaired."""
    payload = {
        "model": model, "stream": False, "format": "json", "think": False,
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": json.dumps({
                "TASKS": [{"id": t["id"], "desc": t["desc"], "project": t.get("project")}
                          for t in tasks],
                "PROJECTS": sorted(projects),
                "ITEMS": [dict(b["item"], k=b["k"]) for b in batch]})},
        ],
    }
    req = urllib.request.Request(OLLAMA, json.dumps(payload).encode(),
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as fh:
            body = json.loads(fh.read())
        items = json.loads(body["message"]["content"]).get("items", [])
    except (urllib.error.URLError, OSError, ValueError, KeyError, TypeError):
        return {}
    ids = {t["id"] for t in tasks}
    keys = {b["k"] for b in batch}
    return {it["k"]: accept(it, ids, projects) for it in items if isinstance(it, dict)
            and it.get("k") in keys} if isinstance(items, list) else {}


def accept(it, ids, projects):
    """What of one model answer is believed: a task that was OFFERED, a project that is
    already KNOWN, a verdict from the closed set, an activity with secrets redacted. Applied
    again to whatever comes back from the cache, so no path trusts the model's own word."""
    it = it if isinstance(it, dict) else {}
    out = {"task": it.get("task") if it.get("task") in ids else None,
           "project": it.get("project") if it.get("project") in projects else None,
           "activity": redact(str(it.get("activity") or ""))[:120],
           "verdict": it.get("verdict") if it.get("verdict") in VERDICTS else None}
    if it.get("model"):
        out["model"] = it["model"]
    return out


def known_projects(tasks):
    repo = binding._repo_map()
    return {t["project"] for t in tasks if t.get("project")} | \
           {p for p in repo.values() if isinstance(p, str)}


def agent_share(a0, a1, spans):
    return webclass._overlap(a0, a1, spans) / max(1, a1 - a0)


def _verdict(resolved, model_verdict, share):
    if resolved:
        return "work"           # attached to a task or a known project: part of the job
    if model_verdict == "work":
        return "work"
    if share >= webclass.DELEGATED_SHARE:
        return "delegated"      # wandering is fine while an agent carries the work
    return "unproductive" if model_verdict in (None, "unproductive") else model_verdict


# -- the day -----------------------------------------------------------------------------

def classify(day, now=None, use_llm=True):
    """Label every terminal second of `day`. Returns the rows written (see ROW)."""
    conf = config.web()
    model = conf.get("model", DEFAULT_MODEL)
    now = int(now or time.time())
    t0 = int(datetime.combine(day, dtime.min).astimezone().timestamp())
    t1 = int((datetime.combine(day, dtime.min) + timedelta(days=1)).astimezone().timestamp())
    windows = window_segments(day, datetime.fromtimestamp(now).astimezone())
    tasks = load_tasks()
    sessions = load_sessions()
    agents = webclass.agent_spans(day)
    snap = live_snapshot()
    today = datetime.fromtimestamp(now).date() == day

    with dbs.open_private() as conn:
        pieces = cut(windows, load_spans(conn, t0, t1, now))
        for pc in pieces:
            sp = pc["span"]
            pc["prelog"] = sp is None
            if sp is None:         # before the focus log: the workspace in the title, nothing more
                ws = parse_title(pc["title"])
                ctx = {"ws_label": ws}
                if today:           # the live workspace is evidence for today only
                    live = workspace_context(ws, snap)
                    # ...and only after its session began: the same workspace may have held
                    # other work earlier today, which the live session must not absorb
                    recs = sessions.get(live.get("agent_session")) or []
                    if live.get("agent_session") and not (recs and int(recs[0].get("ts") or 0) <= pc["start"]):
                        live.pop("agent_session", None)
                        live.pop("ticket_token", None)
                    ctx.update(live)
                pc["ctx"] = ctx
            else:
                pc["ctx"] = sp
            pc["res"] = resolve(pc["ctx"], tasks, sessions, pc["start"], pc["end"])
            if pc["res"] and pc["res"]["by"] is None:
                pc["agent_hint"] = pc["res"]["agent_name"]
                pc["res"] = None
            else:
                pc["agent_hint"] = (pc["res"] or {}).get("agent_name")

        # leftovers go to the model, one question per distinct context
        left = {}
        for pc in pieces:
            if pc["res"]:
                continue
            c = pc["ctx"]
            ws_label = c.get("ws_label")
            it = item_of(c, summary_of(snap, c) if today and not pc["prelog"] else "",
                         prompts_in(sessions, c, pc["start"], pc["end"]), ws_label)
            pc["item"], pc["k"] = it, item_key(it)
            left.setdefault(pc["k"], {"k": pc["k"], "item": it})
        projects = known_projects(tasks)
        try:        # a task made from untracked time belongs to that one day, not to other days
            promoted = {r[0] for r in conn.execute("SELECT task_uuid FROM untracked_claim WHERE decided = 'promoted'")}
        except Exception:       # noqa: BLE001 -- table missing on an unmigrated db
            promoted = set()
        offered = [t for t in tasks if t.get("open") and t["uuid"] not in promoted][:OFFERED]
        cache = {}
        if left:
            cache = {r[0]: json.loads(r[1]) for r in conn.execute(
                "SELECT key, label FROM term_label_cache WHERE key IN (%s)" % ",".join("?" * len(left)),
                list(left))}
        todo = [v for k, v in left.items() if k not in cache]
        if use_llm:
            for i in range(0, len(todo), BATCH):
                got = llm_label(todo[i:i + BATCH], offered, projects, model)
                for k, lab in got.items():
                    lab = dict(accept(lab, {t["id"] for t in offered}, projects), model=model)
                    cache[k] = lab
                    conn.execute("INSERT OR REPLACE INTO term_label_cache(key, label, created_unix)"
                                 " VALUES(?,?,?)", (k, json.dumps(lab), now))
                conn.commit()

        by_id = {t["id"]: t for t in offered}
        rows = []
        for pc in pieces:
            c, res = pc["ctx"], pc["res"]
            task = project = ticket = lab = None
            activity, by, mdl = "", "none", None
            if res:
                task, ticket, project, by = res["task"], res["ticket"], res["project"], res["by"]
                activity = (task or {}).get("desc") or " ".join(
                    x for x in (ticket or project, _basename(c.get("cwd"))) if x)
            else:
                lab = accept(cache.get(pc["k"]), set(by_id), projects) if pc["k"] in cache else {}
                task = by_id.get(lab.get("task"))
                project = lab.get("project") or (task or {}).get("project")
                activity = lab.get("activity") or c.get("ws_label") or "terminal"
                by = ("title" if pc["prelog"] else "llm") if lab else ("title" if pc["prelog"] else "none")
                mdl = lab.get("model")
            if res and pc["prelog"]:
                by = "title"           # evidence came from today's workspace, not a focus span
            share = agent_share(pc["start"], pc["end"], agents)
            verdict = _verdict(bool(task or project or (res and res["ticket"])),
                               (lab or {}).get("verdict"), share)
            rows.append({
                "start": pc["start"], "end": pc["end"], "pane_id": c.get("pane_id"),
                "terminal_id": c.get("terminal_id"), "agent_session": c.get("agent_session"),
                "agent_name": pc.get("agent_hint") if not res else res["agent_name"],
                "task_uuid": (task or {}).get("uuid"),
                "ref": ticket or (task or {}).get("ref"), "project": project,
                "activity": redact(activity)[:120], "verdict": verdict, "by": by, "model": mdl})
        out = write(conn, day, merge(rows))
    return out


ROW = ("day", "start_unix", "end_unix", "seconds", "pane_id", "terminal_id", "agent_session",
       "agent_name", "task_uuid", "ref", "project", "activity", "verdict", "labelled_by", "model")


def merge(rows):
    """Adjacent pieces that resolved identically are one segment."""
    out = []
    ident = ("pane_id", "terminal_id", "agent_session", "agent_name", "task_uuid", "ref",
             "project", "activity", "verdict", "by", "model")
    for r in sorted(rows, key=lambda r: r["start"]):
        p = out[-1] if out else None
        if p and all(p[k] == r[k] for k in ident) and r["start"] - p["end"] <= MERGE_GAP:
            p["end"] = max(p["end"], r["end"])
            p["seconds"] += r["end"] - r["start"]
        else:
            out.append(dict(r, seconds=r["end"] - r["start"]))
    return out


def apply_claims(conn, d, segs):
    """Human work segments with a project but no ticket and no task take the task the user promoted that
    (day, project) to. Attribution only: seconds, verdict and project are untouched."""
    try:
        claims = {r[0]: (r[1], r[2]) for r in conn.execute(
            "SELECT project, task_uuid, ref FROM untracked_claim WHERE day = ? AND decided = 'promoted'", (d,))}
    except Exception:       # noqa: BLE001 -- table missing on an unmigrated db: no claims
        return segs
    out = []
    for s in segs:
        human = not s.get("agent_name") and s.get("verdict") == "work"      # only what candidates() offered
        c = claims.get(s.get("project")) if human and s.get("project") and not s.get("ref") and not s.get("task_uuid") else None
        out.append(dict(s, task_uuid=c[0], ref=c[1], by="claim") if c else s)
    return out


def write(conn, day, segs):
    """Replace one day: derived data, so a rerun is not an append."""
    d = day.isoformat()
    segs = apply_claims(conn, d, segs)
    rows = [(d, s["start"], s["end"], int(s["seconds"]), s["pane_id"], s["terminal_id"],
             s["agent_session"], s["agent_name"], s["task_uuid"], s["ref"], s["project"],
             s["activity"], s["verdict"], s["by"], s["model"]) for s in segs]
    conn.execute("DELETE FROM term_segment WHERE day = ?", (d,))
    conn.execute("DELETE FROM term_day WHERE day = ?", (d,))
    conn.executemany("INSERT INTO term_segment(" + ",".join(ROW) + ") VALUES("
                     + ",".join("?" * len(ROW)) + ")", rows)
    conn.execute(
        "INSERT INTO term_day(day, task_uuid, ref, project, agent_name, verdict, seconds)"
        " SELECT day, COALESCE(task_uuid,''), COALESCE(ref,''), COALESCE(project,''),"
        " COALESCE(agent_name,''), verdict, SUM(seconds) FROM term_segment WHERE day = ?"
        " GROUP BY 1,2,3,4,5,6", (d,))
    conn.commit()
    return rows


def first_day():
    """Oldest day with anything to attribute: the focus log, else the window bucket."""
    best = None
    try:
        with dbs.open_private(readonly=True) as conn:
            v = conn.execute("SELECT MIN(start_unix) FROM focus_span").fetchone()[0]
            best = datetime.fromtimestamp(v).date() if v else None
    except Exception:       # noqa: BLE001 -- table missing: fall through to the window bucket
        pass
    try:
        meta = aw._get("/buckets/").get(aw.bucket("currentwindow"), {})
        created = meta.get("created")
        if created:
            d = datetime.fromisoformat(created.replace("Z", "+00:00")).astimezone().date()
            best = min(best, d) if best else d
    except SystemExit:
        pass
    return best
