"""D10, D15, D9: what happens at the start of a session.

A login is the one moment the user is certainly at the machine and has not yet started,
so it is where three things get asked or said:

  D10  working days with no record at all are asked about, in a blocking panel, until
       they are explained. Nothing is written by asking: the days stay pending, so a
       dismissed or deferred panel simply asks again at the next login.
  D15  the 12:00 habit. Two weeks of toasts plus an adherence chart, then a blocking
       "why" at 12:15. The reason is only ever what the user picked: a panel that times
       out records `timeout`, never a reason we made up.
  D9   the weekly 40h target, reported per day and as "what is left" in the login toast.

`away.on_login` calls `on_login` synchronously inside its watcher loop, so it only
spawns `timetrack login run` detached and returns; the panels block for minutes and must
not stall the watcher. Every subprocess, clock read and toast goes through a module-level
seam (`_spawn`, `_run`, `_toast`, `_fzf`) so tests replace them and nothing reaches the
real desktop.
"""
import shutil
import subprocess
from datetime import date, datetime, timedelta

from . import budget, calendar_, config, dbs, derive, interactive, notify

REASONS = [
    ("slept_late", "Slept late"),
    ("worked_late", "Worked late the night before"),
    ("appointment", "Appointment"),
    ("unwell", "Unwell"),
    ("other", "Other"),
]
KEYS = {k for k, _ in REASONS}

NUDGE_DAYS = 14
FIRST_HOUR = 6          # earlier than this is the tail of a night session; not judged
BAR_MIN = 15
PANEL_TIMEOUT = 700


# --- seams ---------------------------------------------------------------------------

def _timetrack():
    return shutil.which("timetrack") or str(config.HOME / ".nix-profile/bin/timetrack")


def _spawn(argv):
    subprocess.Popen(argv, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _run(argv):
    return subprocess.run(argv, capture_output=True, text=True, timeout=PANEL_TIMEOUT)


def _toast(summary, body=""):
    notify.toast("timetrack", summary, body)


def _fzf(items, header):
    """Otter-styled picker; the chosen key, or '' on Esc. Styling lives in one script."""
    script = str(config.HOME / ".config/otter-launcher/scripts/_otter-fzf.sh")
    prog = ('source "$1" 2>/dev/null || true; '
            "fzf --with-nth=2 --delimiter='\\t' --header=\"$2\" --no-multi | cut -f1")
    res = subprocess.run(["bash", "-c", prog, "_", script, header],
                         input="\n".join(f"{k}\t{label}" for k, label in items),
                         stdout=subprocess.PIPE, text=True)
    return (res.stdout or "").strip()


def on_login(now):
    """Called by the away watcher. Spawn and return at once."""
    _spawn([_timetrack(), "login", "run", "--at", str(int(now))])


# --- helpers -------------------------------------------------------------------------

def _hm(minutes):
    """22h10, or 40h when the minutes are zero."""
    minutes = int(round(minutes))
    sign = "-" if minutes < 0 else ""
    h, m = divmod(abs(minutes), 60)
    return f"{sign}{h}h{m:02d}" if m else f"{sign}{h}h"


def _clock(dt):
    return dt.strftime("%H:%M")


def _month(d):
    return d.strftime("%Y-%m")


def _prev_month(d):
    return _month(d.replace(day=1) - timedelta(days=1))


def _ensure_seeded(wconn, *days):
    """Seed a month's day_class only when it has no rows; never touches answered days."""
    for d in days:
        n = wconn.execute("SELECT COUNT(*) FROM day_class WHERE day LIKE ?",
                          (_month(d) + "-%",)).fetchone()[0]
        if not n:
            calendar_.seed_month(wconn, d.year, d.month)


def _habit(day=None):
    """(target 'HH:MM' as minutes since midnight, grace minutes, settings)."""
    h = config.habits("login")
    hh, mm = str(h.get("target", "12:00")).split(":")
    return int(hh) * 60 + int(mm), int(h.get("grace_min", 15)), h


def _target_label(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def _minutes_of(dt):
    return dt.hour * 60 + dt.minute


def _judged(dt):
    """Only a working day's first login from 06:00 on is held against the habit."""
    return dt.hour >= FIRST_HOUR and calendar_.classify(dt.date())[0] == "working"


def _first_judged_ts(pconn, day, before=None):
    """Earliest login of `day` from 06:00 on. A 03:00 login must not shield a noon one."""
    lo = int(datetime.fromisoformat(day + f"T{FIRST_HOUR:02d}:00:00").timestamp())
    q, args = "SELECT MIN(ts_unix) FROM login_log WHERE day = ? AND ts_unix >= ?", [day, lo]
    if before is not None:
        q += " AND ts_unix < ?"
        args.append(before)
    return pconn.execute(q, args).fetchone()[0]


def _phase(pconn, today):
    h = config.habits("login")
    if not h.get("enabled", True):
        return "off"
    start = h.get("start")
    if start is None:
        pconn.execute("INSERT OR IGNORE INTO schema_meta(k, v) VALUES('login_habit_start', ?)",
                      (today.isoformat(),))
        pconn.commit()
        start = pconn.execute("SELECT v FROM schema_meta WHERE k = 'login_habit_start'"
                              ).fetchone()[0]
    start = date.fromisoformat(str(start)[:10])
    return "nudge" if (today - start).days < NUDGE_DAYS else "enforce"


def _working_days_back(today, count):
    """The last `count` working days up to and including today, oldest first."""
    out, d = [], today
    while len(out) < count and (today - d).days < count * 4 + 14:
        if calendar_.classify(d)[0] == "working":
            out.append(d)
        d -= timedelta(days=1)
    return out[::-1]


def _day_firsts(pconn, days):
    return {d: _first_judged_ts(pconn, d.isoformat()) for d in days}


def _on_time(pconn, target, grace, days):
    """(on time, logged) over `days`: a day with no login says nothing about the habit."""
    ok = logged = 0
    for d, ts in _day_firsts(pconn, days).items():
        if ts is None:
            continue
        logged += 1
        if _minutes_of(datetime.fromtimestamp(ts)) - target <= grace:
            ok += 1
    return ok, logged


# --- D9 ------------------------------------------------------------------------------

def week_summary(conn, day, today=None):
    """The Mon-Sun week containing `day`: target, worked, what is left, per day.

    Worked uses derive.basis, the same footing month_summary uses (net when breaks are
    known, else span), so the week and the month can never disagree about a day.
    """
    today = today or date.today()
    monday = day - timedelta(days=day.weekday())
    days = [monday + timedelta(days=i) for i in range(7)]
    _ensure_seeded(conn, *{monday, days[-1]})
    by_day = {r["attendance_day"]: r for r in conn.execute(
        "SELECT * FROM v_day_worked WHERE attendance_day BETWEEN ? AND ?",
        (days[0].isoformat(), days[-1].isoformat()))}
    calib = config.calibration()
    rows, target, worked = [], 0, 0
    for d in days:
        r = by_day.get(d.isoformat())
        t = int(r["target_minutes"]) if r else 0
        w = derive.basis(r, calib)[0] if r else 0
        target, worked = target + t, worked + w
        rows.append({"day": d.isoformat(), "weekday": d.strftime("%a"), "kind": r["kind"] if r else "-",
                     "target_minutes": t, "worked_minutes": w})
    remaining = [x for x in rows if x["target_minutes"] > 0 and x["day"] >= today.isoformat()
                 and x["kind"] != "leave_paid"]   # credited already; nothing left to work
    left = target - worked
    return {
        "monday": monday.isoformat(), "sunday": days[-1].isoformat(), "days": rows,
        "target_minutes": target, "worked_minutes": worked, "left_minutes": left,
        "remaining_working_days": len(remaining),
        "needed_per_day_minutes": round(left / len(remaining)) if remaining and left > 0 else None,
    }


def week_line(w):
    if not w["target_minutes"]:
        return "Week: no working days"
    head = f"Week: {_hm(w['worked_minutes'])} of {_hm(w['target_minutes'])}"
    if w["left_minutes"] <= 0:
        return f"{head} · target met"
    n = w["remaining_working_days"]
    if not n:
        return f"{head} · {_hm(w['left_minutes'])} short"
    return (f"{head} · {_hm(w['left_minutes'])} left over {n} day{'s' if n != 1 else ''}"
            f" ({_hm(w['needed_per_day_minutes'])}/day)")


# --- login run -----------------------------------------------------------------------

def run_at(ts):
    """Everything that happens for one login. Returns a dict, for tests and the log."""
    ts = int(ts)
    dt = datetime.fromtimestamp(ts)
    today = dt.date()
    day = today.isoformat()
    out = {"ts": ts, "day": day, "pending": 0, "leave": None, "prompt": "none", "phase": None}

    with dbs.open_private() as pconn:
        first_of_day = pconn.execute("SELECT COUNT(*) FROM login_log WHERE day = ? AND ts_unix < ?",
                                     (day, ts)).fetchone()[0] == 0
        cur = pconn.execute("INSERT OR IGNORE INTO login_log(ts_unix, day, first_of_day)"
                            " VALUES(?,?,?)", (ts, day, int(first_of_day)))
        pconn.commit()
        if not cur.rowcount:
            out["prompt"] = "duplicate"
            return out
        out["first_of_day"] = first_of_day

        _leave(ts, today, out)
        _habit_check(pconn, ts, dt, out)
    return out


def _leave(ts, today, out):
    """D10. The days stay pending whatever happens, so the next login asks again."""
    with dbs.open_work() as wconn:
        # this month only: seeding last month would turn every day before tracking began
        # into an "unexplained" one. A month already classified is asked about as it stands.
        _ensure_seeded(wconn, today)
        n = sum(len(interactive.pending_days(wconn, m, today))
                for m in (_prev_month(today), _month(today)))
    out["pending"] = n
    if not n:
        return
    if config.panic():
        out["leave"] = "toast"
    elif budget.take("leave_backfill"):
        out["leave"] = "panel"
        bin_ = config.HOME / ".local/bin"
        try:
            _run([str(bin_ / "timetrack-panel"), f"leave-{ts}",
                  f"{n} working day(s) with no record", "--", _timetrack(), "login", "leave"])
        except (OSError, subprocess.SubprocessError):
            pass
        return
    else:
        out["leave"] = "deferred"
    _toast(f"{n} working day(s) unexplained · timetrack backfill")


def _habit_check(pconn, ts, dt, out):
    day = dt.date().isoformat()
    if not _judged(dt) or _first_judged_ts(pconn, day, before=ts) is not None:
        # weekend, holiday, night-session tail, or not the day's first real login
        pconn.execute("UPDATE login_log SET prompt='none' WHERE ts_unix=?", (ts,))
        pconn.commit()
        return
    target, grace, _ = _habit()
    late = max(0, _minutes_of(dt) - target)
    phase = _phase(pconn, dt.date())
    out.update(phase=phase, late=late)
    if phase == "off":
        pconn.execute("UPDATE login_log SET phase='off', late_minutes=?, prompt='none'"
                      " WHERE ts_unix=?", (late, ts))
        pconn.commit()
        return

    ok, logged = _on_time(pconn, target, grace, _working_days_back(dt.date(), 10))
    when = (f"{late} min after {_target_label(target)}" if late else "on time")
    with dbs.open_work() as wconn:
        wk = week_line(week_summary(wconn, dt.date(), dt.date()))
    _toast(f"Logged in {_clock(dt)} · {when} · on time {ok} of last {logged} working days", wk)

    prompt, reason = "toast", None
    if phase == "enforce" and late > grace and not config.panic():
        if budget.take("login_why"):
            bin_ = config.HOME / ".local/bin"
            prompt = "timeout"
            try:
                res = _run([str(bin_ / "timetrack-panel"), f"login-{ts}",
                            f"Late login ({_clock(dt)}) — why?", "--", _timetrack(),
                            "login", "why-pick"])
                got = (res.stdout or "").strip().splitlines()[-1:] if res.returncode == 0 else []
                if got and got[0] in KEYS:
                    prompt, reason = "panel", got[0]
            except (OSError, subprocess.SubprocessError):
                pass
        else:
            prompt = "deferred"
    pconn.execute("UPDATE login_log SET phase=?, late_minutes=?, prompt=?, reason=?"
                  " WHERE ts_unix=?", (phase, late, prompt, reason, ts))
    pconn.commit()
    out["prompt"], out["reason"] = prompt, reason


# --- subcommands ---------------------------------------------------------------------

def cmd_run(a):
    run_at(a.at)
    return 0


def cmd_leave(a):
    today = date.today()
    with dbs.open_work() as conn:
        for m in (_prev_month(today), _month(today)):
            print(f"=== {m} ===")
            interactive.resolve_days(conn, m)
    return 0


def cmd_why_pick(a):
    key = _fzf(REASONS, "late login — why?")
    if key not in KEYS:
        return 1
    print(key)
    return 0


def habit_lines(pconn, today, days=28):
    target, grace, _ = _habit()
    wd = [d for d in _working_days_back(today, days) if (today - d).days < days]
    lines, ok, logged = [], 0, 0
    for d, ts in _day_firsts(pconn, wd).items():
        if ts is None:
            lines.append(f"{d.isoformat()}  {d.strftime('%a')}  -")
            continue
        late = max(0, _minutes_of(datetime.fromtimestamp(ts)) - target)
        within = late <= grace
        logged += 1
        ok += within
        mark = "▇" * (late // BAR_MIN) + (" ✓" if within else "")
        lines.append(f"{d.isoformat()}  {d.strftime('%a')}  "
                     f"{_clock(datetime.fromtimestamp(ts))}  {mark.strip()}".rstrip())
    lines.append(f"on time {ok} of {logged}")
    return lines


def cmd_habit(a):
    with dbs.open_private(readonly=True) as pconn:
        print("\n".join(habit_lines(pconn, date.today(), a.days)))
    return 0


def cmd_week(a):
    day = date.fromisoformat(a.day) if a.day else date.today()
    with dbs.open_work() as conn:
        w = week_summary(conn, day)
    print(f"week {w['monday']} .. {w['sunday']}")
    for r in w["days"]:
        print(f"  {r['day']}  {r['weekday']}  {r['kind']:<14}"
              f"{_hm(r['worked_minutes']):>7} / {_hm(r['target_minutes']):<5}")
    print(week_line(w))
    return 0


def add_parser(sub):
    s = sub.add_parser("login", help="D10/D15: what happens at login")
    ls = s.add_subparsers(dest="login_cmd", required=True)
    p = ls.add_parser("run", help="handle one login (spawned by the away watcher)")
    p.add_argument("--at", type=int, required=True, help="login time, unix seconds")
    p.set_defaults(fn=cmd_run)
    ls.add_parser("leave", help="answer unexplained working days (runs in the panel)"
                  ).set_defaults(fn=cmd_leave)
    ls.add_parser("why-pick", help="pick why the login was late; key on stdout"
                  ).set_defaults(fn=cmd_why_pick)
    p = ls.add_parser("habit", help="adherence chart: first login per working day")
    p.add_argument("--days", type=int, default=28)
    p.set_defaults(fn=cmd_habit)

    p = sub.add_parser("week", help="D9: the week's target, worked and what is left")
    p.add_argument("--day", help="any date in the week (YYYY-MM-DD); default today")
    p.set_defaults(fn=cmd_week)
