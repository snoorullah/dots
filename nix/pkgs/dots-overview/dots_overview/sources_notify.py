"""Slack direct messages, seen as desktop notifications.

There is no Slack API call here and there never will be: a DM is something somebody already
told the desktop about. notifylog.py records the notification; this turns recent ones into
`kind:"dm"` attention items. A channel mention has "#" in its summary and is ignored, unless the channel matches
SLACK_ALERT_CHANNELS: then it is an alert (red, nobody waiting), whatever its wording.
"""
import hashlib
import re
import time

from . import config, notifylog

WINDOW = 4 * 3600
MAX_ITEMS = 5


CHANNEL_RE = re.compile(r"#([\w.-]+)|\bin ([\w.-]+)\s*$")


def channel_of(summary):
    m = CHANNEL_RE.search(summary)
    return (m.group(1) or m.group(2)) if m else None


def read(now=None, cfg=None):
    now = int(now or time.time())
    cfg = cfg or config.Work()
    path = config.STATE_DIR / "notifications.jsonl"
    rows = notifylog.tail(path, 300)
    if rows is None:
        return [], {"state": "unavailable", "ts": now, "detail": "notification log not running"}
    seen, items = set(), []
    for r in reversed(rows):
        if "slack" not in str(r.get("app", "")).lower():
            continue
        chan = channel_of(str(r.get("summary", "")))
        alert = bool(chan) and cfg.is_slack_alert(chan)
        if "#" in str(r.get("summary", "")) and not alert:
            continue
        age = now - int(r.get("ts") or 0)
        if age > WINDOW:
            break
        summary = str(r.get("summary") or "")[:100]
        if summary in seen:
            continue
        seen.add(summary)
        if sum(1 for i in items if (i["kind"] == "alert") == alert) >= MAX_ITEMS:
            continue
        h = hashlib.sha1(summary.encode()).hexdigest()[:10]
        items.append({
            "id": ("alert:slack:" if alert else "dm:") + h, "kind": "alert" if alert else "dm", "title": summary,
            "ref": None, "src": "alert" if alert else "slack", "url": None,
            "urgency": "critical" if alert else "active", "waiting": not alert, "ageSec": max(0, age),
            "actor": None, "jump": None, "canBreakdown": False, "startedAt": None})
    last = rows[-1].get("ts") if rows else None
    return items, {"state": "ok", "ts": int(last or now), "detail": None}
