"""Turn the event log into the figures a month is judged on.

Nothing here stores anything: every number is recomputed from clock_event each time, so
a rule change or a repaired gap is reflected immediately and a figure can always be
traced back to its rows. The one exception is monthly_submission, which is frozen on
purpose (see export).
"""
import hashlib
from datetime import date, datetime

from . import config


def _rates(working_days):
    """(daily, hourly) from monthly gross. The employer divides by WORKING days, so the
    hourly rate rises in a month with more holidays."""
    gross = config.gross_monthly()
    if not gross or not working_days:
        return None, None
    daily = gross / working_days
    return daily, daily / config.hours_per_day()


def basis(r, calib=None):
    """The minutes one day contributes, and on what footing.

    Net of breaks whenever breaks were recorded -- that is the employer's rule, and a
    span is always the larger number. Only a day with no break recorded falls back to
    its span, and only a GIT-DERIVED span is calibrated: the calibration factor exists
    to correct commit-derived estimates against measured ones. Applying it to the
    hand-kept sheet would inflate the user's own authoritative record by 18% and turn a
    real shortfall into an apparent surplus -- which is exactly what it did.
    """
    calib = config.calibration() if calib is None else calib
    if r["net_minutes"] is not None:
        # An unconfirmed gap is a GUESS about what the absence was. Deducting it is the
        # conservative choice -- an offline meeting is worked time, so the true figure
        # can only be higher -- but the result must not be labelled a settled net
        # figure. Calling both "net" is how an unclassified day would pass review.
        return r["net_minutes"], ("net?" if (r["unconfirmed"] or 0) else "net")
    span = r["span_minutes"] or 0
    prov = r["provenance"] or ""
    if "git" in prov:
        return round(span * calib), "span:calibrated"
    return span, "span"


def month_summary(conn, month, today=None):
    """Everything needed for the summary page of a submission.

    `net_minutes` is only ever summed over days that actually have a break recorded.
    Days without one are counted separately as `days_missing_breaks`, because the
    employer's rule is net of breaks and presenting a span as net would over-report.
    """
    today = today or date.today()
    rows = list(conn.execute(
        "SELECT * FROM v_day_worked WHERE attendance_day LIKE ? ORDER BY attendance_day",
        (month + "-%",)))
    target = sum(r["target_minutes"] for r in rows)
    working = [r for r in rows if r["target_minutes"] > 0]
    working_days = len(working)
    elapsed = [r for r in working if date.fromisoformat(r["attendance_day"]) < today]
    remaining = [r for r in working if date.fromisoformat(r["attendance_day"]) >= today]

    span_working = sum(r["span_minutes"] for r in working)
    span_other = sum(r["span_minutes"] for r in rows if r["target_minutes"] == 0)
    net_known = sum(r["net_minutes"] for r in working if r["net_minutes"] is not None)
    with_breaks = [r for r in working if r["deduction_minutes"] is not None]
    unconfirmed = [r for r in working if (r["unconfirmed"] or 0) > 0]
    missing_breaks = [r for r in working if r["deduction_minutes"] is None and r["span_minutes"] > 0]

    calib = config.calibration()

    def total(rs):
        return sum(basis(r, calib)[0] for r in rs)

    bases = sorted({basis(r, calib)[1] for r in working if r["span_minutes"]})
    worked_to_date = total(elapsed)
    worked_all = total(working)
    daily_rate, hourly_rate = _rates(working_days)
    hourly_rate_f = hourly_rate or 0.0
    per_day = config.hours_per_day() * 60

    # Three different questions, which must not share one label:
    #   shortfall_to_date  how far behind the days already gone
    #   still_needed       what the rest of the month must deliver to clear the target
    #   projected          where the month lands at a normal day's work from here
    span_cal = round(span_working * calib)
    shortfall_to_date = len(elapsed) * per_day - worked_to_date
    still_needed = target - worked_all
    projected = worked_all + len(remaining) * per_day
    projected_shortfall = target - projected

    provs = sorted({p for r in rows if r["provenance"] for p in r["provenance"].split(",")})
    return {
        "month": month,
        "today": today.isoformat(),
        "target_minutes": target,
        "working_days": working_days,
        "elapsed_working_days": len(elapsed),
        "remaining_working_days": len(remaining),
        "remaining_days": [r["attendance_day"] for r in remaining],
        "worked_minutes_to_date": worked_to_date,
        "worked_minutes": worked_all,
        "basis": "+".join(bases) or "none",
        "owed_to_date_minutes": len(elapsed) * per_day,
        "span_minutes": span_working,
        "span_minutes_calibrated": round(span_working * calib),
        "span_minutes_non_working": span_other,
        "calibration": calib,
        "net_minutes_known": net_known,
        "days_with_breaks": len(with_breaks),
        "days_unconfirmed_breaks": len(unconfirmed),
        "unconfirmed_break_days": [r["attendance_day"] for r in unconfirmed],
        "days_missing_breaks": len(missing_breaks),
        "shortfall_to_date_minutes": shortfall_to_date,
        "still_needed_minutes": still_needed,
        "still_needed_per_day_minutes": round(still_needed / len(remaining)) if remaining else None,
        "projected_minutes": projected,
        "projected_shortfall_minutes": projected_shortfall,
        "daily_rate": daily_rate,
        "hourly_rate": hourly_rate,
        "currency": config.currency(),
        # The figure that actually matters: what a normal day's work from here still
        # leaves on the table. Based on the CALIBRATED span, and on the span basis --
        # net of breaks will be worse, and cannot be computed until breaks are recorded.
        "money_projected": (projected_shortfall / 60.0) * hourly_rate_f if hourly_rate else None,
        "money_shortfall_to_date": (shortfall_to_date / 60.0) * hourly_rate_f if hourly_rate else None,
        "money_to_date": (shortfall_to_date / 60.0) * hourly_rate_f if hourly_rate else None,
        "provenance": provs,
        "ruleset": config.RULESET,
        "measured_days": sum(1 for r in rows if r["provenance"] == "live"),
        "reconstructed_days": sum(1 for r in rows if r["provenance"] and "backfill" in r["provenance"]),
    }


def day_rows(conn, month):
    return list(conn.execute(
        "SELECT * FROM v_day_worked WHERE attendance_day LIKE ? ORDER BY attendance_day",
        (month + "-%",)))


def input_digest(conn, month):
    """sha256 over every row a month's figure rests on.

    Frozen alongside a submission so that if derivation changes later, it is provable
    whether the number handed over was retro-fitted.

    Every table is covered, not just clock_event. The figure is
    span - deductions against a target, so a reclassified break or a day moved from
    working to holiday changes it just as surely as an event does -- and a digest that
    covered only events would report "inputs unchanged" beside a figure that had moved,
    which is worse than no digest at all.
    """
    h = hashlib.sha256()
    for sql in (
        "SELECT 'e', id, ts_unix, kind, attendance_day, provenance, ruleset, confidence"
        " FROM clock_event WHERE attendance_day LIKE ? ORDER BY id",
        "SELECT 'd', id, attendance_day, start_unix, end_unix, category, minutes,"
        " confirmed, provenance FROM deduction WHERE attendance_day LIKE ? ORDER BY id",
        "SELECT 'c', day, kind, leave_type, pay_affecting, target_minutes"
        " FROM day_class WHERE day LIKE ? ORDER BY day",
        # a day the user typed over in the vault (migrate.WORK_V6) moves the figure just as
        # surely as a session would
        "SELECT 'x', day, login_unix, logout_unix, off_minutes, salah, lunch, dinner,"
        " washroom, misc, call_personal, unsure FROM day_edit WHERE day LIKE ? ORDER BY day",
        # promoting the live clock changes every figure without touching a single row above,
        # so the flag itself is part of what a submission is pinned to (migrate.WORK_V3)
        "SELECT 'm', k, v FROM schema_meta WHERE k = 'live_counts' AND ? IS NOT NULL",
    ):
        for r in conn.execute(sql, (month + "-%",)):
            h.update(("|".join(str(x) for x in tuple(r)) + "\n").encode())
    return h.hexdigest()


def hhmm(minutes):
    if minutes is None:
        return ""
    sign = "-" if minutes < 0 else ""
    minutes = abs(int(round(minutes)))
    return f"{sign}{minutes // 60}h{minutes % 60:02d}m"


def clock(unix):
    return datetime.fromtimestamp(unix).strftime("%H:%M") if unix else ""
