#!/usr/bin/env bash
# The live clock as a SHADOW (migrate.WORK_V3): recorded, not counted, until promoted.
#
# Switching clockd on writes to the payroll database. Before it may count, two things had to
# be true and were not: agent-only time must stay out of the submitted headline (D3), and
# ActivityWatch -- which measures the same minutes -- must neither double-count them nor be
# erased by them. These assert that switching on cannot move the headline at all.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - <<'PY'
from datetime import datetime
from timetrack import clockd, config, dbs, derive, hotkey, migrate
from timetrack.backfill import aw

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

migrate.migrate()
conn = dbs.open_work()
check("schema v5", conn.execute("PRAGMA user_version").fetchone()[0], 5)
check("ships as a shadow", migrate.live_counts(conn), False)

day = "2026-10-24"
T = lambda h, m=0: int(datetime(2026, 10, 24, h, m).timestamp())
iso = lambda t: datetime.fromtimestamp(t).isoformat(timespec="seconds")
conn.execute("INSERT INTO day_class(day,kind,pay_affecting,target_minutes) VALUES(?,?,?,?)",
             (day, "working", 1, 480))
# AW measured 13:00-17:00 with no gaps
runs = [(datetime(2026, 10, 24, 13), datetime(2026, 10, 24, 17))]
aw.not_afk = lambda *a, **k: []
aw.workdays = lambda _e, _lo=(): [{"day": day, "open": runs[0][0], "close": runs[0][1],
                           "present_seconds": 4 * 3600, "runs": runs}]
aw.write(conn, refresh_day=day)

def span():
    r = conn.execute("SELECT span_minutes FROM v_day_span WHERE attendance_day=?", (day,)).fetchone()
    return r[0] if r else 0
check("AW alone", span(), 240)
digest_before = derive.input_digest(conn, day[:7])

# clockd opens a live session and records a run, partly an agent working while the user is
# away -- exactly the time D3 keeps out of the headline
d = clockd.Clockd(conn)
d._open_session(T(14))
d._event("run_start", T(14), actor="agent")
d._event("run_stop", T(18), actor="agent")
check("LIVE RUN NOT COUNTED IN SHADOW", span(), 240)
check("but recorded and visible", conn.execute(
    "SELECT SUM(seconds)/60 FROM v_live_interval WHERE attendance_day=?", (day,)).fetchone()[0], 240)

# the hourly AW refresh must still write the day: a shadow live session does not own it
aw.write(conn, refresh_day=day)
check("AW refresh not blocked by the live session", span(), 240)

# an OPEN live run must not swallow a hand interval -- in shadow it is not counted
d._event("run_start", T(19), actor="agent")
hotkey.start("", now=T(19, 5))
r = hotkey.stop(conn, now=T(19, 35))
check("hand interval not 'covered' by a shadow run", r["action"], "recorded")
check("hand minutes counted", span(), 270)
d._event("run_stop", T(20), actor="agent")

# clockd adopts only its own session: the hand session never closes
d2 = clockd.Clockd(conn)
d2.adopt_session(T(20, 5))
own = conn.execute("SELECT provenance FROM work_session WHERE id=?", (d2.session_id,)).fetchone()
check("adopts a live session, never the hand one", own[0] if own else None, "live")

# promotion is one row, and it is pinned in the digest
check("digest unchanged by shadow rows? no -- rows are inputs", digest_before != derive.input_digest(conn, day[:7]), True)
pre = derive.input_digest(conn, day[:7])
conn.execute("UPDATE schema_meta SET v='1' WHERE k='live_counts'"); conn.commit()
check("promoted", migrate.live_counts(conn), True)
check("promotion counts the live runs", span() > 270, True)
check("promotion is visible in the digest", pre != derive.input_digest(conn, day[:7]), True)

if fails:
    print("shadow FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("shadow ok (7 scenarios, 14 assertions)")
PY
