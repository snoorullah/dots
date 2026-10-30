#!/usr/bin/env bash
# breaklabel.py + migrate PRIVATE_V8: what a break WAS (picker key), kept beside the deduction.
# What must never happen: a label changing category/minutes/provenance or any worked total, a
# label lost when the hourly AW refresh re-inserts the same gap, or a note that varies run to run.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
mkdir -p "$tmp/vault"
export TIMETRACK_STATE_DIR="$tmp/state" TIMETRACK_VAULT="$tmp/vault" XDG_CONFIG_HOME="$tmp/config"
python3 - "$tmp" <<'PY'
import contextlib, io, sys
from datetime import datetime
from pathlib import Path

from timetrack import away, breaklabel, calendar_, config, dbs, migrate, vault
from timetrack.__main__ import main

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

tmp = Path(sys.argv[1])
away.STATE = tmp / "state" / "away-state.json"
away.INTENT = tmp / "state" / "away-intent.json"
config.PANIC = tmp / "config" / "timetrack" / "PANIC"
away._toast = lambda body: None
away._brief = away._wrap = lambda *a: None
away.aw.write = lambda conn, **kw: None

migrate.migrate()
with dbs.open_private() as p:
    check("private v8+", p.execute("PRAGMA user_version").fetchone()[0] >= 8, True)
    check("table", [r[1] for r in p.execute("PRAGMA table_info(away_label)")],
          ["start_unix", "end_unix", "day", "key", "label", "source"])

T = int(datetime(2026, 10, 15, 22, 0).timestamp())
DAY = "2026-10-15"
conn = dbs.open_work()
calendar_.seed_month(conn, 2026, 10)
sid = conn.execute("INSERT INTO work_session(opened_ts,opened_unix,attendance_day,open_trigger,"
                   "provenance) VALUES(?,?,?,?,?)", (DAY, T - 30000, DAY, "aw", "aw")).lastrowid
conn.execute("INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,actor,provenance,"
             "ruleset,confidence) VALUES(?,?,?,?,?,?,?,?,?)",
             (DAY, T - 30000, DAY, sid, "run_start", "human", "aw", "v1", 1.0))
conn.execute("INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,actor,provenance,"
             "ruleset,confidence) VALUES(?,?,?,?,?,?,?,?,?)",
             (DAY, T + 3000, DAY, sid, "run_stop", "human", "aw", "v1", 1.0))
def gap(g0, g1):
    return conn.execute("INSERT INTO deduction(session_id,attendance_day,start_unix,end_unix,"
                        "category,minutes,confirmed,provenance) VALUES(?,?,?,?,?,?,?,?)",
                        (sid, DAY, g0, g1, "misc", (g1 - g0) / 60, 0, "backfill:aw")).lastrowid
walk, short, asked = gap(T - 3720, T - 0), gap(T - 9000, T - 8760), gap(T - 20000, T - 18000)
conn.commit()
row = lambda i: dict(conn.execute("SELECT * FROM deduction WHERE id=?", (i,)).fetchone())
worked = lambda: [tuple(r) for r in conn.execute("SELECT * FROM v_day_worked ORDER BY attendance_day")]
lab = lambda s: dbs.open_private().execute("SELECT * FROM away_label WHERE start_unix=?", (s,)).fetchone()

# 1. declared walk: label written, deduction exactly as an unlabelled answer would leave it
base = worked()
away.declare("walk", now=T - 3750)
check("declared", away.handle(T - 3720, T, T + 10), "declared:walk")
r = row(walk)
check("walk stays misc, same minutes", (r["category"], r["minutes"], r["confirmed"], r["provenance"]),
      ("misc", 62.0, 1, away.DECLARED))
l = lab(T - 3720)
check("declared label", l and (l["key"], l["label"], l["source"], l["day"], l["end_unix"]),
      ("walk", "Walk / short break", "declared", DAY, T))

# 2. auto short break (< 5 min)
check("auto", away.handle(T - 9000, T - 8760, T + 20), "auto")
l = lab(T - 9000)
check("auto label", l and (l["key"], l["label"], l["source"]), ("auto", "Short break", "auto"))
check("auto deduction", (row(short)["category"], row(short)["provenance"]), ("misc", away.AUTO))

# 3. asked panel path
panel = lambda c: __import__("subprocess").CompletedProcess(c, 0, stdout="washroom\n", stderr="")
check("asked", away.handle(T - 20000, T - 18000, T + 30, launch=panel), "answered:washroom")
l = lab(T - 20000)
check("asked label", l and (l["key"], l["label"], l["source"]),
      ("washroom", "Washroom / pantry", "asked"))
check("asked category", row(asked)["category"], "washroom")

# 4. totals match a run with no labels at all
with_labels = worked()
with dbs.open_private() as p:
    p.execute("DELETE FROM away_label"); p.commit()
check("v_day_worked identical without labels", worked(), with_labels)
check("unlabelled run has no label", breaklabel.for_day(DAY), {})
for s, k, lb, src in ((T - 3720, "walk", "Walk / short break", "declared"),
                      (T - 9000, "auto", "Short break", "auto"),
                      (T - 20000, "washroom", "Washroom / pantry", "asked")):
    breaklabel.record(s, None, DAY, k, lb, src)

# 5. survives an AW refresh: same interval deleted and re-inserted as a fresh row
old = row(walk)
conn.execute("DELETE FROM deduction WHERE id=?", (walk,))
conn.execute("INSERT INTO deduction(session_id,attendance_day,start_unix,end_unix,category,minutes,"
             "confirmed,provenance) VALUES(?,?,?,?,?,?,?,?)",
             (sid, DAY, old["start_unix"], old["end_unix"], "misc", 62.0, 1, away.DECLARED))
conn.commit()
check("label survives refresh", breaklabel.for_day(DAY).get(T - 3720), "Walk / short break")

# 6. the day note shows it, deterministically
vault.render(conn, "2026-10", T)
note_path = config.TIMESHEET_DAYS / f"{DAY}.md"
note = note_path.read_text()
lines = note.split("\n")
clk = vault.derive.clock
check("note shows label", f"- {clk(T - 3720)} to {clk(T)}  Walk / short break (misc) 1:02" in lines, True)
check("auto gap labelled", f"- {clk(T - 9000)} to {clk(T - 8760)}  Short break (misc) 0:04" in lines, True)
check("asked gap labelled", f"- {clk(T - 20000)} to {clk(T - 18000)}  Washroom / pantry (washroom) 0:33" in lines, True)
note_path.unlink()
vault.render(conn, "2026-10", T)
check("note deterministic", note_path.read_text(), note)

# 7. read helper: minutes per label, category fallback
with dbs.open_private() as p:
    p.execute("DELETE FROM away_label WHERE start_unix=?", (T - 20000,)); p.commit()
check("minutes per label", breaklabel.minutes("attendance_day = ?", (DAY,)),
      [("Walk / short break", 62.0), ("washroom", 2000 / 60), ("Short break", 4.0)])
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    main(["breaks", "--day", DAY])
check("breaks cmd", "Walk / short break" in buf.getvalue() and "washroom" in buf.getvalue(), True)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    main(["breaks", "--month", "2026-10"])
check("breaks --month", "Breaks 2026-10" in buf.getvalue(), True)

if fails:
    print("FAIL"); print("\n".join(fails)); sys.exit(1)
print("break-labels: all checks passed")
PY
