"""heatmap.json: one cell per day for the last 119 days (7 rows x 17 columns in the UI).

The `score` is computed HERE and nowhere else; the QML draws it exactly as given.
"""
import time
from datetime import datetime, timedelta

from . import local_tt

SPAN_DAYS = 119


def score(sec, max_sec):
    """0 for no work, then 1..4 by quarter of the busiest day in the span."""
    if sec <= 0 or max_sec <= 0:
        return 0
    return max(1, min(4, -(-sec * 4 // max_sec)))


def build(done_tasks, now=None, span=SPAN_DAYS):
    now = int(now or time.time())
    today = datetime.fromtimestamp(now).date()
    first = today - timedelta(days=span - 1)
    worked = local_tt.worked_by_day(first, today, now)
    done = {}
    for t in done_tasks:
        if t.get("end_ts"):
            d = datetime.fromtimestamp(t["end_ts"]).date()
            done[d] = done.get(d, 0) + 1
    mx = max(worked.values(), default=0)
    days = []
    d = first
    while d <= today:
        days.append({"d": d.isoformat(), "workedSec": worked.get(d, 0), "done": done.get(d, 0),
                     "score": score(worked.get(d, 0), mx)})
        d += timedelta(days=1)
    return {"v": 1, "ts": now, "spanDays": span, "maxSec": mx, "days": days}
