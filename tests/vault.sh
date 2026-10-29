#!/usr/bin/env bash
# vault.py + migrate WORK_V6: the Obsidian-editable timesheet. What must never happen: a
# half-typed file read as an edit, a measured figure frozen into an "edit" the user never
# made, a bad cell applied in part, a held file rewritten over the mistake, text under
# `## Notes` lost, a submitted month moved, a future day given hours, or an edited day
# asked about again.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
mkdir -p "$tmp/vault"
export TIMETRACK_STATE_DIR="$tmp/state" TIMETRACK_VAULT="$tmp/vault" XDG_CONFIG_HOME="$tmp/config"
python3 - "$tmp" <<'PY'
import os, re, sqlite3, sys
from datetime import date, datetime, timedelta
from pathlib import Path

from timetrack import calendar_, config, dbs, derive, interactive, migrate, notify, vault

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

T = datetime(2026, 10, 15, 12, 0).timestamp()          # "now": Thu 15 Oct 2026
toasts = []
notify.toast = lambda *a, **k: toasts.append(a)

def unix(day, hm, plus=0):
    d = date.fromisoformat(day) + timedelta(days=plus)
    h, m = hm.split(":")
    return int(datetime(d.year, d.month, d.day, int(h), int(m)).timestamp())

# --- a v5 database with data in it, then the migration ---------------------------------
conn = dbs.open_work()
for v, sql in migrate.MIGRATIONS["work"][:5]:
    conn.executescript(sql)
    conn.execute(f"PRAGMA user_version = {v}")
conn.commit()
calendar_.seed_month(conn, 2026, 10)
calendar_.seed_month(conn, 2026, 9)

def session(day, runs):
    cur = conn.execute(
        "INSERT INTO work_session(opened_ts,opened_unix,attendance_day,open_trigger,provenance)"
        " VALUES(?,?,?,?,?)", (day, unix(day, runs[0][0]), day, "aw", "aw"))
    sid = cur.lastrowid
    for a, b, plus in runs:
        for kind, ts in (("run_start", unix(day, a)), ("run_stop", unix(day, b, plus))):
            conn.execute(
                "INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,actor,"
                "provenance,ruleset,confidence) VALUES(?,?,?,?,?,?,?,?,?)",
                (day, ts, day, sid, kind, "human", "aw", "v1", 1.0))

def ded(day, a, b, cat, minutes, confirmed, prov="aw"):
    conn.execute(
        "INSERT INTO deduction(attendance_day,start_unix,end_unix,category,minutes,confirmed,"
        "provenance) VALUES(?,?,?,?,?,?,?)",
        (day, unix(day, a), unix(day, b), cat, minutes, confirmed, prov))

session("2026-10-01", [("19:23", "03:28", 1)])
ded("2026-10-01", "21:00", "21:30", "lunch", 30, 1)
ded("2026-10-01", "23:00", "23:15", "misc", 15, 0)
ded("2026-10-01", "23:30", "23:45", "misc", 0, 1, "manual:meeting")   # a meeting: worked time
session("2026-10-05", [("10:00", "18:00", 0)])
session("2026-10-06", [("14:00", "18:00", 0), ("21:00", "02:00", 1)])  # 3h between shifts
session("2026-09-01", [("10:00", "18:00", 0)])
conn.commit()

def snap():
    return [tuple(r) for r in conn.execute(
        "SELECT attendance_day, kind, target_minutes, span_minutes, first_unix, last_unix,"
        " provenance, deduction_minutes, unconfirmed, net_minutes FROM v_day_worked"
        " ORDER BY attendance_day")]
before = snap()
conn.close()
migrate.migrate()
conn = dbs.open_work()
check("user_version", conn.execute("PRAGMA user_version").fetchone()[0], 6)
check("measured figures unchanged by the migration", snap(), before)
check("day_edit exists", conn.execute("SELECT COUNT(*) FROM day_edit").fetchone()[0], 0)
check("doctor expects v6", max(v for v, _ in migrate.MIGRATIONS["work"]), 6)

# --- helpers ----------------------------------------------------------------------------
SHEET = config.TIMESHEET / "2026-10.md"
def day_note(day): return config.TIMESHEET_DAYS / f"{day}.md"
def settle():
    """Pretend time has passed: every vault file untouched for 100 s."""
    for p in vault.vault_files():
        os.utime(p, (T - 100, T - 100))
def age(p, secs): os.utime(p, (T - secs, T - secs))
def sync():
    r = vault.sync(conn, T); settle(); return r
def row(day):
    return conn.execute("SELECT * FROM v_day_worked WHERE attendance_day=?", (day,)).fetchone()
def edit_row(day):
    return conn.execute("SELECT * FROM day_edit WHERE day=?", (day,)).fetchone()
def sheet_cell(day, col, val, secs=100, month="2026-10"):
    p = config.TIMESHEET / f"{month}.md"
    lines, i = p.read_text().split("\n"), vault.HEADER.index(col)
    for n, l in enumerate(lines):
        if l.startswith(f"| [[days/{day}"):
            cells = vault.split_row(l); cells[i] = val
            lines[n] = "| " + " | ".join(cells) + " |"
    p.write_text("\n".join(lines)); age(p, secs)
def note_field(day, key, val, secs=100):
    p = day_note(day)
    p.write_text(re.sub(rf'(?m)^{key}: ".*"$', f'{key}: "{val}"', p.read_text())); age(p, secs)
def cells(day, month="2026-10"):
    for l in (config.TIMESHEET / f"{month}.md").read_text().split("\n"):
        if l.startswith(f"| [[days/{day}"):
            return dict(zip(vault.HEADER, vault.split_row(l)))
def log(action=None):
    return [dict(r) for r in conn.execute(
        "SELECT * FROM day_edit_log" + (" WHERE action=?" if action else "") + " ORDER BY id",
        (action,) if action else ())]

# --- render ------------------------------------------------------------------------------
rep = vault.render(conn, "2026-10", T)
check("sheet written", SHEET.exists(), True)
check("15 day notes (up to today only)", len(list(config.TIMESHEET_DAYS.iterdir())), 15)
check("15 rows", sum(1 for l in SHEET.read_text().split("\n") if l.startswith("| [[days/")), 15)
c = cells("2026-10-01")
check("row 10-01", (c["Day"], c["Kind"], c["Login"], c["Logout"], c["Off"], c["Lunch"],
                    c["Unsure"], c["Net"], c["Target"], c["Source"]),
      ("Thu", "working", "19:23", "03:28+1", "0:00", "0:30", "0:15", "7:20", "8:00", "aw"))
c = cells("2026-10-06")
check("multi-shift row shows Off", (c["Login"], c["Logout"], c["Off"], c["Net"]), ("14:00", "02:00+1", "3:00", "9:00"))
check("weekend row has no hours", (cells("2026-10-03")["Login"], cells("2026-10-03")["Lunch"]), ("", ""))
check("totals line", "**Worked**" in SHEET.read_text() and "**Delta**" in SHEET.read_text(), True)
check("note frontmatter", 'login: "19:23"' in day_note("2026-10-01").read_text(), True)
check("note lists measured breaks", "lunch 0:30" in day_note("2026-10-01").read_text(), True)

settle()
mt = {p: p.stat().st_mtime_ns for p in vault.vault_files()}
rep = vault.render(conn, "2026-10", T)
check("idempotent render writes nothing", rep["written"], [])
check("mtimes unchanged", {p: p.stat().st_mtime_ns for p in vault.vault_files()}, mt)

# a round trip with no typing: nothing becomes an edit (multi-shift day included)
r = sync()
check("no-op sync", (r["applied"], r["rejected"]), (0, 0))
check("no day_edit from a round trip", conn.execute("SELECT COUNT(*) FROM day_edit").fetchone()[0], 0)
check("measured figures survive a round trip", snap()[:len(before)], before[:len(before)])

# --- quiet window ------------------------------------------------------------------------
digest0 = derive.input_digest(conn, "2026-10")
gaps0 = [g["attendance_day"] for g in interactive.pending_gaps(conn, "2026-10")]
check("gap pending before an edit", gaps0, ["2026-10-01"])
note_field("2026-10-05", "login", "09:00", secs=5)           # typed 5 s ago
r = sync()
check("fresh file not read", edit_row("2026-10-05"), None)
check("fresh file untouched", 'login: "09:00"' in day_note("2026-10-05").read_text(), True)
vault.render(conn, "2026-10", T)
check("fresh file not overwritten by render", 'login: "09:00"' in day_note("2026-10-05").read_text(), True)

# --- edit login in a day note ---------------------------------------------------------------
age(day_note("2026-10-05"), 100)
r = sync()
w = row("2026-10-05")
check("edit applied", r["applied"], 1)
check("login moved", w["first_unix"], unix("2026-10-05", "09:00"))
check("span grew", w["span_minutes"], 540)
check("provenance vault", w["provenance"], "vault")
check("net from the edit", w["net_minutes"], 540)
check("surface day", edit_row("2026-10-05")["surface"], "day")
check("row shows edited", cells("2026-10-05")["Source"], "edited")
check("digest changed by a day_edit", derive.input_digest(conn, "2026-10") != digest0, True)
check("log set", [l["action"] for l in log()], ["set"])

# --- edit a break in the month table ----------------------------------------------------------
sheet_cell("2026-10-05", "Lunch", "1h")
r = sync()
check("break edit", (row("2026-10-05")["net_minutes"], edit_row("2026-10-05")["lunch"], edit_row("2026-10-05")["surface"]),
      (480, 60, "month"))
check("note re-rendered with the new break", 'lunch: "1:00"' in day_note("2026-10-05").read_text(), True)

# --- the same day in both: the newer file wins ---------------------------------------------------
note_field("2026-10-05", "lunch", "0:30", secs=100)
sheet_cell("2026-10-05", "Lunch", "0:45", secs=50)
r = sync()
check("newer wins", edit_row("2026-10-05")["lunch"], 45)
note_field("2026-10-05", "dinner", "0:20", secs=30)
sheet_cell("2026-10-05", "Dinner", "0:10", secs=90)
sync()
check("newer wins (note this time)", edit_row("2026-10-05")["dinner"], 20)

# --- notes survive ---------------------------------------------------------------------------------
p = day_note("2026-10-05")
p.write_text(p.read_text() + "\nCall with the platform team.\n  - indented  \n\n# a heading\n"); age(p, 100)
note_field("2026-10-05", "misc", "0:05")
sync()
txt = p.read_text()
check("notes kept verbatim", txt.endswith("## Notes\n\nCall with the platform team.\n  - indented  \n\n# a heading\n"), True)
check("edit beside the notes applied", edit_row("2026-10-05")["misc"], 5)
settle(); vault.render(conn, "2026-10", T)
check("notes kept across a render", p.read_text().endswith("## Notes\n\nCall with the platform team.\n  - indented  \n\n# a heading\n"), True)

# --- an edited day stops being asked about -----------------------------------------------------------
sheet_cell("2026-10-01", "Lunch", "0:40")
sync()
check("edited day leaves pending_gaps", [g["attendance_day"] for g in interactive.pending_gaps(conn, "2026-10")], [])
e = edit_row("2026-10-01")
check("edit keeps the measured seconds", (e["login_unix"], e["logout_unix"]), (unix("2026-10-01", "19:23"), unix("2026-10-01", "03:28", 1)))
check("unsure carried as a break and flags the day",
      (e["unsure"], row("2026-10-01")["unconfirmed"], row("2026-10-01")["deduction_minutes"]), (15, 1, 55))

# --- multi-shift day: Off round-trips, and an edit beside it keeps the span -----------------------------
s0 = row("2026-10-06")["span_minutes"]
sheet_cell("2026-10-06", "Lunch", "0:30")
sync()
check("Off kept through an edit", (edit_row("2026-10-06")["off_minutes"], row("2026-10-06")["span_minutes"], row("2026-10-06")["net_minutes"]),
      (180, s0, s0 - 30))
check("Off cell unchanged", cells("2026-10-06")["Off"], "3:00")

# --- invalid edit: held, nothing applied, toast, untouched; then fixed -------------------------------------
toasts.clear()
note_field("2026-10-06", "login", "25:99")
note_field("2026-10-06", "lunch", "9:00", secs=100)
bad = day_note("2026-10-06").read_text()
r = sync()
check("rejected + held", (r["rejected"], r["held"]), (1, 1))
check("nothing applied from a held file", edit_row("2026-10-06")["lunch"], 30)
check("toast", (toasts[0][0], toasts[0][1], toasts[0][2].startswith("2026-10-06: ")), ("timetrack", "Timesheet edit not saved", True))
check("rejection logged", [l["action"] for l in log("rejected")][-1], "rejected")
sync(); vault.render(conn, "2026-10", T); settle()
check("held file untouched", day_note("2026-10-06").read_text(), bad)
check("held file does not toast again", len(toasts), 1)
note_field("2026-10-06", "login", "13:30")
note_field("2026-10-06", "lunch", "0:30")
sync()
check("fixing applies", edit_row("2026-10-06")["login_unix"], unix("2026-10-06", "13:30"))
check("held cleared", vault.load_state()["held"], {})
# breaks that do not fit
toasts.clear()
sheet_cell("2026-10-05", "Lunch", "9h")
sync()
check("breaks longer than the day rejected", (edit_row("2026-10-05")["lunch"], len(toasts)), (45, 1))
sheet_cell("2026-10-05", "Lunch", "0:45")
sync()
check("then fixed", vault.load_state()["held"], {})

# --- clear login and logout: back to measured ----------------------------------------------------------------
sheet_cell("2026-10-05", "Login", ""); sheet_cell("2026-10-05", "Logout", "")
sync()
w = row("2026-10-05")
check("reverted", (edit_row("2026-10-05"), w["first_unix"], w["span_minutes"], w["provenance"]),
      (None, unix("2026-10-05", "10:00"), 480, "aw"))
check("clear logged", [l["action"] for l in log("clear")][-1:], ["clear"])
check("cell back to measured", cells("2026-10-05")["Login"], "10:00")
check("session still there", conn.execute("SELECT COUNT(*) FROM work_session WHERE attendance_day='2026-10-05'").fetchone()[0], 1)

# --- +1 and the implicit next day ---------------------------------------------------------------------------------
note_field("2026-10-08", "login", "19:00"); note_field("2026-10-08", "logout", "03:30+1")
note_field("2026-10-09", "login", "20:00"); note_field("2026-10-09", "logout", "04:00")
sync()
check("explicit +1", (row("2026-10-08")["last_unix"], row("2026-10-08")["span_minutes"]), (unix("2026-10-08", "03:30", 1), 510))
check("implicit next day", (row("2026-10-09")["last_unix"], row("2026-10-09")["span_minutes"]), (unix("2026-10-09", "04:00", 1), 480))
check("rendered canonically", cells("2026-10-09")["Logout"], "04:00+1")
for s, want in (("45", 45), ("45m", 45), ("0:45", 45), ("1h05", 65), ("1h", 60), ("", 0), ("0", 0)):
    check(f"duration {s!r}", vault.parse_minutes(s), want)
try:
    vault.parse_minutes("-5"); fails.append("negative minutes accepted")
except ValueError:
    pass

# --- kind: day_class only, and it sticks ----------------------------------------------------------------------------
sheet_cell("2026-10-07", "Kind", "holiday")
sheet_cell("2026-10-10", "Kind", "working")                    # a Saturday
sync()
c7 = conn.execute("SELECT kind, target_minutes FROM day_class WHERE day='2026-10-07'").fetchone()
c10 = conn.execute("SELECT kind, target_minutes FROM day_class WHERE day='2026-10-10'").fetchone()
check("holiday target 0", tuple(c7), ("holiday", 0))
check("working target a full day", tuple(c10), ("working", 480))
check("kind edit froze no hours", (edit_row("2026-10-07"), edit_row("2026-10-10")), (None, None))
check("kind logged", [(l["day"], l["action"]) for l in log("kind")], [("2026-10-07", "kind"), ("2026-10-10", "kind")])
calendar_.seed_month(conn, 2026, 10)
check("reseed keeps a kind the user set", (conn.execute("SELECT kind FROM day_class WHERE day='2026-10-07'").fetchone()[0],
      conn.execute("SELECT kind FROM day_class WHERE day='2026-10-10'").fetchone()[0]), ("holiday", "working"))
# a kind change on a measured day leaves its measured hours alone
sheet_cell("2026-10-05", "Kind", "leave_paid")
sync()
check("kind change does not freeze measured hours", (edit_row("2026-10-05"), row("2026-10-05")["provenance"]), (None, "aw"))

# --- future day: kind yes, hours no --------------------------------------------------------------------------------------
toasts.clear()
p = SHEET
p.write_text(p.read_text().replace("\n**Worked**", "\n| [[days/2026-10-20\\|2026-10-20]] | Tue | holiday | 10:00 | 18:00 |  |  |  |  |  |  |  |  |  |  |  |\n\n**Worked**", 1)); age(p, 100)
sync()
check("future kind accepted", conn.execute("SELECT kind, target_minutes FROM day_class WHERE day='2026-10-20'").fetchone()[0:2], ("holiday", 0))
check("future hours rejected", (edit_row("2026-10-20"), len(toasts), [l["reason"][:6] for l in log("rejected")][-1]), (None, 1, "future"))
check("future row not rendered", cells("2026-10-20"), None)

# --- submitted month: rejected, restored ----------------------------------------------------------------------------------------
vault.render(conn, "2026-09", T); settle()
conn.execute("INSERT INTO monthly_submission VALUES('2026-09',1,0,0,0,'net','v1','x','x')"); conn.commit()
orig = (config.TIMESHEET / "2026-09.md").read_text()
sheet_cell("2026-09-01", "Lunch", "2h", month="2026-09")
toasts.clear()
r = sync()
check("submitted rejected", (edit_row("2026-09-01"), log("rejected")[-1]["reason"], len(toasts)), (None, "submitted", 1))
vault.render(conn, "2026-09", T)
check("submitted month restored", (config.TIMESHEET / "2026-09.md").read_text(), orig)

# --- wait-quiet ---------------------------------------------------------------------------------------------------------------------
clock = {"t": T}; naps = []
age(SHEET, 0)
def nap(s): naps.append(s); clock["t"] += s
check("wait-quiet waits then returns", vault.wait_quiet(now=lambda: clock["t"], sleep=nap), True)
check("it slept for the quiet window", sum(naps) >= vault.QUIET, True)

# --- no vault on the machine: render is a no-op ---------------------------------------------------------------------------------------
import shutil
shutil.rmtree(config.VAULT);
check("no vault, no files", (vault.render(conn, "2026-10", T)["written"], config.VAULT.exists()), ([], False))

# --- the CLI is wired -------------------------------------------------------------------------------------------------------------------
from timetrack.__main__ import main
import contextlib, io
with contextlib.redirect_stdout(io.StringIO()) as out:
    rc = main(["vault", "log", "--month", "2026-10"])
check("vault log", (rc, "rejected" in out.getvalue()), (0, True))

if fails:
    print("vault FAILED:")
    for f in fails: print("  " + f)
    sys.exit(1)
print("vault ok")
PY
