"""sessions.jsonl + herdr + taskwarrior -> tasks.

The Claude hook only records ("session X, pane Y, first words Z"). This is the one place
that turns a record into a Taskwarrior task, so the rule "every piece of work has a task"
is enforced in a single, testable function instead of scattered across hooks.

Idempotent: a task is found by `sess` first and `ref` second, so running it twice in a row
changes nothing.
"""
import os
import time

from . import atomic, config, herdr, names, tw

SESS_DIR = "sessions"
MAX_AGE = 24 * 3600
LOG = "sessions.jsonl"
LOG_CAP = 5000


def prune(now=None, cap=LOG_CAP):
    """Bound the hook's state: sessions.jsonl is a ring of `cap` lines, and a per-session
    file older than MAX_AGE is deleted (load_sessions would skip it anyway)."""
    now = int(now or time.time())
    d = config.STATE_DIR
    log = d / LOG
    try:
        lines = log.read_text(encoding="utf-8").splitlines()
        if len(lines) > cap:
            atomic.write_text(log, "\n".join(lines[-cap:]) + "\n")
    except OSError:
        pass
    removed = 0
    for f in (d / SESS_DIR).glob("*.json") if (d / SESS_DIR).is_dir() else []:
        rec = atomic.read_json(f)
        try:
            ts = int(rec.get("ts") or 0) if isinstance(rec, dict) else 0
            ts = ts or int(f.stat().st_mtime)
            if now - ts > MAX_AGE:
                os.unlink(f)
                removed += 1
        except OSError:
            pass
    return removed


def load_sessions(now=None):
    """The latest record per session seen in the last 24 h that has real work in it."""
    now = int(now or time.time())
    d = config.STATE_DIR / SESS_DIR
    out = []
    try:
        files = list(d.glob("*.json"))
    except OSError:
        return out
    for f in files:
        rec = atomic.read_json(f)
        if not isinstance(rec, dict) or rec.get("v") != 1 or not rec.get("sess"):
            continue
        if now - int(rec.get("ts") or 0) > MAX_AGE:
            continue
        out.append(rec)
    return sorted(out, key=lambda r: r.get("ts") or 0)


def _title(rec, agent):
    head = " ".join(str(rec.get("prompt_head") or "").split())
    return head or f"claude session {agent}"


def _adopt_ticket(t, ticket, by_ref, want):
    """A session task created before the user named a ticket joins that ticket on the next cycle.

    With no task carrying the ticket yet, the session task takes it as its ref. With one
    already (a mirrored ticket), the session coordinates move onto it and the now redundant
    claude placeholder is completed, so the session id never sits on two pending tasks.
    """
    if t is None or t.get("src") != "claude" or t.get("ref") or not ticket or not tw.valid_ref(ticket):
        return t
    other = by_ref.get(ticket)
    if other is None:
        tw.modify(t["uuid"], ref=ticket)
        t["ref"] = ticket
        by_ref[ticket] = t
        return t
    tw.done(t["uuid"])
    return other


def run(now=None, live=None):
    """Make sure every recorded session has a task. Returns {'created': n, 'updated': n}."""
    prune(now)
    live = live if live is not None else herdr.snapshot()
    live_by_sess = {a["sess"]: a for a in (live or []) if a.get("sess")}
    pend = tw.pending()
    by_sess = {t.get("sess"): t for t in pend if t.get("sess")}
    by_ref = {t.get("ref"): t for t in pend if t.get("ref")}
    created = updated = 0
    for rec in load_sessions(now):
        sess = rec["sess"]
        agent = rec.get("agent") or names.for_session(sess)
        pane = (live_by_sess.get(sess) or {}).get("pane") or rec.get("pane")
        wspace = (live_by_sess.get(sess) or {}).get("workspace") or rec.get("workspace")
        ticket = rec.get("ticket")
        want = {"agent": agent, "sess": sess, "pane": pane, "wspace": wspace}
        t = by_sess.get(sess) or (by_ref.get(ticket) if ticket and tw.valid_ref(ticket) else None)
        t = _adopt_ticket(t, ticket, by_ref, want)
        if t is not None:
            diff = {k: v for k, v in want.items() if v and t.get(k) != v}
            # a ref-attached task is somebody else's (a mirrored ticket): only its session
            # coordinates change, never its title, project or src
            if diff:
                tw.modify(t["uuid"], **diff)
                updated += 1
            continue
        if not (rec.get("prompt_head") or ticket):
            continue            # a session that never got a prompt is not work yet
        attrs = dict(want, src="claude")
        if ticket and tw.valid_ref(ticket):
            attrs["ref"] = ticket
        uuid = tw.add(_title(rec, agent), tags=("mirror", "attn"), **attrs)
        created += 1
        t = {"uuid": uuid, **want}
        by_sess[sess] = t
        if ticket:
            by_ref[ticket] = t
    return {"created": created, "updated": updated}
