#!/usr/bin/env bash
# An answer that covers PART of an AW gap must not swallow the rest of it.
#
# Found live: a declared washroom break ended at 23:00:04, where ActivityWatch split one
# absence in two. The refresh skipped the whole 22:45-23:17 gap because an answer touched
# it, so the 17 minutes after 23:00 stayed inside the figure (doctor: aw:lower-bound FAIL).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - <<'PY'
from datetime import datetime
from timetrack import dbs, migrate
from timetrack.backfill import aw

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

migrate.migrate()
conn = dbs.open_work()
day = "2026-11-04"
T = lambda h, m: datetime(2026, 11, 4, h, m)
conn.execute("INSERT INTO day_class(day,kind,pay_affecting,target_minutes) VALUES(?,?,?,?)",
             (day, "working", 1, 480))
conn.commit()
runs = [(T(21, 30), T(22, 45)), (T(23, 17), T(23, 57))]          # 75 + 40 present
aw.not_afk = lambda *a, **k: []
aw.workdays = lambda _ev, _lo=(): [{"day": day, "open": runs[0][0], "close": runs[-1][1],
                                    "present_seconds": 115 * 60, "runs": runs}]
net = lambda: conn.execute("SELECT net_minutes FROM v_day_worked WHERE attendance_day=?",
                           (day,)).fetchone()[0]
aw.write(conn, refresh_day=day)
check("first write deducts the whole gap", round(net()), 115)

# the user declares 22:45-23:00 a washroom break; the rest of the absence is unanswered
d = conn.execute("SELECT id FROM deduction").fetchone()[0]
conn.execute("UPDATE deduction SET end_unix=?, minutes=15, category='washroom', confirmed=1,"
             " provenance='away:declared' WHERE id=?", (int(T(23, 0).timestamp()), d))
conn.commit()
aw.write(conn, refresh_day=day)
check("REFRESH STILL DEDUCTS THE UNANSWERED REMAINDER", round(net()), 115)
rows = conn.execute("SELECT category, confirmed, round(minutes) m FROM deduction"
                    " ORDER BY start_unix").fetchall()
check("answer kept, remainder asked", [tuple(r) for r in rows],
      [("washroom", 1, 15), ("misc", 0, 17)])

# 3. the remainder was not a break: the user was at the desk. Worked time, kept on refresh.
from timetrack import interactive
rid = conn.execute("SELECT id FROM deduction WHERE confirmed=0").fetchone()[0]
interactive.answer_gap(conn, rid, interactive.WORKED); conn.commit()
check("'I was working' returns the minutes", round(net()), 132)
aw.write(conn, refresh_day=day)
check("refresh keeps 'I was working'", round(net()), 132)
check("recorded as worked, not meeting", conn.execute(
    "SELECT provenance FROM deduction WHERE id=(SELECT MAX(id) FROM deduction"
    " WHERE start_unix=?)", (int(T(23, 0).timestamp()),)).fetchone()[0], interactive.WORKED)
check("picker breaks offered", {c[1] for c in interactive.GAP_CHOICES} >= {
    "walk / short break", "lunch / long break", "not a break: I was working"}, True)

# 4. a day already answered as paid leave is not asked about again
conn.execute("INSERT INTO day_class(day,kind,leave_type,pay_affecting,target_minutes)"
             " VALUES('2026-11-02','leave_paid','sick',0,480)")
conn.execute("INSERT INTO day_class(day,kind,pay_affecting,target_minutes)"
             " VALUES('2026-11-03','working',1,480)")
from datetime import date
check("answered leave not re-asked", [d["attendance_day"] for d in
      interactive.pending_days(conn, "2026-11", today=date(2026, 11, 5))], ["2026-11-03"])

if fails:
    print("aw-gap FAILED:"); [print("  " + f) for f in fails]; raise SystemExit(1)
print("aw-gap ok (4 scenarios)")
PY
