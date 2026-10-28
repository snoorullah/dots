"""Worked time, read from what timetrack already recorded on this machine.

Read-only by construction: sqlite is opened `mode=ro`, so a bug here cannot move a
payroll number. Nothing leaves the machine; the one HTTP call (ActivityWatch) goes to
loopback and bypasses any proxy, so a poisoned HTTP_PROXY cannot redirect it.
"""
import calendar
import json
import os
import re
import sqlite3
import subprocess
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

from . import atomic, config


def _ro(path):
    if not path.exists():
        return None
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
    conn.row_factory = sqlite3.Row
    return conn


def day_start(d):
    """Local midnight of a date, as epoch seconds."""
    return int(datetime(d.year, d.month, d.day).timestamp())


# A day is a WORK SESSION, login -> logout, never a clock boundary: an evening past midnight
# is that session's day. timetrack's work_session carries attendance_day (fixed when the
# session opened). A day's bounds are its sessions' first open and last close (now while
# one is open). Dates with no session fall back to local midnight, which has nothing in it.

def _sessions():
    """{attendance_day (date): [opened_unix, closed_unix or None]} merged per day."""
    conn = _ro(config.TT_DIR / "work.db")
    if conn is None:
        return {}
    out = {}
    try:
        for r in conn.execute("SELECT attendance_day, opened_unix, closed_unix FROM work_session"):
            try:
                d = datetime.strptime(r["attendance_day"], "%Y-%m-%d").date()
            except (TypeError, ValueError):
                continue
            cur = out.setdefault(d, [r["opened_unix"], r["closed_unix"]])
            cur[0] = min(cur[0], r["opened_unix"])
            cur[1] = None if (cur[1] is None or r["closed_unix"] is None) else max(cur[1], r["closed_unix"])
    except sqlite3.Error:
        return {}
    finally:
        conn.close()
    return out


def workday(now):
    """The day of the session `now` is in, else of the last session before it, else the date."""
    best = None
    for d, (a, b) in _sessions().items():
        if a <= now and (best is None or a > best[1]):
            best = (d, a)
    return best[0] if best else datetime.fromtimestamp(now).date()


def workday_start(d):
    """When day d began: its first login. Without a session that day, the first login of any
    later day (so a week starting on a day off begins at the next login), else midnight."""
    days = _sessions()
    later = [a for x, (a, b) in days.items() if x >= d]
    return min(later) if later else day_start(d)


def day_bounds(d, now=None):
    """[login, logout) of day d; an open session runs to now."""
    se = _sessions().get(d)
    if not se:
        return day_start(d), day_start(d + timedelta(days=1))
    now = int(now or time.time())
    end = se[1] if se[1] is not None else min(now, se[0] + OPEN_CAP)   # as _end caps a lost session
    return se[0], max(se[0], end)


def _clip(a, b, t0, t1):
    return max(0, min(b, t1) - max(a, t0))


OPEN_CAP = 16 * 3600


def _end(r, now):
    """Where a session ends. One the clock never closed (the machine slept, the daemon died)
    is capped, so a forgotten session cannot count yesterday evening as today's work."""
    return r["closed_unix"] or min(now, r["opened_unix"] + OPEN_CAP)


def _union(spans):
    """Merge overlapping [a, b) spans: two sessions open at once are still one hour of wall clock."""
    out = []
    for a, b in sorted(s for s in spans if s[1] > s[0]):
        if out and a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def worked_by_day(first, last, now=None):
    """{date: seconds} for first..last inclusive: session spans minus deductions."""
    now = int(now or time.time())
    out = {}
    d = first
    while d <= last:
        out[d] = 0
        d += timedelta(days=1)
    conn = _ro(config.TT_DIR / "work.db")
    if conn is None:
        return out
    t0, t1 = workday_start(first), workday_start(last + timedelta(days=1))
    try:
        sess = [(r["opened_unix"], _end(r, now), r["id"]) for r in conn.execute(
            "SELECT id, opened_unix, closed_unix FROM work_session"
            " WHERE opened_unix < ? AND COALESCE(closed_unix, ?) > ?", (t1, now, t0))]
        ded = [(r["start_unix"], r["end_unix"], r["session_id"]) for r in conn.execute(
            "SELECT start_unix, end_unix, session_id FROM deduction"
            " WHERE end_unix IS NOT NULL AND start_unix < ? AND end_unix > ?", (t1, t0))]
    except sqlite3.Error:
        return out
    finally:
        conn.close()
    for d in out:
        a, b = day_bounds(d, now)
        out[d] = _net(sess, ded, a, b)
    return out


def _net(sess, ded, t0, t1):
    s = _union((x[0], x[1]) for x in sess)
    d = _union((x[0], x[1]) for x in ded)
    return max(0, sum(_clip(a, b, t0, t1) for a, b in s) - sum(_clip(a, b, t0, t1) for a, b in d))


def worked_sec(t0, t1, now=None):
    """Seconds of worked time between two epochs (not day-aligned)."""
    now = int(now or time.time())
    conn = _ro(config.TT_DIR / "work.db")
    if conn is None:
        return 0
    try:
        sess = [(r["opened_unix"], _end(r, now)) for r in conn.execute(
            "SELECT opened_unix, closed_unix FROM work_session"
            " WHERE opened_unix < ? AND COALESCE(closed_unix, ?) > ?", (t1, now, t0))]
        ded = [(r["start_unix"], r["end_unix"]) for r in conn.execute(
            "SELECT start_unix, end_unix FROM deduction"
            " WHERE end_unix IS NOT NULL AND start_unix < ? AND end_unix > ?", (t1, t0))]
    except sqlite3.Error:
        return 0
    finally:
        conn.close()
    return _net(sess, ded, t0, t1)


def ref_seconds(t0, t1):
    """[(ticket, seconds)] from the clock's run intervals, largest first."""
    conn = _ro(config.TT_DIR / "work.db")
    if conn is None:
        return []
    acc = {}
    try:
        for r in conn.execute("SELECT ticket, start_unix, end_unix FROM v_run_interval"
                              " WHERE ticket IS NOT NULL AND start_unix < ? AND end_unix > ?", (t1, t0)):
            acc[r["ticket"]] = acc.get(r["ticket"], 0) + _clip(r["start_unix"], r["end_unix"], t0, t1)
    except sqlite3.Error:
        return []
    finally:
        conn.close()
    return sorted(((k, v) for k, v in acc.items() if v > 0), key=lambda kv: -kv[1])


def project_intervals(t0, now):
    """[(start, end, project)] from timewarrior since t0. The task hook tags project first.

    Fetched ONCE per cycle and bucketed in Python; four `timew export` calls would blow the
    fast cycle's time budget.
    """
    fmt = "%Y%m%dT%H%M%S"
    # timew offers to CREATE its database when it is missing; an overview must never write one
    db = Path(os.environ.get("TIMEWARRIORDB") or config.HOME / ".local/share/timewarrior")
    if not db.is_dir():
        return []
    a, b = (time.strftime(fmt, time.gmtime(x)) + "Z" for x in (t0, now))
    try:
        p = subprocess.run(["timew", "export", a, "-", b], capture_output=True, text=True,
                           timeout=10, stdin=subprocess.DEVNULL)
        rows = json.loads(p.stdout) if p.returncode == 0 else []
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    out = []
    for r in rows:
        try:
            s = _utc(r["start"])
            e = _utc(r["end"]) if r.get("end") else int(now)
        except (KeyError, ValueError):
            continue
        tags = r.get("tags") or []
        # the hook tags [project, description], but timew stores tags sorted, so "first" is not
        # the project: a project name has no spaces, a task description almost always does
        words = [t for t in tags if t and not any(c.isspace() for c in t)]
        out.append((s, e, words[0] if len(tags) >= 2 and len(words) == 1 else "unassigned"))
    return out


def project_seconds(intervals, t0, t1):
    """[(project, seconds)] of the intervals inside [t0, t1], largest first."""
    acc = {}
    for s, e, proj in intervals:
        acc[proj] = acc.get(proj, 0) + _clip(s, e, t0, t1)
    return sorted(((k, v) for k, v in acc.items() if v > 0), key=lambda kv: -kv[1])


def _utc(s):
    return calendar.timegm(time.strptime(s, "%Y%m%dT%H%M%SZ"))


# -- ActivityWatch, cached ---------------------------------------------------------------

AW = "http://127.0.0.1:5600/api/0"
APP_CACHE_SEC = 600


def _aw(path, timeout=4):
    # ProxyHandler({}) = no proxy, ever: this call is loopback by definition
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(f"{AW}{path}", timeout=timeout) as fh:
        return json.loads(fh.read())


def _aw_ts(e):
    return datetime.fromisoformat(str(e.get("timestamp")).replace("Z", "+00:00")).timestamp()


def app_seconds(t0, t1, now=None, cached_only=False):
    """[(app, seconds)] from the window watcher, cached for 10 min so the 60 s cycle stays cheap."""
    now = int(now or time.time())
    cache_path = config.STATE_DIR / "app-cache.json"
    key = f"v2:{t0}:{t1 // 3600}"
    cache = atomic.read_json(cache_path, {}) or {}
    hit = cache.get(key)
    if hit and (cached_only or now - hit["at"] < APP_CACHE_SEC):
        return [tuple(x) for x in hit["apps"]]
    if cached_only:
        return []
    try:
        buckets = _aw("/buckets/")
        win = next(n for n, m in buckets.items() if m.get("type") == "currentwindow")
        afk = next((n for n, m in buckets.items() if m.get("type") == "afkstatus"), None)
        q = urllib.parse.urlencode({"start": datetime.fromtimestamp(t0).astimezone().isoformat(),
                                    "end": datetime.fromtimestamp(t1).astimezone().isoformat(), "limit": 100000})
        events = _aw(f"/buckets/{urllib.parse.quote(win)}/events?{q}", timeout=8)
        present = _aw(f"/buckets/{urllib.parse.quote(afk)}/events?{q}", timeout=8) if afk else None
    except (OSError, ValueError, StopIteration):
        return [tuple(x) for x in hit["apps"]] if hit else []
    # a window that stays focused while I am away (locked overnight) is not time spent in it:
    # count only the part inside [t0, t1] that overlaps "not-afk"
    here = sorted((_aw_ts(e), _aw_ts(e) + float(e.get("duration") or 0)) for e in (present or [])
                  if (e.get("data") or {}).get("status") == "not-afk")
    acc = {}
    for e in events:
        app = (e.get("data") or {}).get("app")
        if not app:
            continue
        s0 = max(_aw_ts(e), t0)
        s1 = min(_aw_ts(e) + float(e.get("duration") or 0), t1)
        if s1 <= s0:
            continue
        sec = sum(max(0.0, min(s1, b) - max(s0, a)) for a, b in here) if present is not None else s1 - s0
        if sec > 0:
            acc[app] = acc.get(app, 0) + int(sec)
    apps = sorted(acc.items(), key=lambda kv: -kv[1])[:8]
    cache = {k: v for k, v in cache.items() if now - v.get("at", 0) < 86400}
    cache[key] = {"at": now, "apps": apps}
    atomic.write_json(cache_path, cache)
    return apps


# -- terminal and browser attention, from timetrack's private.db -------------------------
# term_segment (termclass) says which task / project / agent each terminal second was spent
# on; web_visit (webclass) does the same for the browser. Read-only like everything here.
# private.db holds pane titles and directories, so only the labels below are ever read out of
# it -- never a title, a cwd or a prompt -- and the six JSON files stay free of them.

TERMINAL_APP = re.compile(r"^(com\.mitchellh\.ghostty|ghostty|kitty|alacritty|foot|"
                          r"org\.wezfurlong\.wezterm|wezterm)", re.IGNORECASE)


def term_segments(t0, t1):
    """[{sec, task_uuid, ref, project, agent, verdict}] clipped to [t0, t1)."""
    conn = _ro(config.TT_DIR / "private.db")
    if conn is None:
        return []
    try:
        rows = conn.execute(
            "SELECT start_unix, end_unix, task_uuid, ref, project, agent_name, verdict, labelled_by"
            " FROM term_segment WHERE start_unix < ? AND end_unix > ?", (t1, t0)).fetchall()
    except sqlite3.Error:
        return []
    finally:
        conn.close()
    return [{"sec": _clip(r["start_unix"], r["end_unix"], t0, t1), "task_uuid": r["task_uuid"],
             "ref": r["ref"], "project": r["project"], "agent": r["agent_name"],
             "verdict": r["verdict"], "by": r["labelled_by"]} for r in rows]


def web_links(t0, t1):
    """[(ticket, task_uuid, seconds)] for browser visits that were tied to something."""
    conn = _ro(config.TT_DIR / "private.db")
    if conn is None:
        return []
    try:
        rows = conn.execute(
            "SELECT start_unix, end_unix, ticket, task_uuid FROM web_visit WHERE start_unix < ?"
            " AND end_unix > ? AND (ticket IS NOT NULL OR task_uuid IS NOT NULL)", (t1, t0)).fetchall()
    except sqlite3.Error:
        return []
    finally:
        conn.close()
    return [(r["ticket"], r["task_uuid"], _clip(r["start_unix"], r["end_unix"], t0, t1)) for r in rows]


def _add(acc, key, sec):
    if key and sec > 0:
        acc[key] = acc.get(key, 0) + sec


def ranked(acc):
    return sorted(((k, v) for k, v in acc.items() if v > 0), key=lambda kv: -kv[1])


def attention(segs, links, uuid_ref, uuid_project):
    """({ref: sec}, {project: sec}, {agent: sec}) of what the person's own attention went on.

    Terminal and browser focus never overlap, so they add. A segment tied only to a task
    still counts for that task's ref and project, via the Taskwarrior maps."""
    refs, projects, agents = {}, {}, {}
    for g in segs:
        _add(refs, g["ref"] or uuid_ref.get(g["task_uuid"]), g["sec"])
        _add(projects, g["project"] or uuid_project.get(g["task_uuid"]), g["sec"])
        _add(agents, g["agent"], g["sec"])
    for ticket, uuid, sec in links:
        _add(refs, ticket or uuid_ref.get(uuid), sec)
        _add(projects, uuid_project.get(uuid), sec)
    return refs, projects, agents


def merge_max(pairs, extra):
    """[(key, sec)] and {key: sec} -> ranked [(key, sec)], the larger figure per key.

    Max, not sum: the clock's run time and timewarrior's intervals measure the same hours
    from another angle, so adding them to attention would count an hour twice."""
    acc = dict(pairs)
    for k, v in extra.items():
        acc[k] = max(acc.get(k, 0), v)
    return ranked(acc)


def _hm(sec):
    m = round(sec / 60)
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def term_detail(segs):
    """"work 3h12m / delegated 20m": the terminal app line read as what it was spent on."""
    acc = {}
    for g in segs:
        # a verdict with no evidence behind it is a default, not a finding: say so
        blind = g["by"] in ("none", "title") and not (g["ref"] or g["project"] or g["task_uuid"])
        _add(acc, "unattributed" if blind else g["verdict"], g["sec"])
    return " \u00b7 ".join(f"{k} {_hm(v)}" for k, v in ranked(acc)[:3])


def clock_state(now=None):
    """The `clock` block of now.json: in / out / away, from timetrack's own state files."""
    now = int(now or time.time())
    intent = atomic.read_json(config.TT_DIR / "away-intent.json")
    if intent and now - int(intent.get("since", 0)) < 4 * 3600:
        return {"state": "away", "awayReason": intent.get("label"), "sinceTs": intent.get("since")}
    c = atomic.read_json(config.TT_DIR / "clock.json") or {}
    st = str(c.get("state") or "").upper()
    since = c.get("updated_unix")
    if st in ("RUNNING", "AMBER", "GRACE"):
        return {"state": "in", "awayReason": None, "sinceTs": since}
    return {"state": "out", "awayReason": None, "sinceTs": since}
