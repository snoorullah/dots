"""Worked time, read from what timetrack already recorded on this machine.

Read-only by construction: sqlite is opened `mode=ro`, so a bug here cannot move a
payroll number. Nothing leaves the machine; the one HTTP call (ActivityWatch) goes to
loopback and bypasses any proxy, so a poisoned HTTP_PROXY cannot redirect it.
"""
import calendar
import json
import os
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


def day_bounds(d):
    """[start, end) of a local day. Built from dates, not 86400 s, so a DST day is 23/25 h."""
    return day_start(d), day_start(d + timedelta(days=1))


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
    t0, t1 = day_start(first), day_start(last + timedelta(days=1))
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
        a, b = day_bounds(d)
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
        out.append((s, e, tags[0] if len(tags) >= 2 else "unassigned"))
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


def app_seconds(t0, t1, now=None, cached_only=False):
    """[(app, seconds)] from the window watcher, cached for 10 min so the 60 s cycle stays cheap."""
    now = int(now or time.time())
    cache_path = config.STATE_DIR / "app-cache.json"
    key = f"{t0}:{t1 // 3600}"
    cache = atomic.read_json(cache_path, {}) or {}
    hit = cache.get(key)
    if hit and (cached_only or now - hit["at"] < APP_CACHE_SEC):
        return [tuple(x) for x in hit["apps"]]
    if cached_only:
        return []
    try:
        bucket = next(n for n, m in _aw("/buckets/").items() if m.get("type") == "currentwindow")
        q = urllib.parse.urlencode({"start": datetime.fromtimestamp(t0).astimezone().isoformat(),
                                    "end": datetime.fromtimestamp(t1).astimezone().isoformat(), "limit": 100000})
        events = _aw(f"/buckets/{urllib.parse.quote(bucket)}/events?{q}", timeout=8)
    except (OSError, ValueError, StopIteration):
        return [tuple(x) for x in hit["apps"]] if hit else []
    acc = {}
    for e in events:
        app = (e.get("data") or {}).get("app")
        if app:
            acc[app] = acc.get(app, 0) + int(e.get("duration") or 0)
    apps = sorted(acc.items(), key=lambda kv: -kv[1])[:8]
    cache = {k: v for k, v in cache.items() if now - v.get("at", 0) < 86400}
    cache[key] = {"at": now, "apps": apps}
    atomic.write_json(cache_path, cache)
    return apps


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
