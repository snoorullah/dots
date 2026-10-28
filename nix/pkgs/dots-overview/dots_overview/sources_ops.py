"""dots-ops job statuses, read from the same state files `dots-ops waybar` reads.

Never shells a `dots-ops` subcommand: those can act. Reading the JSON is enough to know
which job failed.
"""
import json
import time

from . import config


def read(now=None):
    """(items, source) where each item is an alert for a job in warn/fail."""
    now = int(now or time.time())
    d = config.OPS_STATE
    if not d.is_dir():
        return [], {"state": "unavailable", "ts": now, "detail": "no dots-ops state directory"}
    items = []
    for f in sorted(d.glob("*.json")):
        try:
            j = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        st = j.get("status")
        # only a FAILED job is red; a warning is the dots-ops module's own amber, not an alert here
        if st != "fail":
            continue
        job = str(j.get("job") or f.stem)
        changed = int(j.get("changed") or now)
        items.append({
            "id": f"alert:ops:{job}", "kind": "alert", "title": f"{job}: {str(j.get('summary') or st)[:100]}",
            "ref": None, "src": "ops", "url": None,
            "urgency": "critical", "waiting": False,
            "ageSec": max(0, now - changed), "actor": None, "jump": None, "canBreakdown": False, "startedAt": None})
    return items, {"state": "ok", "ts": now, "detail": f"{len(items)} job(s) failed" if items else None}
