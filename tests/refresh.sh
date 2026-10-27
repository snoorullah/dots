#!/usr/bin/env bash
# The hourly AW refresh must not undo what the user said about the day.
#
# Found live: the capture job re-derives TODAY every hour by dropping AW's session and
# writing it again. It deleted deductions by session_id, so a gap the user classified as
# dinner was back to "unconfirmed misc" an hour later -- and a gap declared a MEETING,
# which is worked time, was deducted again. On a day with an offline meeting that is the
# meeting silently subtracted from the figure handed to an employer.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - <<'PY'
from datetime import datetime, timedelta
from timetrack import dbs, interactive, migrate
from timetrack.backfill import aw

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

migrate.migrate()
conn = dbs.open_work()
day = "2026-10-22"
T = lambda h, m: datetime(2026, 10, 22, h, m)
conn.execute("INSERT INTO day_class(day,kind,pay_affecting,target_minutes) VALUES(?,?,?,?)",
             (day, "working", 1, 480))
conn.commit()

def presence(until_h, until_m):
    # 13:00-15:00 | 30m dinner | 15:30-17:00 | 60m meeting | 18:00-<until>
    runs = [(T(13, 0), T(15, 0)), (T(15, 30), T(17, 0)), (T(18, 0), T(until_h, until_m))]
    secs = sum((b - a).total_seconds() for a, b in runs)
    return [{"day": day, "open": runs[0][0], "close": runs[-1][1],
             "present_seconds": secs, "runs": runs}]

def net():
    return conn.execute("SELECT net_minutes FROM v_day_worked WHERE attendance_day=?",
                        (day,)).fetchone()[0]

aw.not_afk = lambda *a, **k: []
aw.workdays = lambda _ev, _lo=(): presence(19, 0)
aw.write(conn, refresh_day=day)
check("first write: 6h span, 90m of gaps", net(), 360 - 90)

# the user answers both gaps: dinner (deducted) and a meeting (worked time)
rows = conn.execute("SELECT id, start_unix FROM deduction ORDER BY start_unix").fetchall()
conn.execute("UPDATE deduction SET category='dinner', confirmed=1, provenance='manual'"
             " WHERE id=?", (rows[0]["id"],))
conn.execute("UPDATE deduction SET minutes=0, confirmed=1, provenance=? WHERE id=?",
             (interactive.MEETING, rows[1]["id"]))
conn.commit()
check("after answering: the meeting returns 60 minutes", net(), 360 - 30)

# an hour later the day has grown, and the capture job refreshes it
aw.workdays = lambda _ev, _lo=(): presence(20, 0)
aw.write(conn, refresh_day=day)
check("REFRESH KEEPS THE MEETING AS WORKED TIME", net(), 420 - 30)
cats = conn.execute("SELECT category, minutes, confirmed, provenance FROM deduction"
                    " ORDER BY start_unix").fetchall()
check("two deductions, not four", len(cats), 2)
check("dinner survived", (cats[0]["category"], cats[0]["confirmed"]), ("dinner", 1))
check("meeting survived at zero cost", (cats[1]["minutes"], cats[1]["provenance"]),
      (0, interactive.MEETING))
check("nothing re-asked", conn.execute(
    "SELECT COUNT(*) FROM deduction WHERE confirmed=0").fetchone()[0], 0)

# A HAND interval on an AW day. Three ways it went wrong before: hung on AW's session it
# was erased by the next refresh; its session made AW skip the day entirely; and where it
# overlapped measured presence both were summed.
from timetrack import hotkey
before = net()
hotkey.start("", now=int(T(20, 30).timestamp()))
r = hotkey.stop(conn, now=int(T(21, 30).timestamp()))      # 20:30-21:30, half beyond AW
check("hand interval recorded", r["action"], "recorded")
check("hand interval in its own session", conn.execute(
    "SELECT provenance FROM work_session WHERE id=?", (r["session_id"],)).fetchone()[0], "hotkey")
aw.workdays = lambda _ev, _lo=(): presence(21, 0)                 # AW presence grows to 21:00
aw.write(conn, refresh_day=day)
check("refresh kept the hand interval", conn.execute(
    "SELECT COUNT(*) FROM clock_event WHERE provenance='hotkey' AND kind IN ('run_start','run_stop')").fetchone()[0], 2)
check("refresh did not skip the AW day", conn.execute(
    "SELECT COUNT(*) FROM work_session WHERE provenance='backfill:aw'").fetchone()[0], 1)
# AW now covers 13:00-21:00 (480m span, 30m dinner, meeting free) = 450; the hand interval
# adds only what AW did NOT see, 21:00-21:30 -- the 20:30-21:00 overlap counts once
check("overlap counted ONCE", net(), 450 + 30)
aw.write(conn, refresh_day=day)                            # and again: stable, no drift
check("second refresh is stable", net(), 450 + 30)

# A hand interval that COVERS an AFK gap -- the real 2026-10-23 shape. The gap stays
# deducted (the hand interval carries the minutes) but is not asked about again, and the
# doctor's lower bound compares AW's share only, since AW cannot see hand time.
d2 = "2026-10-21"
conn.execute("INSERT INTO day_class(day,kind,pay_affecting,target_minutes) VALUES(?,?,?,?)",
             (d2, "working", 1, 480))
conn.commit()
U = lambda h, m, s=0: datetime(2026, 10, 21, h, m, s)
hotkey.start("", now=int(U(10, 0, 4).timestamp()))                # 4s after AW saw idle
hotkey.stop(conn, now=int(U(10, 14).timestamp()))
runs2 = [(U(9, 0), U(10, 0)), (U(10, 14), U(11, 0))]
aw.workdays = lambda _ev, _lo=(): [{"day": d2, "open": runs2[0][0], "close": runs2[-1][1],
    "present_seconds": sum((b - a).total_seconds() for a, b in runs2), "runs": runs2}]
aw.write(conn, refresh_day=d2)
g = conn.execute("SELECT confirmed, provenance FROM deduction WHERE attendance_day=?"
                 " AND provenance != 'hotkey:overlap'", (d2,)).fetchone()
check("covered gap is not re-asked", (g["confirmed"], g["provenance"]), (1, "hotkey:covered"))
n2 = conn.execute("SELECT net_minutes FROM v_day_worked WHERE attendance_day=?", (d2,)).fetchone()[0]
check("covered gap counted once: 106 AW + 14 hand", round(n2), 120)
from timetrack import doctor
real_present = 106
hand = conn.execute("SELECT SUM(seconds)/60.0 FROM v_run_interval WHERE attendance_day=?"
                    " AND provenance='hotkey'", (d2,)).fetchone()[0]
check("AW share within measured presence", round(n2 - hand) <= real_present + 1, True)

# the guard still holds: a refresh never touches a day it did not write itself
conn.execute("UPDATE work_session SET provenance='backfill:sheet' WHERE attendance_day=?", (day,))
conn.commit()
aw.workdays = lambda _ev, _lo=(): presence(21, 0)
aw.write(conn, refresh_day=day)
check("sheet day untouched", net(), 450 + 30)

if fails:
    print("refresh FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("refresh ok (6 scenarios, 17 assertions)")
PY
