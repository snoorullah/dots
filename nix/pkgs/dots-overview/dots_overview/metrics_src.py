"""Read-only loaders for metrics.py.

Every loader opens its source `mode=ro`, never writes, and never raises: a missing file,
table or tool returns None (source absent) and records why in a Gaps, so the page can say
"no data" instead of showing a made-up zero. Nothing here names a company, person or host.
"""
import json
import os
import sqlite3
import subprocess
import time
import tomllib
from datetime import datetime
from pathlib import Path

from . import atomic, config, local_tt, tw


class Gaps:
    """What could not be read, per source: {source: [reason, ...]} (first reason wins the line)."""

    def __init__(self):
        self.items = {}

    def add(self, source, reason):
        self.items.setdefault(source, [])
        if reason not in self.items[source]:
            self.items[source].append(reason)

    def get(self, source):
        return self.items.get(source, [])


def _open(name, gaps, source):
    path = config.TT_DIR / name
    try:
        conn = local_tt._ro(path)
    except sqlite3.Error as e:
        gaps.add(source, f"{name} unreadable ({type(e).__name__})")
        return None
    if conn is None:
        gaps.add(source, f"{name} not found")
    return conn


def _q(conn, sql, args, gaps, source, what):
    """rows as dicts, or None when the table / view does not exist."""
    if conn is None:
        return None
    try:
        return [dict(r) for r in conn.execute(sql, args)]
    except sqlite3.Error:
        gaps.add(source, f"{what} unavailable")
        return None


class Db:
    """One timetrack database, opened once per build and closed at the end."""

    def __init__(self, name, source, gaps):
        self.gaps, self.source = gaps, source
        self.conn = _open(name, gaps, source)

    def rows(self, sql, args=(), what=""):
        return _q(self.conn, sql, args, self.gaps, self.source, what or sql.split("FROM")[-1].split()[0])

    def close(self):
        if self.conn is not None:
            self.conn.close()


# -- work.db -----------------------------------------------------------------------------

def day_rows(work, first, last):
    """[{day, kind, target, net, span, first_unix, last_unix, ded}] for first..last (ISO dates), oldest first."""
    rows = work.rows(
        "SELECT attendance_day AS day, kind, target_minutes AS target, net_minutes AS net, span_minutes AS span,"
        " first_unix, last_unix, deduction_minutes AS ded FROM v_day_worked"
        " WHERE attendance_day >= ? AND attendance_day <= ? ORDER BY attendance_day", (first, last), "v_day_worked")
    if rows is not None:
        return rows
    rows = work.rows("SELECT day, kind, target_minutes AS target FROM day_class WHERE day >= ? AND day <= ?"
                     " ORDER BY day", (first, last), "day_class")
    if rows is None:
        return None
    work.gaps.add("timetrack", "v_day_worked missing: worked time unknown")
    return [dict(r, net=None, span=None, first_unix=None, last_unix=None, ded=None) for r in rows]


def ticket_minutes(work, first):
    """{day: (human, agent)} from ticket_minutes; None when the table is absent, {} when empty."""
    rows = work.rows("SELECT attendance_day AS day, SUM(human_minutes) AS h, SUM(agent_minutes) AS a"
                     " FROM ticket_minutes WHERE attendance_day >= ? GROUP BY attendance_day", (first,), "ticket_minutes")
    return None if rows is None else {r["day"]: (r["h"] or 0, r["a"] or 0) for r in rows}


def sessions_of(work, day):
    """[(opened, closed or None)] of the human sessions of one attendance day."""
    sql = "SELECT opened_unix, closed_unix FROM work_session WHERE attendance_day = ?"
    flt = local_tt._human(work.conn) if work.conn is not None else "1"
    rows = work.rows(f"{sql} AND {flt} ORDER BY opened_unix", (day,), "work_session")
    return [(r["opened_unix"], r["closed_unix"]) for r in rows or []]


# -- private.db --------------------------------------------------------------------------

def focus_spans(priv, t0, now):
    """[{start, end, token, zone}] ordered by start. An open span ends at its last sighting."""
    rows = priv.rows("SELECT start_unix, end_unix, seen_unix, ticket_token, ws_label FROM focus_span"
                     " WHERE start_unix >= ? ORDER BY start_unix, id", (t0,), "focus_span")
    if rows is None:
        return None
    out = []
    for r in rows:
        end = r["end_unix"] if r["end_unix"] is not None else max(r["seen_unix"] or r["start_unix"], r["start_unix"])
        out.append({"start": r["start_unix"], "end": min(end, now), "token": r["ticket_token"] or "",
                    "zone": r["ws_label"] or ""})
    return out


def breaks(priv, first):
    """{day: {label: minutes}} from away_label (grouped by key, the label of its first row)."""
    rows = priv.rows("SELECT day, key, label, end_unix - start_unix AS sec FROM away_label"
                     " WHERE end_unix IS NOT NULL AND day >= ? ORDER BY start_unix", (first,), "away_label")
    if rows is None:
        return None
    acc = {}
    for r in rows:
        if r["sec"] and r["sec"] > 0:
            d = acc.setdefault(r["day"], {})
            e = d.setdefault(r["key"], [r["label"] or r["key"], 0])
            e[1] += r["sec"]
    return {day: {lab: round(sec / 60) for lab, sec in v.values() if round(sec / 60) > 0} for day, v in acc.items()}


SALAH_SKIP = ("disabled", "away", "no_session")        # no way to pray, or no way to know: not in the total
SALAH_DONE = ("logged", "declared")
SALAH_PRAYED = ("jamaah", "alone")


def salah(priv, first, now):
    """{day: (on_time, total, nudged)}. On time is logged/declared or a prayed status (jamaah, alone):
    the enforcement column alone never reads `logged` once the prayer was handled in the lock panel.
    Rows where I was away, the check was off, or the prayer is not yet due stay out of the total."""
    rows = priv.rows("SELECT day, enforcement, status, iqamah_unix, nudged_unix FROM salah_log WHERE day >= ?",
                     (first,), "salah_log")
    if rows is None:
        return None
    out = {}
    for r in rows:
        a = out.setdefault(r["day"], [0, 0, 0])
        if r["nudged_unix"]:
            a[2] += 1
        if r["enforcement"] in SALAH_SKIP:
            continue
        if r["enforcement"] == "pending" and (r["iqamah_unix"] or 0) > now:
            continue
        a[1] += 1
        if r["enforcement"] in SALAH_DONE or r["status"] in SALAH_PRAYED:
            a[0] += 1
    return {d: tuple(v) for d, v in out.items()}


def prompts(priv, t0):
    """[ts] of prompts that were shown (an interruption)."""
    rows = priv.rows("SELECT ts_unix FROM prompt_log WHERE outcome = 'shown' AND ts_unix >= ?", (t0,), "prompt_log")
    return None if rows is None else [r["ts_unix"] for r in rows]


def logins(priv, first):
    """{day: late_minutes} for the first login of each day (a null lateness counts as 0)."""
    rows = priv.rows("SELECT day, late_minutes FROM login_log WHERE first_of_day = 1 AND day >= ? ORDER BY ts_unix",
                     (first,), "login_log")
    if rows is None:
        return None
    out = {}
    for r in rows:
        out.setdefault(r["day"], int(r["late_minutes"] or 0))
    return out


def term_days(priv, first):
    """[(day, project, seconds, delegated_seconds)] per day and project (empty project dropped)."""
    rows = priv.rows("SELECT day, project, SUM(seconds) AS sec,"
                     " SUM(CASE WHEN verdict = 'delegated' THEN seconds ELSE 0 END) AS dele"
                     " FROM term_day WHERE day >= ? AND project != '' GROUP BY day, project", (first,), "term_day")
    return None if rows is None else [(r["day"], r["project"], r["sec"] or 0, r["dele"] or 0) for r in rows]


def health(priv, first):
    """(checkpoints, doses): checkpoints [{day, slot, score, outcome, answered}], doses [{day, ts}]. Private."""
    cps = priv.rows("SELECT day, slot, score, outcome, answered_unix AS answered FROM health_checkpoint"
                    " WHERE day >= ? ORDER BY day, due_unix", (first,), "health_checkpoint")
    doses = priv.rows("SELECT day, ts_unix AS ts FROM med_dose WHERE day >= ? ORDER BY ts_unix", (first,), "med_dose")
    return cps, doses


# -- other local sources -----------------------------------------------------------------

def tasks_completed(t0, gaps):
    try:
        return tw.completed_since(t0)
    except (tw.TwError, OSError, ValueError):
        gaps.add("taskwarrior", "task export failed")
        return None


def tasks_pending(gaps):
    try:
        return tw.pending()
    except (tw.TwError, OSError, ValueError):
        gaps.add("taskwarrior", "task export failed")
        return None


def mirror_refs(gaps):
    doc = atomic.read_json(config.STATE_DIR / "mirror.json")
    if not isinstance(doc, dict) or not isinstance(doc.get("refs"), list):
        gaps.add("mirror", "mirror.json missing")
        return None
    return [r for r in doc["refs"] if isinstance(r, dict)]


def focus_now():
    doc = atomic.read_json(config.STATE_DIR / "focus.json")
    if not isinstance(doc, dict):
        return None
    out = {k: doc[k] for k in ("zone", "state") if isinstance(doc.get(k), str) and doc[k]}
    return out or None


def login_target_min():
    """Target login, minutes after midnight: work.conf LOGIN_TARGET, else timetrack's habits.toml
    [login] target, else timetrack's own default (12:00)."""
    raw = config.Work().raw.get("LOGIN_TARGET", "")
    if not raw:
        path = Path(os.environ.get("XDG_CONFIG_HOME") or config.HOME / ".config") / "timetrack" / "habits.toml"
        try:
            raw = str((tomllib.loads(path.read_text(encoding="utf-8")).get("login") or {}).get("target", ""))
        except (OSError, ValueError):
            raw = ""
    try:
        hh, mm = (raw or "12:00").split(":")
        return int(hh) * 60 + int(mm)
    except ValueError:
        return None


# -- git ---------------------------------------------------------------------------------

GIT_TTL = 300


def git_email():
    try:
        p = subprocess.run(["git", "config", "--global", "user.email"], capture_output=True, text=True,
                           timeout=3, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return None
    return p.stdout.strip() or None


def default_roots():
    out = []
    work = config.HOME / "work"
    if work.is_dir():
        out += sorted(p for p in work.iterdir() if (p / ".git").exists())
    src = config.HOME / ".local/share/chezmoi"
    if (src / ".git").exists():
        out.append(src)
    return out


def common_dir(repo):
    """The shared .git directory of a checkout: linked worktrees all resolve to their main repo."""
    g = Path(repo) / ".git"
    if g.is_file():
        try:
            line = g.read_text(encoding="utf-8").strip()
        except OSError:
            return g
        if line.startswith("gitdir:"):
            gd = Path(line[7:].strip())
            if not gd.is_absolute():
                gd = (Path(repo) / gd).resolve()
            return gd.parents[1] if gd.parent.name == "worktrees" else gd
    return g


def _log(gitdir, email, since):
    try:
        p = subprocess.run(["git", f"--git-dir={gitdir}", "log", "--branches", "--no-merges", f"--since=@{since}",
                            f"--author={email}", "--format=%H %ct"], capture_output=True, text=True,
                           timeout=5, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return []
    return p.stdout.splitlines() if p.returncode == 0 else []


def commit_times(roots, email, since):
    """Sorted commit times (unix) of `email` since `since`, one per distinct hash. Linked worktrees of one
    repository are read once; the repositories are read in parallel; the answer is kept for GIT_TTL."""
    from concurrent.futures import ThreadPoolExecutor
    cache = config.STATE_DIR / "metrics-cache" / "git.json"
    key = f"{email}:{since // 86400}:{len(roots)}"
    hit = atomic.read_json(cache) or {}
    if hit.get("key") == key and time.time() - hit.get("at", 0) < GIT_TTL:
        return hit["times"]
    dirs = sorted({common_dir(r) for r in roots})
    seen = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for lines in ex.map(lambda d: _log(d, email, since), dirs):
            for line in lines:
                h, _, ct = line.partition(" ")
                if h and ct.isdigit():
                    seen[h] = int(ct)
    times = sorted(seen.values())
    try:
        atomic.write_json(cache, {"key": key, "at": int(time.time()), "times": times})
    except OSError:
        pass
    return times


def iso(ts):
    return datetime.fromtimestamp(ts).date().isoformat()
