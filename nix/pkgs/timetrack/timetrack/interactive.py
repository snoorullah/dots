"""Walk the days that need a human, pre-filled with whatever evidence exists.

The plan calls for "one blocking panel per day". This is deliberately a TERMINAL prompt
instead: a blocking Hyprland panel is inescapable by design, and the dead-man's switch that
makes one safe is Phase 2 work. A command the user chooses to run needs no such guard, and
shipping the capability now is worth more than shipping the modal.

Two kinds of question, which are not the same:

  gaps  an absence was recorded but nobody knows what it WAS. An offline meeting is
        worked time; lunch is not. Until answered the minutes are deducted, so the
        figure understates -- answering can only ever move it up or leave it.
  days  a working day with no session at all. Was it worked and unlogged, leave, or
        genuinely absent? These change the TARGET as well as the total.

Everything written here is confidence 1.0 and provenance `manual`: it is the user's own
testimony, which is exactly what the sheet is.
"""
import sys
from datetime import date, datetime

from . import config, derive

PROVENANCE = "manual"
CONFIDENCE = 1.0

# A gap that was a meeting is WORKED time, so answering `meeting` must deduct nothing.
# That distinction is the whole reason gaps are asked about.
#
# It used to DELETE the deduction, which left no record that the question had ever been
# answered. The hourly AW refresh then re-derived the same gap from the same presence data
# and wrote it back as an unconfirmed deduction -- so a meeting the user had explicitly
# declared was deducted again an hour later, and asked about again. Now the row is KEPT
# at zero minutes with provenance manual:meeting: it deducts nothing, it is the durable
# record of the answer, and the refresh recognises it and leaves the interval alone.
# (deduction.category still has no `meeting` member, by design -- a meeting is not a kind
# of deduction. The provenance says what it was; the zero says what it costs.)
MEETING = "manual:meeting"
GAP_CHOICES = [
    ("1", "salah", "salah"),
    ("2", "lunch", "lunch"),
    ("7", "dinner", "dinner"),
    ("3", "washroom", "washroom"),
    ("4", "meeting", None),          # None => not a deduction at all
    ("5", "other", "misc"),
    ("6", "personal call", "call_personal"),
    ("s", "skip for now", "SKIP"),
]

DAY_CHOICES = [
    ("1", "worked but not logged", "worked_unlogged"),
    ("2", "paid leave (sick/casual)", "leave_paid"),
    ("3", "unpaid leave (reduces target)", "leave_unpaid"),
    ("4", "public holiday", "holiday"),
    ("5", "absent (shortfall stands)", "absent"),
    ("s", "skip for now", "SKIP"),
]


def _ask(prompt, choices):
    valid = {c[0] for c in choices}
    for key, label, _ in choices:
        print(f"    {key}) {label}")
    while True:
        try:
            got = input(f"  {prompt} ").strip().lower()
        except EOFError:
            return "SKIP"
        if got in valid:
            return next(c[2] for c in choices if c[0] == got)
        print("    ?")


def _clock(unix):
    return datetime.fromtimestamp(unix).strftime("%H:%M")


def pending_gaps(conn, month):
    return list(conn.execute(
        "SELECT id, attendance_day, start_unix, end_unix, minutes, category"
        " FROM deduction WHERE attendance_day LIKE ? AND confirmed = 0"
        # a day the user stated in the vault is theirs: asking about its gaps again would
        # contradict an answer they already typed
        " AND attendance_day NOT IN (SELECT day FROM day_edit WHERE salah IS NOT NULL"
        " OR lunch IS NOT NULL OR dinner IS NOT NULL OR washroom IS NOT NULL"
        " OR misc IS NOT NULL OR call_personal IS NOT NULL OR unsure IS NOT NULL)"
        " ORDER BY attendance_day, start_unix", (month + "-%",)))


def pending_days(conn, month, today=None):
    """Working days, already elapsed, with no recorded session at all."""
    today = today or date.today()
    out = []
    for r in conn.execute(
            "SELECT attendance_day, kind, target_minutes, span_minutes FROM v_day_worked"
            " WHERE attendance_day LIKE ? AND target_minutes > 0 ORDER BY attendance_day",
            (month + "-%",)):
        if (r["span_minutes"] or 0) > 0:
            continue
        if date.fromisoformat(r["attendance_day"]) >= today:
            continue           # not yet elapsed; nothing to explain
        out.append(dict(r))
    return out


def answer_gap(conn, gap_id, choice, provenance=PROVENANCE):
    """Record a human's answer for one gap. `choice` None means meeting: worked time."""
    if choice is None:
        # worked time: the deduction stops costing anything, and stays as the record
        conn.execute(
            "UPDATE deduction SET minutes = 0, confirmed = 1, provenance = ?"
            " WHERE id = ?", (MEETING, gap_id))
    else:
        conn.execute(
            "UPDATE deduction SET category = ?, confirmed = 1, provenance = ?"
            " WHERE id = ?", (choice, provenance, gap_id))


def resolve_gaps(conn, month):
    rows = pending_gaps(conn, month)
    if not rows:
        print("no unclassified gaps")
        return 0
    answered = 0
    for g in rows:
        print(f"\n  {g['attendance_day']}  {_clock(g['start_unix'])}-{_clock(g['end_unix'])}"
              f"  ({derive.hhmm(round(g['minutes']))} away)")
        choice = _ask("what was it?", GAP_CHOICES)
        if choice == "SKIP":
            continue
        answer_gap(conn, g["id"], choice)
        if choice is None:
            print(f"    -> meeting: {derive.hhmm(round(g['minutes']))} returned to worked time")
        else:
            print(f"    -> {choice}, confirmed")
        answered += 1
    conn.commit()
    return answered


def resolve_days(conn, month):
    rows = pending_days(conn, month)
    if not rows:
        print("no unexplained working days")
        return 0
    answered = 0
    for d in rows:
        print(f"\n  {d['attendance_day']}  no session recorded "
              f"(target {derive.hhmm(d['target_minutes'])})")
        choice = _ask("what happened?", DAY_CHOICES)
        if choice == "SKIP":
            continue
        if choice == "worked_unlogged":
            try:
                hours = float(input("    hours worked: ").strip())
            except (ValueError, EOFError):
                print("    skipped")
                continue
            start = int(datetime.fromisoformat(d["attendance_day"] + "T13:00:00").timestamp())
            end = start + int(hours * 3600)
            cur = conn.execute(
                "INSERT INTO work_session(opened_ts,opened_unix,closed_ts,closed_unix,"
                "attendance_day,open_trigger,close_trigger,provenance) VALUES(?,?,?,?,?,?,?,?)",
                (d["attendance_day"], start, d["attendance_day"], end,
                 d["attendance_day"], "manual", "manual", PROVENANCE))
            sid = cur.lastrowid
            for kind, ts in (("session_open", start), ("run_start", start),
                             ("run_stop", end), ("session_close", end)):
                conn.execute(
                    "INSERT INTO clock_event(ts,ts_unix,attendance_day,session_id,kind,"
                    "actor,provenance,ruleset,confidence) VALUES(?,?,?,?,?,?,?,?,?)",
                    (d["attendance_day"], ts, d["attendance_day"], sid, kind, "human",
                     PROVENANCE, config.RULESET, CONFIDENCE))
            print(f"    -> {hours}h recorded as attested")
        else:
            # leave_unpaid drops the target: an unpaid day is not owed
            target = 0 if choice in ("leave_unpaid", "holiday") else d["target_minutes"]
            conn.execute(
                "UPDATE day_class SET kind = ?, target_minutes = ? WHERE day = ?",
                (choice, target, d["attendance_day"]))
            print(f"    -> {choice}" + (" (target cleared)" if target == 0 else ""))
        answered += 1
    conn.commit()
    return answered


def run(conn, month):
    if not sys.stdin.isatty():
        raise SystemExit("timetrack: backfill --interactive needs a terminal")
    print(f"=== unclassified gaps in {month} ===")
    g = resolve_gaps(conn, month)
    print(f"\n=== unexplained working days in {month} ===")
    d = resolve_days(conn, month)
    return {"gaps_answered": g, "days_answered": d}
