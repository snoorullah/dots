"""Rollup: read sources into the DB for one 4am-logical day (part A: raw + aggregation)."""
from collections import defaultdict
from datetime import datetime, date, timedelta
from urllib.parse import urlparse
from . import db as dbmod, categorize
from .config import logical_date

BREAK_MIN_SECONDS = 180

def _parse(ts: str) -> datetime:
    """Parse ISO8601, tolerating AW's nanosecond precision (datetime handles ≤ microseconds)."""
    import re
    ts = re.sub(r"(\.\d{6})\d+", r"\1", ts.replace("Z", "+00:00"))
    return datetime.fromisoformat(ts)

def rollup_raw(db, day: date, tasks, intervals_, window_events, afk_events, logind, rules) -> None:
    dbmod.upsert(db, "tasks", tasks)
    dbmod.upsert(db, "intervals", [
        {"start": i["start"], "end": i.get("end"),
         "tags": i.get("tags", []),
         "project": (i.get("tags") or [None])[0],
         "description": (i.get("tags") or [None, None])[1] if len(i.get("tags") or []) > 1 else None}
        for i in intervals_
    ])
    dbmod.upsert(db, "sessions", [
        {"ts": e["ts"], "type": e.get("type"), "detail": e.get("detail")} for e in logind
    ])
    # aggregate window events → usage (date,category,app,hour → seconds)
    agg = defaultdict(float)
    for ev in window_events:
        d = ev.get("data", {})
        cat = categorize.categorize(d.get("app", ""), d.get("title", ""), rules=rules)
        hour = _parse(ev["timestamp"]).astimezone().hour
        agg[(str(day), cat, d.get("app", ""), hour)] += ev.get("duration", 0)
    # Replace the day's usage rows before inserting the freshly-aggregated ones.
    # `category` is part of usage's pk (date,category,app,hour), so an app that moves
    # categories (user edits categories.toml, e.g. Web -> Comms) would otherwise get a
    # NEW row under the new category while the OLD (date,"Web",app,hour) row is
    # orphaned — never deleted, and rollup_derived's cat_seconds then sums BOTH,
    # inflating daily_summary/note totals. The CLI always rolls up the complete
    # 4am->4am day, so replace-the-day is correct and idempotent.
    if "usage" in db.table_names():
        db["usage"].delete_where("date = ?", [str(day)])
    dbmod.upsert(db, "usage", [
        {"date": k[0], "category": k[1], "app": k[2], "hour": k[3], "seconds": round(v)}
        for k, v in agg.items()
    ])
    # afk spans ≥ threshold → auto breaks
    breaks = []
    for ev in afk_events:
        if ev.get("data", {}).get("status") == "afk" and ev.get("duration", 0) >= BREAK_MIN_SECONDS:
            breaks.append({"start": ev["timestamp"], "duration": round(ev["duration"]),
                           "source": "auto", "label": None})
    dbmod.upsert(db, "breaks", breaks)
    # persist afk spans to a local scratch table (NOT synced — sync.dump skips '_' tables) so
    # part B's reconciliation can read them. Idempotent on start.
    afk_rows = [{"start": ev["timestamp"],
                 "end": (_parse(ev["timestamp"]) + timedelta(seconds=ev.get("duration", 0))).isoformat(),
                 "status": ev.get("data", {}).get("status")}
                for ev in afk_events if ev.get("timestamp")]
    if afk_rows:
        db["_afk_raw"].upsert_all(afk_rows, pk="start")

def rollup_web(db, day: date, web_events, rules) -> None:
    """Aggregate aw-watcher-web events into (date, domain, hour) -> seconds, upserting `web`.
    Inert (no-op) when web_events is empty — callers guard this on a web bucket existing."""
    agg = defaultdict(float)
    cats = {}
    for ev in web_events:
        d = ev.get("data", {})
        url = d.get("url")
        if not url:
            continue                                       # guard missing/None url
        host = urlparse(url).hostname
        if not host:
            continue                                        # unparseable url -> no domain
        hour = _parse(ev["timestamp"]).astimezone().hour
        key = (str(day), host, hour)
        agg[key] += ev.get("duration", 0)
        cats[key] = categorize.categorize(app="", title="", domain=host, rules=rules)
    # Replace the day's web rows before inserting the fresh ones — same replace-the-day
    # approach as rollup_raw's usage aggregation above. web keys on domain (not
    # category) so upsert alone wouldn't orphan rows here, but doing the delete keeps
    # both paths consistent and the dump deterministic even when a source shrinks.
    if "web" in db.table_names():
        db["web"].delete_where("date = ?", [str(day)])
    dbmod.upsert(db, "web", [
        {"date": k[0], "domain": k[1], "hour": k[2], "seconds": round(v), "category": cats[k]}
        for k, v in agg.items()
    ])

# --- part B: derived (salah, reconciliation, daily_summary, adherence, streak) ---
from . import intervals as I

PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

def _rows(db, table):
    """Read a table's rows, or [] if it doesn't exist yet (partial days / tests)."""
    return db[table].rows if table in db.table_names() else []

def _afk_spans(db, want_status, ds):
    """not-afk/afk spans with the given status that STARTED on logical day `ds` (str).
    _afk_raw accumulates across every 30-min rollup with no pruning (pk=start), so
    without this day-scope filter a query on day N+1 would still see day N's rows."""
    return [(_parse(r["start"]), _parse(r["end"])) for r in _rows(db, "_afk_raw")
            if r["status"] == want_status and _logday(r["start"]) == ds]

def _iso(compact: str) -> str:  # 20260718T083000Z -> 2026-07-18T08:30:00+00:00
    return datetime.strptime(compact, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%S+00:00")

def _logday(ts: str) -> str:  # ISO ts -> its 4am-logical date string
    return str(logical_date(_parse(ts).astimezone().replace(tzinfo=None)))

def _iv_logday(compact_start: str):  # timew UTC compact start -> its 4am-local logical date
    return logical_date(_parse(_iso(compact_start)).astimezone().replace(tzinfo=None))

def _due_logday(due):
    """A task's `due` (taskwarrior compact-UTC, e.g. '20260718T080000Z') -> its 4am-local
    logical date, or None if missing/malformed — one bad `due` must not crash the rollup."""
    if not due:
        return None
    try:
        return _iv_logday(due)
    except (ValueError, TypeError):
        return None

def day_counts(row) -> bool:
    """A day 'counts' for streak/habit purposes: clocked in, all 5 salah logged
    (missed/qaza still counts — honesty logs the day), and >=1 task tracked."""
    return bool(row and row.get("clock_in_logged") and row.get("salah_logged") == 5
                and row.get("tasks_tracked", 0) >= 1)

def rollup_derived(db, day, rules) -> None:  # rules: unused in part B, kept for signature symmetry with rollup_raw
    ds = str(day)
    # salah from tasks (project 'salah', due on `day`). `due` is taskwarrior's compact-UTC
    # form ("20260718T080000Z"), so match via the same compact-UTC->4am-local conversion
    # the intervals use (_iv_logday/_due_logday), NOT a dashed-string .startswith check.
    salah = [{"date": ds, "prayer": t["description"], "status": t.get("salah_status"),
              "due": t.get("due"), "logged_at": t.get("modified")}
             for t in _rows(db, "tasks")
             if t.get("project") == "salah" and _due_logday(t.get("due")) == day]
    dbmod.upsert(db, "salah", salah)
    salah_logged = sum(1 for s in salah if s["status"])

    # intervals belonging to THIS logical day (convert UTC start -> local -> 4am boundary)
    day_ivs = [iv for iv in _rows(db, "intervals") if iv.get("start") and _iv_logday(iv["start"]) == day]
    ivspans = [(_parse(_iso(iv["start"])), _parse(_iso(iv["end"]))) for iv in day_ivs if iv.get("end")]
    interval_seconds = sum((e - s).total_seconds() for s, e in ivspans)

    cat_seconds = {}
    for u in _rows(db, "usage"):
        if u["date"] == ds:
            cat_seconds[u["category"]] = cat_seconds.get(u["category"], 0) + u["seconds"]

    day_sessions = [s for s in _rows(db, "sessions") if s.get("ts") and _logday(s["ts"]) == ds]
    clock_in = 1 if any(s.get("type") == "login" for s in day_sessions) else 0
    in_events = sorted((s for s in day_sessions if s.get("type") in ("login", "unlock")),
                        key=lambda s: _parse(s["ts"]))
    out_events = sorted((s for s in day_sessions if s.get("type") in ("logout", "lock")),
                         key=lambda s: _parse(s["ts"]))
    clock_in_time = _parse(in_events[0]["ts"]).astimezone().strftime("%H:%M") if in_events else None
    clock_out_time = _parse(out_events[-1]["ts"]).astimezone().strftime("%H:%M") if out_events else None

    day_breaks = [b for b in _rows(db, "breaks") if _logday(b["start"]) == ds]
    labeled = sum(1 for b in day_breaks if b.get("label"))

    # notafk/afk spans computed here (ahead of the adherence upsert below) because
    # coverage_pct needs active_untracked_seconds, which reconciliation also needs.
    notafk, afk = _afk_spans(db, "not-afk", ds), _afk_spans(db, "afk", ds)
    active_untracked_min = round(sum((e - s).total_seconds() for s, e in I.subtract(notafk, ivspans)) / 60)
    denom = interval_seconds + (active_untracked_min * 60)
    coverage_pct = round(100 * interval_seconds / denom) if denom else None

    dbmod.upsert(db, "daily_summary", [{
        "date": ds, "categories": cat_seconds, "tracked_seconds": sum(cat_seconds.values()),
        "breaks": len(day_breaks), "salah_logged": salah_logged}])
    dbmod.upsert(db, "adherence", [{
        "date": ds, "clock_in_logged": clock_in, "salah_logged": salah_logged,
        "breaks_labeled": labeled, "breaks_total": len(day_breaks), "tasks_tracked": len(day_ivs),
        "coverage_pct": coverage_pct, "clock_in": clock_in_time, "clock_out": clock_out_time}])

    present = [(min(s for s, _ in notafk), max(e for _, e in notafk))] if notafk else []
    dbmod.upsert(db, "reconciliation", [{
        "date": ds,
        "active_untracked_min": active_untracked_min,
        "task_afk_min": round(I.overlap(ivspans, afk) / 60),
        "present_idle_min": round(I.overlap(present, afk) / 60)}])

def streak(db, day) -> int:
    rows = {r["date"]: r for r in _rows(db, "adherence")}
    n, cur = 0, day
    while True:
        if day_counts(rows.get(str(cur))):
            n += 1; cur = cur - timedelta(days=1)
        else:
            return n
