"""dots-task: a Claude session declares which task it is working on. Everything here is local.

The rule is "no agent works without a declared task". This module holds the state and the
CLI; gate.py holds the hooks that enforce it. The state, under STATE_DIR:

    declared/<sess>.json   what the session declared: a task, or an exemption with a reason
    live/<sess>.json       {sess, cwd, pane, ts}: written by the hook so a CLI that cannot see
                           its session id can still find it (outside herdr)
    task-log.jsonl         one line per declare / new / switch / none, for the daily brief

Which session is "this" one (resolve_session), first match wins:
    1. env DOTS_SESSION_ID, CLAUDE_CODE_SESSION_ID, CLAUDE_SESSION_ID. Claude Code exports
       CLAUDE_CODE_SESSION_ID to every Bash tool subprocess, so inside a session this is exact.
    2. env HERDR_PANE_ID -> the newest live/ or sessions/ record for that pane.
    3. the newest live/ or sessions/ record whose cwd is this directory (or a parent of it).

Tickets are LOCAL Taskwarrior tasks. Nothing here talks to GitHub, an ERP or any remote.
"""
import argparse
import json
import os
import re
import sys
import time
import uuid as uuidlib

from . import atomic, config, herdr, names, tw

SESS_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
PANE_RE = re.compile(r"^[A-Za-z0-9:_-]{1,40}$")
PROJECT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$")
SESS_ENV = ("DOTS_SESSION_ID", "CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID")
DECL, LIVE, LOG = "declared", "live", "task-log.jsonl"
TOKEN_TTL_MS = 4 * 3600 * 1000          # herdr caps ttl at 86 400 000
MAX_AGE = 24 * 3600
LOG_CAP_BYTES = 200_000


class TaskError(Exception):
    pass


def clean(s, n=200):
    """One line, no control characters, at most n characters."""
    return " ".join("".join(c if c.isprintable() else " " for c in str(s or "")).split())[:n]


# ---- state -----------------------------------------------------------------------------

def _p(kind, sess):
    return config.STATE_DIR / kind / f"{sess}.json"


def read_decl(sess):
    d = atomic.read_json(_p(DECL, sess)) if sess and SESS_RE.match(sess) else None
    return d if isinstance(d, dict) and d.get("v") == 1 else None


def write_decl(sess, **kw):
    rec = {"v": 1, "sess": sess, "ts": int(time.time())}
    rec.update(kw)
    atomic.write_json(_p(DECL, sess), rec)
    return rec


def declared_ok(d):
    """A declaration opens the gate: a task, or an explicit exemption."""
    return bool(d) and (bool(d.get("exempt")) or bool(d.get("uuid")))


def touch_live(sess, cwd, pane):
    atomic.write_json(_p(LIVE, sess), {"v": 1, "sess": sess, "cwd": cwd, "pane": pane, "ts": int(time.time())})


def log_event(kind, sess, **kw):
    path = config.STATE_DIR / LOG
    row = {"v": 1, "ts": int(time.time()), "kind": kind, "sess": sess}
    row.update({k: v for k, v in kw.items() if v is not None})
    try:
        if path.exists() and path.stat().st_size > LOG_CAP_BYTES:
            lines = path.read_text(encoding="utf-8").splitlines()
            atomic.write_text(path, "\n".join(lines[-1000:]) + "\n")
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    except OSError:
        pass


def read_log(t0, t1):
    out = []
    try:
        for line in (config.STATE_DIR / LOG).read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if isinstance(r, dict) and t0 <= int(r.get("ts") or 0) < t1:
                out.append(r)
    except OSError:
        pass
    return out


# ---- which session is this --------------------------------------------------------------

def _records(now):
    recs = []
    for kind in (LIVE, "sessions"):
        d = config.STATE_DIR / kind
        for f in d.glob("*.json") if d.is_dir() else []:
            r = atomic.read_json(f)
            if (isinstance(r, dict) and SESS_RE.match(str(r.get("sess") or "")) and r.get("action") != "end"
                    and now - int(r.get("ts") or 0) <= MAX_AGE):
                recs.append(r)
    return recs


def resolve_session(env=None, cwd=None, now=None):
    """(session id, how) or (None, None)."""
    env = os.environ if env is None else env
    for k in SESS_ENV:
        v = env.get(k) or ""
        if SESS_RE.match(v):
            return v, k
    now = int(now or time.time())
    recs = _records(now)
    pane = env.get("HERDR_PANE_ID") or ""
    if pane:
        hit = [r for r in recs if r.get("pane") == pane]
        if hit:
            return max(hit, key=lambda r: r.get("ts") or 0)["sess"], "pane"
    cwd = str(cwd or os.getcwd())
    hit = [r for r in recs if r.get("cwd") and (cwd == r["cwd"] or cwd.startswith(r["cwd"].rstrip("/") + "/"))]
    if hit:
        return max(hit, key=lambda r: r.get("ts") or 0)["sess"], "cwd"
    return None, None


def pane_of(sess, env=None):
    env = os.environ if env is None else env
    p = env.get("HERDR_PANE_ID") or ""
    if PANE_RE.match(p):
        return p
    for kind in (LIVE, "sessions"):
        r = atomic.read_json(_p(kind, sess))
        if isinstance(r, dict) and PANE_RE.match(str(r.get("pane") or "")):
            return r["pane"]
    return None


# ---- herdr token ------------------------------------------------------------------------

def refresh_token(pane, value, timeout=1.0):
    """Show the ticket in the herdr sidebar (`$ticket`). Display metadata only; pane id FIRST."""
    if not pane or not PANE_RE.match(pane):
        return
    value = re.sub(r"[^A-Za-z0-9:_./#-]", "-", str(value or "no-task"))[:40] or "no-task"
    herdr.run(["pane", "report-metadata", pane, "--source", "dots-task", "--token", f"ticket={value}",
               "--ttl-ms", str(TOKEN_TTL_MS)], timeout=timeout)


# ---- tasks ------------------------------------------------------------------------------

def find(arg):
    """One pending task by ref, taskwarrior id or uuid."""
    a = (arg or "").strip()
    if tw.UUID_RE.fullmatch(a) or a.isdigit():
        rows = [r for r in tw.export(a) if r.get("status") == "pending"]
    elif tw.valid_ref(a):
        r = tw.by_ref(a)
        rows = [r] if r and r.get("status") == "pending" else []
    else:
        raise TaskError(f"not a ref, id or uuid: {a!r}")
    if not rows:
        raise TaskError(f"no open task matches {a!r} (see `dots-task list`)")
    return rows[0]


def label(t):
    return t.get("ref") or f"id:{t.get('id')}"


def declare(sess, t, env=None, kind="declare"):
    """Bind a session to a task: UDAs, start, declaration file, session record, herdr token."""
    env = os.environ if env is None else env
    pane = pane_of(sess, env)
    wspace = pane.split(":", 1)[0] if pane and ":" in pane else None
    prev = read_decl(sess)
    others = [x for x in tw.export("status:pending", f"sess.is:{sess}") if x["uuid"] != t["uuid"]]
    for o in others:
        if o.get("start_ts"):
            tw.stop(o["uuid"])
        if o.get("src") == "claude" and not o.get("ref"):
            tw.drop(o["uuid"])                    # ingest's prompt-head placeholder: this task replaces it
        else:
            tw.clear(o["uuid"], "sess", "pane", "wspace")
    tw.modify(t["uuid"], agent=names.for_session(sess), sess=sess, pane=pane, wspace=wspace)
    if not t.get("start_ts"):
        tw.start(t["uuid"])
    d = write_decl(sess, uuid=t["uuid"], ref=t.get("ref"), title=clean(t.get("desc"), 120),
                   project=t.get("project") or "", pane=pane)
    rec = atomic.read_json(_p("sessions", sess))
    if isinstance(rec, dict) and t.get("ref"):
        rec["ticket"] = t["ref"]                    # the overview recorder keeps it sticky from here
        atomic.write_json(_p("sessions", sess), rec)
    refresh_token(pane, label(t))
    log_event(kind if kind == "new" else "switch" if prev and prev.get("uuid") not in (None, t["uuid"]) else kind, sess,
              ref=t.get("ref"), project=t.get("project"))
    return d


def new_task(title, project, parent=None, tags=()):
    title = clean(title)
    if not title:
        raise TaskError("a title is required")
    if project and not PROJECT_RE.match(project):
        raise TaskError(f"odd project name {project!r}")
    attrs = {}
    if parent:
        p = tw.by_ref(parent) if tw.valid_ref(parent) else None
        if p is None:
            raise TaskError(f"no parent task {parent!r}")
        attrs["parentref"] = parent
        project = project or p.get("project")
    if not project:
        raise TaskError("--project is required (or --parent, to inherit one)")
    ref = "local:" + uuidlib.uuid4().hex[:6]
    while tw.by_ref(ref):
        ref = "local:" + uuidlib.uuid4().hex[:6]
    uid = tw.add(title, tags=("claude", "mirror") + tuple(tags), src="claude", ref=ref, project=project, **attrs)
    return tw.export(uid)[0]


def listing(sess, grep=None, project=None, limit=25):
    rows = []
    for t in tw.pending():
        if t.get("src") == "claude" and not t.get("ref"):
            continue                                # ingest placeholders are not choices
        if project and t.get("project") != project:
            continue
        if grep and grep.lower() not in (t.get("desc") or "").lower() + " " + (t.get("ref") or "").lower():
            continue
        rows.append(t)
    rows.sort(key=lambda t: (not t.get("start_ts"), -(t.get("entry_ts") or 0)))
    return rows[:limit], len(rows)


def statusline_text(sess):
    d = read_decl(sess)
    if not d:
        return "no task"
    if d.get("exempt"):
        return "untracked"
    return f"{d.get('ref') or 'task'} {clean(d.get('title'), 28)}".strip()


# ---- CLI --------------------------------------------------------------------------------

def _session(args):
    sess, how = resolve_session()
    if not sess:
        raise TaskError("cannot tell which Claude session this is; set DOTS_SESSION_ID=<session id> or run it from the session's pane")
    return sess


def _show(d):
    if d.get("exempt"):
        return f"untracked: {d.get('reason')}"
    return f"{d.get('ref') or d.get('uuid', '')[:8]}  {d.get('title')}" + (f"  [{d['project']}]" if d.get("project") else "")


def cmd_declare(a):
    sess = _session(a)
    d = declare(sess, find(a.target), kind="declare")
    print("task: " + _show(d))


def cmd_new(a):
    sess = _session(a)
    t = new_task(a.title, a.project, a.parent)
    d = declare(sess, t, kind="new")
    print("created and declared: " + _show(d))


def cmd_none(a):
    sess = _session(a)
    reason = clean(a.reason, 200)
    if len(reason) < 3:
        raise TaskError("say why (a few words): dots-task none \"quick question, no files touched\"")
    write_decl(sess, exempt=True, reason=reason)
    pane = pane_of(sess)
    refresh_token(pane, "untracked")
    log_event("none", sess, reason=reason)
    print("untracked: " + reason)


def cmd_current(a):
    sess = _session(a)
    d = read_decl(sess)
    print(_show(d) if declared_ok(d) else "none declared (dots-task list, then dots-task declare <ref>)")
    return 0 if declared_ok(d) else 1


def cmd_list(a):
    from . import report              # lazy: the hooks import this module and must start fast
    rows, total = listing(None, a.grep, a.project, a.limit)
    for t in rows:
        mark = "*" if t.get("start_ts") else " "
        print(f"{mark} {label(t):<18} {(t.get('project') or '-'):<12} {report.scrub(t.get('desc'))[:70]}")
    if total > len(rows):
        print(f"  ... {total - len(rows)} more: --grep WORD, --project P, --limit N")
    if not rows:
        print("no open tasks match; create one: dots-task new \"<title>\" --project <p>")


def cmd_promote(a):
    t = find(a.local)
    if not (t.get("ref") or "").startswith("local:"):
        raise TaskError("only local: tasks are promoted")
    if not tw.valid_ref(a.new_ref) or tw.by_ref(a.new_ref):
        raise TaskError(f"{a.new_ref!r} is not a free, valid ref")
    tw.modify(t["uuid"], ref=a.new_ref)
    tw.run([t["uuid"], "modify", "-claude"])
    log_event("promote", None, ref=a.new_ref)
    print(f"{t['ref']} is now {a.new_ref}")


def cmd_statusline(a):
    try:
        sess = str(json.loads(sys.stdin.read(65536) or "{}").get("session_id") or "")
    except ValueError:
        sess = ""
    if SESS_RE.match(sess):
        print(statusline_text(sess))


def main(argv):
    ap = argparse.ArgumentParser(prog="dots-task", description="declare the task this Claude session is working on")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("declare", help="bind this session to an open task (ref, id or uuid)")
    p.add_argument("target")
    p.set_defaults(fn=cmd_declare)
    p = sub.add_parser("switch", help="same as declare; stops the previous task's clock")
    p.add_argument("target")
    p.set_defaults(fn=cmd_declare)
    p = sub.add_parser("new", help="create a local task (src=claude) and declare it")
    p.add_argument("title")
    p.add_argument("--project")
    p.add_argument("--parent")
    p.set_defaults(fn=cmd_new)
    p = sub.add_parser("none", help="trivial non-work: open the gate for this session, logged")
    p.add_argument("reason")
    p.set_defaults(fn=cmd_none)
    sub.add_parser("current", help="the task this session declared").set_defaults(fn=cmd_current)
    p = sub.add_parser("list", help="open tasks to pick from")
    p.add_argument("--grep")
    p.add_argument("--project")
    p.add_argument("--limit", type=int, default=25)
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("promote", help="give a local: task a real ref (e.g. after you filed the ticket)")
    p.add_argument("local")
    p.add_argument("new_ref")
    p.set_defaults(fn=cmd_promote)
    sub.add_parser("statusline", help="status line segment; reads the status line JSON on stdin").set_defaults(fn=cmd_statusline)
    a = ap.parse_args(argv)
    try:
        return a.fn(a) or 0
    except (TaskError, tw.TwError) as e:
        print(f"dots-task: {e}", file=sys.stderr)
        return 1
