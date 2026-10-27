#!/usr/bin/env bash
# D7 (away.py): declared on the way out (Super+Esc) or asked on the way back. What must
# never happen: a gap answered without the user, a neighbouring gap answered by mistake, a
# stale declaration answering a later gap, or presence after a logout counted to that day.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
python3 - "$tmp" <<'PY'
import subprocess, sys
from datetime import datetime
from pathlib import Path

from timetrack import away, config, dbs, migrate
from timetrack.backfill import aw

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

tmp = Path(sys.argv[1])
away.STATE = tmp / "state" / "away-state.json"
away.INTENT = tmp / "state" / "away-intent.json"
config.PANIC = tmp / "config" / "timetrack" / "PANIC"
away._toast = lambda body: None
aw.write = lambda conn, **kw: None      # the refresh is tests/refresh.sh's subject

T = int(datetime(2026, 10, 27, 17, 0).timestamp())
iso = lambda t: datetime.fromtimestamp(t).astimezone().isoformat()
ev = lambda t, status: {"timestamp": iso(t), "data": {"status": status}}

# 1. last_return
check("fresh return", away.last_return([ev(T, "not-afk"), ev(T - 1200, "afk")], T + 30), (T - 1200, T))
check("still away", away.last_return([ev(T, "afk"), ev(T - 600, "not-afk")], T + 30), None)
check("stale return", away.last_return([ev(T, "not-afk"), ev(T - 1200, "afk")], T + 600), None)
check("blip under MIN_GAP", away.last_return([ev(T, "not-afk"), ev(T - 60, "afk")], T + 30), None)

# 2. salah hint
pt = tmp / "prayer-times.conf"
pt.write_text("# generated\nAsr 17:15    # adhan 16:10\nMaghrib 17:52\n")
check("gap over Asr iqamah", away.salah_hint(T, T + 1800, pt), "Asr")
check("gap far from iqamah", away.salah_hint(T - 7200, T - 5400, pt), None)

migrate.migrate()
conn = dbs.open_work()
sid = conn.execute("INSERT INTO work_session(opened_ts,opened_unix,attendance_day,open_trigger,"
                   "provenance) VALUES(?,?,?,?,?)", (iso(T - 9000), T - 9000, "2026-10-27",
                   "aw", "backfill:aw")).lastrowid
def gap(g0, g1):
    return conn.execute("INSERT INTO deduction(session_id,attendance_day,start_unix,end_unix,"
                        "category,minutes,confirmed,provenance) VALUES(?,?,?,?,?,?,?,?)",
                        (sid, "2026-10-27", g0, g1, "misc", (g1 - g0) / 60, 0,
                         "backfill:aw")).lastrowid
row = lambda i: dict(conn.execute("SELECT * FROM deduction WHERE id=?", (i,)).fetchone())
short, long_, other = gap(T - 7200, T - 6960), gap(T - 3600, T - 1800), gap(T - 1700, T - 1000)
decl, stale, meal = gap(T - 12000, T - 10000), gap(T - 20000, T - 19000), gap(T - 30000, T - 28000)
conn.commit()

# 4. find_gap never answers a neighbour
check("matches its own gap", away.find_gap(conn, T - 3590, T - 1800)["id"], long_)
check("no match on a sliver", away.find_gap(conn, T - 1810, T - 1100) and
      away.find_gap(conn, T - 1810, T - 1100)["id"], other)

# 5. handle
check("short gap auto", away.handle(T - 7200, T - 6960, T), "auto")
r = row(short)
check("short: deducted, confirmed, marked auto", (r["category"], r["confirmed"], r["provenance"]),
      ("misc", 1, away.AUTO))

calls = []
def panel(answer, rc=0):
    def f(cmd):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, rc, stdout=answer, stderr="")
    return f

check("timeout leaves it alone", away.handle(T - 3600, T - 1800, T, launch=panel("", 2)), "unanswered")
check("still unconfirmed", row(long_)["confirmed"], 0)
check("meeting answered", away.handle(T - 3600, T - 1800, T + 100, launch=panel("meeting\n")),
      "answered:meeting")
r = row(long_)
check("meeting costs nothing", (r["minutes"], r["confirmed"], r["provenance"]),
      (0, 1, "manual:meeting"))

before = len(calls)
check("no budget: asked again", away.handle(T - 1700, T - 1000, T + 200, launch=panel("salah\n")),
      "answered:salah")
check("asked: panel shown", len(calls), before + 1)
before = len(calls)
other = gap(T - 900, T - 400); conn.commit()
away.STATE.unlink()
config.PANIC.parent.mkdir(parents=True, exist_ok=True); config.PANIC.touch()
check("PANIC defers", away.handle(T - 900, T - 400, T + 9000, launch=panel("salah\n")), "deferred")
check("no panel under PANIC", len(calls), before)

# 6. declared with Super+Esc: answered from the pick, no panel
config.PANIC.unlink()
away.declare("washroom", now=T - 12030)
n = len(calls)
check("declared answers the gap", away.handle(T - 12000, T - 10000, T + 20000, launch=panel("")),
      "declared:washroom")
r = row(decl)
check("declared: washroom, confirmed", (r["category"], r["confirmed"], r["provenance"]),
      ("washroom", 1, away.DECLARED))
check("declared: no panel", len(calls), n)
check("declaration consumed", away.INTENT.exists(), False)

away.declare("walk", now=T - 30000)   # stale: long before this gap began
away.STATE.unlink(missing_ok=True)
check("stale declaration ignored", away.handle(T - 20000, T - 19000, T + 30000,
      launch=panel("salah\n")), "answered:salah")

away.declare("meal", now=T - 30000)
check("morning long break is lunch", (away.handle(T - 30000, T - 28000, T + 40000),
      row(meal)["category"]), ("declared:meal", "lunch"))
check("long break from 17:00 is dinner", away.category("meal", T + 60), "dinner")
check("garbage panel output is no answer", away.handle(T - 900, T - 400, T + 50000,
      launch=panel("rm -rf /\n")), "unanswered")

# 7. log out ends the day: presence after it never extends that session
from datetime import timedelta
away.declare("logout", now=T)
check("logout recorded", conn.execute("SELECT COUNT(*) FROM logout WHERE ts_unix=?", (T,)).fetchone()[0], 1)
d = lambda h, m=0: datetime(2026, 10, 27, h, m).astimezone()
L = datetime.fromtimestamp(T).astimezone()
days = aw.workdays([(d(13), d(18)), (d(19), d(20))], [L])
check("logout ends the day; same-evening return dropped", [(x["open"].hour, x["close"].hour) for x in days], [(13, 17)])
nxt = datetime(2026, 10, 28, 1, 0).astimezone()
days = aw.workdays([(d(13), d(18)), (nxt, nxt + timedelta(hours=1))], [L])
check("01:00 after a logout is still dropped", [x["day"] for x in days], ["2026-10-27"])
nxt = datetime(2026, 10, 28, 12, 0).astimezone()
days = aw.workdays([(d(13), d(17)), (nxt, nxt + timedelta(hours=3))], [L])
check("next day's work counts", [x["day"] for x in days], ["2026-10-27", "2026-10-28"])
late = datetime(2026, 10, 28, 0, 30).astimezone()
days = aw.workdays([(d(20), late), (nxt, nxt + timedelta(hours=3))], [late])
check("00:30 logout does not black out the next day", [x["day"] for x in days], ["2026-10-27", "2026-10-28"])
check("no logout: one cluster", len(aw.workdays([(d(13), d(18)), (d(19), d(20))])), 1)
check("away after logout: nothing to answer", away.handle(T + 60, T + 3600, T + 60000), "declared:logout")

if fails:
    print("away FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("away ok (7 scenarios, 33 assertions)")
PY
