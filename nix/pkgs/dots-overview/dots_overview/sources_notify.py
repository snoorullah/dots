"""Slack direct messages, seen as desktop notifications.

There is no Slack API call here and there never will be: a DM is something somebody already
told the desktop about. notifylog.py records the notification; this turns recent ones into
`kind:"dm"` attention items. A channel mention has "#" in its summary and is ignored.
"""
import hashlib
import time

from . import config, notifylog

WINDOW = 4 * 3600
MAX_ITEMS = 5


def read(now=None):
    now = int(now or time.time())
    path = config.STATE_DIR / "notifications.jsonl"
    rows = notifylog.tail(path, 300)
    if rows is None:
        return [], {"state": "unavailable", "ts": now, "detail": "notification log not running"}
    seen, items = set(), []
    for r in reversed(rows):
        if "slack" not in str(r.get("app", "")).lower() or "#" in str(r.get("summary", "")):
            continue
        age = now - int(r.get("ts") or 0)
        if age > WINDOW:
            break
        summary = str(r.get("summary") or "")[:100]
        if summary in seen:
            continue
        seen.add(summary)
        items.append({
            "id": "dm:" + hashlib.sha1(summary.encode()).hexdigest()[:10], "kind": "dm", "title": summary,
            "ref": None, "src": "notif", "url": None, "urgency": "active", "waiting": True, "ageSec": max(0, age),
            "actor": None, "jump": None, "canBreakdown": False, "startedAt": None})
        if len(items) >= MAX_ITEMS:
            break
    last = rows[-1].get("ts") if rows else None
    return items, {"state": "ok", "ts": int(last or now), "detail": None}
