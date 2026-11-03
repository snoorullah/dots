"""What a break was, for the user's own reading (private.db away_label, migrate PRIVATE_V8).

Display only. The deduction (category, minutes, provenance) is the fact and is never read
back from here; a missing or unreadable label simply shows the category as before.
"""
import sys

from . import dbs


def record(start, end, day, key, label, source):
    """Best effort: a label that cannot be written must never undo an answered gap."""
    try:
        with dbs.open_private() as conn:
            conn.execute("INSERT OR REPLACE INTO away_label(start_unix, end_unix, day, key, label,"
                         " source) VALUES(?,?,?,?,?,?)", (start, end, day, key, label, source))
            conn.commit()
    except Exception as e:
        print(f"breaklabel: not recorded: {e}", file=sys.stderr)
        return False
    return True


def by_start(where="", args=()):
    """{start_unix: label} for the rows matching `where`; empty when there is no table."""
    try:
        with dbs.open_private(readonly=True) as conn:
            return {r["start_unix"]: r["label"] for r in conn.execute(
                "SELECT start_unix, label FROM away_label " + where, args)}
    except Exception:
        return {}


def for_day(day):
    return by_start("WHERE day = ?", (day,))


def minutes(where, args=()):
    """[(label or category, minutes)], largest first (ties by name, so output is stable)."""
    labels = by_start()
    tot = {}
    with dbs.open_work(readonly=True) as conn:
        for r in conn.execute("SELECT start_unix, category, minutes, confirmed FROM deduction"
                              " WHERE end_unix IS NOT NULL AND " + where, args):
            k = (r["confirmed"] and labels.get(r["start_unix"])) or r["category"]
            tot[k] = tot.get(k, 0) + (r["minutes"] or 0)
    return sorted(tot.items(), key=lambda kv: (-kv[1], kv[0]))


def cmd(a):
    from datetime import date
    if a.month:
        where, args, title = "attendance_day LIKE ?", (a.month + "-%",), a.month
    else:
        day = a.day or date.today().isoformat()
        where, args, title = "attendance_day = ?", (day,), day
    rows = minutes(where, args)
    print(f"Breaks {title}")
    for k, m in rows:
        h, mm = divmod(int(round(m)), 60)
        print(f"  {k:<28} {h}:{mm:02d}")
    if not rows:
        print("  none recorded")
    return 0
