"""activity.json: worked time per bucket (today / week / month / quarter).

Local only: work.db is opened read-only, timewarrior and ActivityWatch are asked for totals.
"""
import time
from datetime import datetime, timedelta

from . import local_tt, tw
from .heatmap import SPAN_DAYS

TOP = 8


def bucket_starts(today):
    """Local midnight starts for today / week (Monday) / month / quarter."""
    q = (today.month - 1) // 3 * 3 + 1
    return {"today": today, "week": today - timedelta(days=today.weekday()),
            "month": today.replace(day=1), "quarter": today.replace(month=q, day=1)}


def _titles(tasks):
    return {t["ref"]: t.get("desc", "") for t in tasks if t.get("ref")}


def build(done_tasks, tasks, now=None, apps="today"):
    """apps: "all" queries ActivityWatch for every bucket, "today" only for today (the rest from cache)."""
    now = int(now or time.time())
    today = datetime.fromtimestamp(now).date()
    titles = _titles(tasks + done_tasks)
    out = {}
    first = local_tt.day_start(bucket_starts(today)["quarter"])
    ints = local_tt.project_intervals(first, now)
    for name, start in bucket_starts(today).items():
        t0 = local_tt.day_start(start)
        refs = local_tt.ref_seconds(t0, now)[:TOP]
        out[name] = {
            "workedSec": local_tt.worked_sec(t0, now, now),
            "tasksDone": sum(1 for t in done_tasks if (t.get("end_ts") or 0) >= t0),
            "byProject": [{"project": p, "sec": s} for p, s in local_tt.project_seconds(ints, t0, now)[:TOP]],
            "byApp": [{"app": a, "sec": s} for a, s in local_tt.app_seconds(t0, now, now, cached_only=(apps != "all" and name != "today"))[:TOP]],
            "byRef": [{"ref": r, "sec": s, "title": titles.get(r, r)} for r, s in refs]}
    return {"v": 1, "ts": now, "buckets": out}


def completed(now=None, span=SPAN_DAYS):
    now = int(now or time.time())
    return tw.completed_since(now - (span + 1) * 86400)
