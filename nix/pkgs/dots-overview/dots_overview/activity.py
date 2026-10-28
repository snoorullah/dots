"""activity.json: worked time per bucket (today / week / month / quarter).

Local only: work.db and private.db are opened read-only (private.db for terminal and
browser attention: only task / project / agent labels are read), timewarrior and
ActivityWatch are asked for totals.
"""
import time
from datetime import datetime, timedelta

from . import local_tt, tw
from .heatmap import SPAN_DAYS

TOP = 8


def bucket_starts(today):
    """Start dates for today / week (Monday) / month / quarter; each begins at that day's first login."""
    q = (today.month - 1) // 3 * 3 + 1
    return {"today": today, "week": today - timedelta(days=today.weekday()),
            "month": today.replace(day=1), "quarter": today.replace(month=q, day=1)}


def _titles(tasks):
    return {t["ref"]: t.get("desc", "") for t in tasks if t.get("ref")}


def _maps(tasks):
    """{uuid: ref} and {uuid: project}: how a segment tied only to a task finds its ref."""
    ref = {t["uuid"]: t["ref"] for t in tasks if t.get("uuid") and t.get("ref")}
    proj = {t["uuid"]: t["project"] for t in tasks if t.get("uuid") and t.get("project")}
    return ref, proj


def build(done_tasks, tasks, now=None, apps="today"):
    """apps: "all" queries ActivityWatch for every bucket, "today" only for today (the rest from cache)."""
    now = int(now or time.time())
    today = local_tt.workday(now)
    titles = _titles(tasks + done_tasks)
    out = {}
    first = local_tt.workday_start(bucket_starts(today)["quarter"])
    ints = local_tt.project_intervals(first, now)
    uuid_ref, uuid_project = _maps(tasks + done_tasks)
    for name, start in bucket_starts(today).items():
        t0 = local_tt.workday_start(start)
        segs = local_tt.term_segments(t0, now)
        att_refs, att_projects, att_agents = local_tt.attention(
            segs, local_tt.web_links(t0, now), uuid_ref, uuid_project)
        refs = local_tt.merge_max(local_tt.ref_seconds(t0, now), att_refs)[:TOP]
        projects = local_tt.merge_max(local_tt.project_seconds(ints, t0, now), att_projects)[:TOP]
        by_app = [{"app": a, "sec": s} for a, s in local_tt.app_seconds(
            t0, now, now, cached_only=(apps != "all" and name != "today"))[:TOP]]
        detail = local_tt.term_detail(segs)
        for row in by_app:      # the terminal line reads as what the terminal time went on
            if detail and local_tt.TERMINAL_APP.match(row["app"]):
                row["detail"] = detail
        out[name] = {
            "workedSec": local_tt.worked_sec(t0, now, now),
            "tasksDone": sum(1 for t in done_tasks if (t.get("end_ts") or 0) >= t0),
            "byProject": [{"project": p, "sec": s} for p, s in projects],
            "byApp": by_app,
            "byAgent": [{"agent": a, "sec": s} for a, s in local_tt.ranked(att_agents)[:TOP]],
            "byRef": [{"ref": r, "sec": s, "title": titles.get(r, r)} for r, s in refs]}
    return {"v": 1, "ts": now, "buckets": out}


def completed(now=None, span=SPAN_DAYS):
    now = int(now or time.time())
    return tw.completed_since(now - (span + 1) * 86400)
