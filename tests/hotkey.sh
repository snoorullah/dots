#!/usr/bin/env bash
# The manual interval (D4), and the one way it could inflate a payroll figure.
#
# v_day_span SUMS run intervals; it does not merge them. So an interval written by hand
# that overlaps one the daemon already recorded is counted TWICE -- and this is the only
# path in the system where a user action writes run rows directly, so it is the only place
# that can happen. Every assertion below is about that.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - <<'PY'
import time
from datetime import date, datetime

from timetrack import config, dbs, hotkey, migrate

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

migrate.migrate()
conn = dbs.open_work()
# these runs stand for what clockd RECORDED and COUNTS, so the live clock is promoted
# here; shadow mode (live recorded, not counted) is tests/shadow.sh's subject
conn.execute("UPDATE schema_meta SET v='1' WHERE k='live_counts'"); conn.commit()
# pinned to noon: the real clock made "now - 2h" cross midnight between 00:00 and 02:00
now = int(datetime.combine(date.today(), datetime.min.time()).timestamp()) + 12 * 3600
day = date.fromtimestamp(now).isoformat()
def iso(t): return datetime.fromtimestamp(t).isoformat(timespec="seconds")

def session():
    cur = conn.execute(
        "INSERT INTO work_session(opened_ts,opened_unix,attendance_day,open_trigger,"
        "provenance) VALUES(?,?,?,?,?)", (iso(now - 7200), now - 7200, day, "test", "live"))
    conn.commit()
    return cur.lastrowid

def run(sid, t0, t1=None):
    for kind, t in (("run_start", t0), ("run_stop", t1)):
        if t is None:            # an UNPAIRED run_start: the daemon has it open right now
            continue
        conn.execute(
            "INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,actor,"
            "provenance,ruleset,confidence) VALUES(?,?,?,?,?,'human','live',?,1.0)",
            (iso(t), t, day, sid, kind, config.RULESET))
    conn.commit()

def span():
    v = conn.execute("SELECT span_minutes FROM v_day_span WHERE attendance_day=?",
                     (day,)).fetchone()
    return v[0] if v else 0

# 1. a mis-press records nothing. Under a minute is not an interval.
hotkey.start("", now=now - 20)
r = hotkey.stop(conn, now=now)
check("mis-press", r["action"], "too_short")
check("mis-press wrote nothing", span(), 0)

# 2. the ordinary case: nothing else covered it, so it is recorded, and at confidence 1.0
#    with provenance 'hotkey' so it stays separable from anything measured.
hotkey.start("whiteboard", now=now - 1800)
r = hotkey.stop(conn, now=now)
check("recorded", r["action"], "recorded")
check("30 minutes", span(), 30)
row = conn.execute("SELECT provenance, confidence, reason_code, actor FROM clock_event"
                   " WHERE kind='run_start'").fetchone()
check("provenance", row["provenance"], "hotkey")
check("confidence", row["confidence"], 1.0)
check("reason", row["reason_code"], "hotkey")
check("actor", row["actor"], "human")
check("a session was opened for it", conn.execute(
    "SELECT open_trigger FROM work_session").fetchone()[0], "hotkey")

# 3. THE DOUBLE COUNT. A closed interval already covers the window, so the hand-opened one
#    must add nothing -- and must say why rather than failing silently.
conn.execute("DELETE FROM clock_event"); conn.execute("DELETE FROM work_session"); conn.commit()
sid = session()
run(sid, now - 3600, now - 60)                 # the daemon recorded 59 minutes
check("daemon span", span(), 59)
hotkey.start("same time, by hand", now=now - 1800)
r = hotkey.stop(conn, now=now - 600)
check("covered", r["action"], "covered")
check("span unchanged", span(), 59)

# 4. an UNPAIRED run_start is the subtler half: the daemon has a run open and will close it
#    later at a time that covers this window. Checking only closed intervals would pass
#    here and double-count the moment the daemon wrote its run_stop.
conn.execute("DELETE FROM clock_event"); conn.execute("DELETE FROM work_session"); conn.commit()
sid = session()
run(sid, now - 3600)                           # start with no stop: clockd owns it
hotkey.start("", now=now - 1800)
r = hotkey.stop(conn, now=now)
check("open run covers it", r["action"], "covered")
check("open run reason named", "clockd owns" in r["why"], True)
check("nothing written", conn.execute(
    "SELECT COUNT(*) FROM clock_event WHERE provenance='hotkey'").fetchone()[0], 0)

# 4b. ...but in SHADOW the same open live run covers nothing: its minutes are not in the
#     figure, so refusing the hand interval would drop real time.
conn.execute("DELETE FROM clock_event"); conn.execute("DELETE FROM work_session")
conn.execute("UPDATE schema_meta SET v='0' WHERE k='live_counts'"); conn.commit()
sid = session()
run(sid, now - 3600)
hotkey.start("", now=now - 1800)
check("shadow open run does not cover", hotkey.stop(conn, now=now)["action"], "recorded")
conn.execute("UPDATE schema_meta SET v='1' WHERE k='live_counts'"); conn.commit()

# 5. adjacent, not overlapping: the daemon stopped at T, the hand interval starts at T.
#    This must RECORD -- an over-eager guard would silently drop real work.
conn.execute("DELETE FROM clock_event"); conn.execute("DELETE FROM work_session"); conn.commit()
sid = session()
run(sid, now - 7200, now - 3600)
hotkey.start("", now=now - 3600)
r = hotkey.stop(conn, now=now - 1800)
check("adjacent records", r["action"], "recorded")
check("60 + 30 minutes", span(), 90)

# 6. stop with nothing open
check("stop when closed", hotkey.stop(conn, now=now)["action"], "not_open")
check("toggle opens", hotkey.toggle(conn, now=now)["action"], "started")
check("toggle closes", hotkey.toggle(conn, now=now + 120)["action"], "recorded")

if fails:
    print("hotkey FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("hotkey ok (7 scenarios, 20 assertions)")
PY
