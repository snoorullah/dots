"""day_class seeding: the denominator of every monthly figure.

Target = (weekdays - paid holidays - approved leave) x hours_per_day. Holidays reduce the
denominator rather than becoming a shortfall, which also means the hourly rate rises in a
month with more holidays -- that is the employer's formula (monthly gross / working days
/ hours_per_day), not an approximation of it.
"""
import calendar as _cal
from datetime import date

from . import config


def classify(day, holidays=None, week_off=None, hours=None):
    """(kind, leave_type, target_minutes) for a date, before any attestation."""
    holidays = config.holidays() if holidays is None else holidays
    week_off = config.week_off() if week_off is None else week_off
    hours = config.hours_per_day() if hours is None else hours
    if day.weekday() in week_off:
        return "weekend", None, 0
    if day in holidays:
        return "holiday", None, 0
    return "working", None, hours * 60


def seed_month(conn, year, month):
    """Insert day_class rows for a month.

    Never overwrites a row that has been attested or already classified as leave or
    absent: those came from the user answering a prompt, and a reseed must not silently
    discard an answer.
    """
    holidays, week_off, hours = config.holidays(), config.week_off(), config.hours_per_day()
    kept = inserted = updated = 0
    # a kind the user set by hand in the vault (vault.py) is an answer like any other: the
    # hourly reseed must not turn a holiday they declared back into a working day
    pinned = set()
    if conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'day_edit_log'").fetchone():
        pinned = {r[0] for r in conn.execute(
            "SELECT DISTINCT day FROM day_edit_log WHERE action = 'kind'")}
    for dom in range(1, _cal.monthrange(year, month)[1] + 1):
        day = date(year, month, dom)
        kind, leave, target = classify(day, holidays, week_off, hours)
        row = conn.execute(
            "SELECT kind, attested_unix FROM day_class WHERE day=?", (day.isoformat(),)
        ).fetchone()
        if row is not None:
            if day.isoformat() in pinned or row["attested_unix"] is not None or row["kind"] in (
                "leave_paid", "leave_unpaid", "absent", "worked_unlogged"
            ):
                kept += 1
                continue
            conn.execute(
                "UPDATE day_class SET kind=?, leave_type=?, target_minutes=? WHERE day=?",
                (kind, leave, target, day.isoformat()),
            )
            updated += 1
        else:
            conn.execute(
                "INSERT INTO day_class(day, kind, leave_type, pay_affecting, target_minutes)"
                " VALUES(?,?,?,0,?)",
                (day.isoformat(), kind, leave, target),
            )
            inserted += 1
    conn.commit()
    return {"inserted": inserted, "updated": updated, "kept": kept}


def month_target(conn, month):
    """(target_minutes, working_days) for a 'YYYY-MM'."""
    row = conn.execute(
        "SELECT COALESCE(SUM(target_minutes),0) AS t,"
        "       SUM(CASE WHEN target_minutes>0 THEN 1 ELSE 0 END) AS d"
        " FROM day_class WHERE day LIKE ?",
        (month + "-%",),
    ).fetchone()
    return int(row["t"] or 0), int(row["d"] or 0)
