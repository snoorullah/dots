#!/usr/bin/env bash
# D10/D15/D9 (login.py): leave backfill, the 12:00 habit, the weekly target. What must
# never happen: a reason we made up for a panel nobody answered, a nudge-phase login that
# blocks, a weekend or a night-session tail judged as late, a panel past the D21 budget, or
# the away watcher stalled behind a panel (on_login only spawns).
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - "$tmp" <<'PY'
import subprocess, sys, time
from datetime import date, datetime
from pathlib import Path

from timetrack import config, dbs, derive, login, migrate

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

tmp = Path(sys.argv[1])
config.PANIC = tmp / "config" / "timetrack" / "PANIC"
config.PANIC.parent.mkdir(parents=True)
migrate.migrate()

toasts, panels, spawned = [], [], []
answer = {"rc": 0, "out": ""}
login._toast = lambda summary, body="": toasts.append((summary, body))
login._spawn = lambda argv: spawned.append(argv)
login._timetrack = lambda: "/x/timetrack"
def fake_run(cmd):
    panels.append(cmd)
    if cmd[1].startswith("login-"):
        return subprocess.CompletedProcess(cmd, answer["rc"], stdout=answer["out"], stderr="")
    return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
login._run = fake_run
def habits(**kw): config.habits = lambda section: dict(kw)

at = lambda d, h, m=0: int(datetime(2026, *d, h, m).timestamp())
def reset():
    toasts.clear(); panels.clear()
    with dbs.open_private() as c:
        c.execute("DELETE FROM prompt_log"); c.commit()
def row(ts):
    with dbs.open_private() as c:
        return dict(c.execute("SELECT * FROM login_log WHERE ts_unix=?", (ts,)).fetchone())
def kinds(): return [p[1].split("-")[0] for p in panels]
def fill_budget():
    with dbs.open_private() as c:
        now = int(time.time())
        for i in range(2):
            c.execute("INSERT INTO prompt_log VALUES(?,?,'shown')", (now - 10 - i, f"x{i}"))
        c.commit()

# 1. on_login only spawns
t = at((10, 28), 12, 47)
login.on_login(t)
check("spawns once", spawned, [["/x/timetrack", "login", "run", "--at", str(t)]])

# 2. first_of_day, and a repeated run of the same login is a no-op
habits(enabled=False)
reset()
a, b = at((10, 28), 9, 0), at((10, 28), 9, 30)
login.run_at(a); login.run_at(b)
check("first of day", (row(a)["first_of_day"], row(b)["first_of_day"]), (1, 0))
check("same login twice", login.run_at(a)["prompt"], "duplicate")

# 3. D10: pending days -> panel / toast when over budget / toast only under PANIC
reset(); habits(enabled=False)
r = login.run_at(at((10, 29), 9, 0))
check("pending found", r["pending"] > 0, True)
check("panel when budget allows", (kinds(), panels[0][3:5] if panels else None), (["leave"], ["--", "/x/timetrack"]))
check("panel runs login leave", panels[0][-2:], ["login", "leave"])
check("no toast beside the panel", toasts, [])
reset(); fill_budget()
login.run_at(at((10, 30), 9, 0))
check("over budget: no panel", panels, [])
check("over budget: toast", [t[0].endswith("unexplained · timetrack backfill") for t in toasts], [True])
reset(); config.PANIC.touch()
login.run_at(at((10, 31), 9, 0))
with dbs.open_private() as c:
    n = c.execute("SELECT COUNT(*) FROM prompt_log").fetchone()[0]
check("PANIC: toast only, budget untouched", (panels, len(toasts), n), ([], 1, 0))
config.PANIC.unlink()

# 4. D15 nudge: never opens the why panel
reset(); habits(start="2026-10-25")
t = at((11, 2), 12, 47)
r = login.run_at(t)
check("nudge phase", (row(t)["phase"], row(t)["late_minutes"], row(t)["prompt"], row(t)["reason"]),
      ("nudge", 47, "toast", None))
check("nudge: no why panel", [k for k in kinds() if k == "login"], [])
check("login toast", toasts[0][0].startswith("Logged in 12:47 · 47 min after 12:00 · on time "), True)
check("login toast carries the week", toasts[0][1].startswith("Week: "), True)

# 5. D15 enforce: late beyond grace -> panel, reason recorded
reset(); habits(start="2026-10-01"); answer.update(rc=0, out="slept_late\n")
t = at((11, 3), 12, 47)
login.run_at(t)
r5 = row(t)
check("enforce: panel", [k for k in kinds() if k == "login"], ["login"])
check("panel title", [p[2] for p in panels if p[1].startswith("login-")], ["Late login (12:47) — why?"])
check("panel reason", (r5["phase"], r5["prompt"], r5["reason"]), ("enforce", "panel", "slept_late"))

# 6. exit 2 or junk -> timeout, never a made-up reason
for name, rc, out, day in (("exit 2", 2, "", 4), ("junk", 0, "banana\n", 5)):
    reset(); answer.update(rc=rc, out=out)
    t = at((11, day), 12, 47)
    login.run_at(t)
    check(f"{name}: timeout, no reason", (row(t)["prompt"], row(t)["reason"]), ("timeout", None))

# 7. enforce but over budget -> deferred
reset(); fill_budget(); answer.update(rc=0, out="unwell\n")
t = at((11, 6), 12, 47)
login.run_at(t)
check("over budget: deferred", ([k for k in kinds() if k == "login"], row(t)["prompt"]), ([], "deferred"))

# 8. within grace -> no panel; late 10
reset(); answer.update(rc=0, out="other\n")
t = at((11, 9), 12, 10)
login.run_at(t)
check("within grace", ([k for k in kinds() if k == "login"], row(t)["late_minutes"], row(t)["prompt"]),
      ([], 10, "toast"))
t = at((11, 10), 11, 30)
login.run_at(t)
check("early is zero late", (row(t)["late_minutes"], "on time" in toasts[-1][0]), (0, True))

# 9. weekend and a 03:00 login are not judged; noon after a 03:00 login still is
reset(); habits(start="2026-10-01")
t = at((10, 31), 12, 47)             # Saturday
login.run_at(t)
check("weekend not judged", (row(t)["phase"], row(t)["late_minutes"], row(t)["prompt"], panels and kinds()),
      (None, None, "none", ["leave"] if panels else panels))
reset()
n3, n12 = at((11, 11), 3, 0), at((11, 11), 12, 47)
login.run_at(n3)
check("03:00 not judged", (row(n3)["phase"], row(n3)["prompt"], [t for t in toasts if "Logged in" in t[0]]),
      (None, "none", []))
answer.update(rc=0, out="worked_late\n")
login.run_at(n12)
check("noon after 03:00 judged", (row(n12)["first_of_day"], row(n12)["prompt"], row(n12)["reason"]),
      (0, "panel", "worked_late"))
reset()
t2 = at((11, 11), 15, 0)
login.run_at(t2)
check("second login of the day not judged", (row(t2)["phase"], row(t2)["prompt"]), (None, "none"))

# 10. habit chart
with dbs.open_private(readonly=True) as c:
    lines = login.habit_lines(c, date(2026, 11, 11), 28)
chart = {l.split()[0]: l for l in lines}
check("chart late line", chart["2026-11-03"], "2026-11-03  Tue  12:47  ▇▇▇")
check("chart grace line", chart["2026-11-09"], "2026-11-09  Mon  12:10  ✓")
check("chart no login", chart["2026-10-27"], "2026-10-27  Tue  -")
check("chart weekend absent", "2026-11-07" in chart, False)
check("chart footer", lines[-1].startswith("on time ") and " of " in lines[-1], True)

# 11. D9 week on a fixture week: Mon 8h + Tue 7h + Wed 7h10 = 22h10 of 40h
sec = 0
def session(day, h0, mins):
    s = int(datetime.fromisoformat(f"{day}T{h0:02d}:00:00").timestamp()); e = s + mins * 60
    with dbs.open_work() as c:
        sid = c.execute("INSERT INTO work_session(opened_ts,opened_unix,closed_ts,closed_unix,"
                        "attendance_day,open_trigger,close_trigger,provenance) VALUES(?,?,?,?,?,?,?,?)",
                        (day, s, day, e, day, "manual", "manual", "manual")).lastrowid
        for kind, ts in (("session_open", s), ("run_start", s), ("run_stop", e), ("session_close", e)):
            c.execute("INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,actor,"
                      "provenance,ruleset,confidence) VALUES(?,?,?,?,?,?,?,?,?)",
                      (day, ts, day, sid, kind, "human", "manual", config.RULESET, 1.0))
        c.commit()
session("2026-10-26", 9, 480); session("2026-10-27", 9, 420); session("2026-10-28", 9, 430)
with dbs.open_work() as c:
    w = login.week_summary(c, date(2026, 10, 28), today=date(2026, 10, 28))
    sun = login.week_summary(c, date(2026, 11, 1), today=date(2026, 10, 28))
check("week target", w["target_minutes"], 2400)
check("week worked", w["worked_minutes"], 1330)
check("week left", (w["left_minutes"], w["remaining_working_days"], w["needed_per_day_minutes"]), (1070, 3, 357))
check("week line", login.week_line(w), "Week: 22h10 of 40h · 17h50 left over 3 days (5h57/day)")
check("week is Mon-Sun", (w["monday"], w["sunday"], sun["monday"]), ("2026-10-26", "2026-11-01", "2026-10-26"))
check("weekend target 0", [d["target_minutes"] for d in w["days"][5:]], [0, 0])

# 12. paid leave is credited at its target, not reported as a shortfall
with dbs.open_work() as c:
    login._ensure_seeded(c, date(2026, 11, 2))
    c.execute("UPDATE day_class SET kind='leave_paid', leave_type='sick' WHERE day='2026-11-02'")
    c.execute("UPDATE day_class SET kind='leave_paid', leave_type='casual' WHERE day='2026-11-06'")
    c.commit()
session("2026-11-03", 9, 420)
with dbs.open_work() as c:
    w = login.week_summary(c, date(2026, 11, 4), today=date(2026, 11, 4))
    m = derive.month_summary(c, "2026-11", today=date(2026, 11, 4))
check("leave week worked", w["worked_minutes"], 480 + 420 + 480)
check("leave week left", (w["left_minutes"], w["remaining_working_days"]), (1020, 2))
check("leave month shortfall", m["shortfall_to_date_minutes"], 60)

if fails:
    print("login FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("login ok (12 scenarios)")
PY
