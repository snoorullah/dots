"""Untracked time -> ticket. Human terminal time on a project with no ticket, offered as a task.

term_day (timetrack's private.db) holds the day's terminal seconds by task / ref / project.
"Untracked on project X" is the rows with no ref and no task_uuid. When that is at least
UNTRACKED_MIN_MINUTES (default 30) for today or yesterday, attention.json gets an `untracked`
item; "Make ticket" creates a LOCAL task and records a claim, and timetrack's termclass then
labels that time with the task (labelled_by 'claim') on every later re-run.

Attribution only: worked / break / payroll numbers are never read or written here, and neither
is work.db. The claim table is created by timetrack's migration (PRIVATE_V9).
"""
import sqlite3
import time
from datetime import date, datetime, timedelta

from . import config, local_tt, task

UNATTRIBUTED = "COALESCE(ref,'') = '' AND COALESCE(task_uuid,'') = ''"


class UntrackedError(Exception):
    pass


def _days(now):
    d = datetime.fromtimestamp(now).date()
    return [d, d - timedelta(days=1)]


def _claims(conn, day):
    try:
        return {r[0]: (r[1], r[2], r[3]) for r in conn.execute(
            "SELECT project, decided, task_uuid, ref FROM untracked_claim WHERE day = ?", (day,))}
    except sqlite3.Error:
        return {}


def candidates(now=None, min_min=None):
    """[{day, project, sec}] with at least min_min minutes of unattributed human work and no decision."""
    now = int(now or time.time())
    min_min = config.Work().untracked_min if min_min is None else min_min
    conn = local_tt._ro(config.TT_DIR / "private.db")
    if conn is None:
        return []
    out = []
    try:
        for d in _days(now):
            day = d.isoformat()
            decided = _claims(conn, day)
            rows = conn.execute(
                f"SELECT project, SUM(seconds) FROM term_day WHERE day = ? AND {UNATTRIBUTED}"
                " AND COALESCE(agent_name,'') = '' AND verdict = 'work' AND COALESCE(project,'') != ''"
                " GROUP BY project", (day,)).fetchall()
            for project, sec in rows:
                if sec >= min_min * 60 and project not in decided and task.PROJECT_RE.match(project):
                    out.append({"day": day, "project": project, "sec": int(sec)})
    except sqlite3.Error:
        return []
    finally:
        conn.close()
    out.sort(key=lambda c: (c["day"], c["sec"]), reverse=True)
    return out


def _dur(sec):
    m = int(sec) // 60
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def items(now=None):
    now = int(now or time.time())
    out = []
    for c in candidates(now):
        end = datetime.combine(date.fromisoformat(c["day"]) + timedelta(days=1), datetime.min.time())
        age = max(0, now - int(end.timestamp()))       # 0 for today
        out.append({
            "id": f"untracked:{c['day']}:{c['project']}", "kind": "untracked",
            "title": f"{_dur(c['sec'])} on {c['project']}, no ticket", "ref": None, "src": "timetrack",
            "url": None, "urgency": "passive", "waiting": False, "ageSec": age, "actor": None, "jump": None,
            "canBreakdown": False, "canPromote": True, "day": c["day"], "project": c["project"], "startedAt": None})
    return out


def _check(day, project):
    try:
        date.fromisoformat(day)
    except ValueError:
        raise UntrackedError(f"not a day (YYYY-MM-DD): {day!r}")
    if not task.PROJECT_RE.match(project or ""):
        raise UntrackedError(f"odd project name {project!r}")


def _open():
    path = config.TT_DIR / "private.db"
    if not path.exists():
        raise UntrackedError("no private.db yet")
    conn = sqlite3.connect(path, timeout=30, isolation_level=None)     # explicit BEGIN IMMEDIATE below
    if not conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'untracked_claim'").fetchone():
        conn.close()
        raise UntrackedError("private.db is not migrated (timetrack migrate)")
    return conn


def relabel(conn, day, project, task_uuid, ref):
    """Point the day's unattributed human work segments on a project at a task, then rebuild term_day."""
    conn.execute(
        f"UPDATE term_segment SET task_uuid = ?, ref = ?, labelled_by = 'claim' WHERE day = ? AND project = ? AND {UNATTRIBUTED}"
        " AND COALESCE(agent_name,'') = '' AND verdict = 'work'",
        (task_uuid, ref, day, project))
    conn.execute("DELETE FROM term_day WHERE day = ?", (day,))
    conn.execute(
        "INSERT INTO term_day(day, task_uuid, ref, project, agent_name, verdict, seconds)"
        " SELECT day, COALESCE(task_uuid,''), COALESCE(ref,''), COALESCE(project,''),"
        " COALESCE(agent_name,''), verdict, SUM(seconds) FROM term_segment WHERE day = ? GROUP BY 1,2,3,4,5,6", (day,))


def promote(day, project, title=None, now=None):
    """Create the local task and the claim. Returns (task, created). A second call is a no-op.
    BEGIN IMMEDIATE first: racing callers queue here, so the check-then-create is one step."""
    _check(day, project)
    conn = _open()
    try:
        conn.execute("BEGIN IMMEDIATE")
        try:
            have = _claims(conn, day).get(project)
            if have and have[0] == "promoted":
                conn.execute("ROLLBACK")
                return {"uuid": have[1], "ref": have[2]}, False
            if not have and not any(c["day"] == day and c["project"] == project for c in candidates(now, 0)):
                raise UntrackedError(f"no untracked time on {project} on {day}")
            t = task.new_task(title or f"{project}: untracked work {day}", project)
            conn.execute("INSERT OR REPLACE INTO untracked_claim(day, project, task_uuid, ref, decided, decided_unix)"
                         " VALUES(?,?,?,?,?,?)", (day, project, t["uuid"], t.get("ref") or "", "promoted", int(now or time.time())))
            relabel(conn, day, project, t["uuid"], t.get("ref") or "")
            conn.execute("COMMIT")
            return t, True
        except BaseException:
            if conn.in_transaction:
                conn.execute("ROLLBACK")
            raise
    finally:
        conn.close()


def ignore(day, project, now=None):
    _check(day, project)
    conn = _open()
    try:
        conn.execute("BEGIN IMMEDIATE")
        try:
            if _claims(conn, day).get(project, ("",))[0] == "promoted":
                conn.execute("ROLLBACK")
                return False
            conn.execute("INSERT OR REPLACE INTO untracked_claim(day, project, task_uuid, ref, decided, decided_unix)"
                         " VALUES(?,?,'','','ignored',?)", (day, project, int(now or time.time())))
            conn.execute("COMMIT")
            return True
        except BaseException:
            if conn.in_transaction:
                conn.execute("ROLLBACK")
            raise
    finally:
        conn.close()
