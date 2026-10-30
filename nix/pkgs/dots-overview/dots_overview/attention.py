"""attention.json: what needs me, ranked, with the health of every source.

Fast-cycle safe: it reads Taskwarrior (where the slow cycle already mirrored GitHub and
ERP), the herdr snapshot, dots-ops state and the notification log. No network.

amber = `waiting` (somebody is blocked on ME). red = `failed` (an alert and nobody waits).
Those are the only two counts the pill spends colour on.
"""
import time

from . import atomic, config, herdr, names, sources_notify, sources_ops, sync

URGENCY_RANK = {"critical": 0, "time": 1, "active": 2, "passive": 3}
CLAUDE_TTL = 24 * 3600
MAX_ITEMS = 30

KIND_OF = {"review": "review", "hd": "erp", "todo": "erp", "task": "erp", "issue": "task", "pr": "task"}
# An open ERP item is assigned work, not somebody blocked on me. Only these states are:
# a task past its due date, and a ticket the customer has replied on.
ERP_WAITS = {"task:overdue", "hd:replied"}


def _jump(t):
    if t.get("pane") or t.get("wspace") or t.get("sess"):
        return {"pane": t.get("pane"), "workspace": t.get("wspace"), "sess": t.get("sess")}
    return None


def from_tasks(tasks, now):
    items = []
    for t in tasks:
        tags = t.get("tags") or []
        if "attn" not in tags and not t.get("start_ts"):
            continue
        age = max(0, now - (t.get("entry_ts") or now))
        if t.get("src") == "claude":
            if age > CLAUDE_TTL and "alert" not in tags:
                continue
            kind, waiting, urgency = "task", False, "passive"
        else:
            sk = (t.get("srcstate") or "").partition(":")[0]
            kind = KIND_OF.get(sk, "task")
            ss = (t.get("srcstate") or "").lower()
            waiting = kind == "review" or (kind == "erp" and ss in ERP_WAITS)
            urgency = "active" if waiting else "passive"
        ref = t.get("ref")
        alert = "alert" in tags and t.get("src") == "claude"     # made by Create ticket (alertpr)
        if alert:
            kind, waiting, urgency = "alert", False, "active"
        items.append({
            "id": f"{kind}:{ref or t['uuid'][:8]}", "kind": kind, "title": (t.get("desc") or "")[:140],
            "ref": ref, "src": t.get("src"), "url": t.get("url"), "urgency": urgency, "waiting": waiting,
            "ageSec": age, "actor": t.get("agent"), "jump": _jump(t),
            "canBreakdown": bool(ref) and (alert or t.get("src") in ("gh", "erp")) and "sub" not in tags,
            "startedAt": t.get("start_ts")})
    return items


def from_herdr(live, now):
    items = []
    for a in live or []:
        if herdr.waiting(a["status"]):
            who = names.for_session(a.get("sess"))
            items.append({
                "id": f"blocker:{a['pane']}", "kind": "blocker", "title": f"{who} is waiting on you",
                "ref": None, "src": "herdr", "url": None, "urgency": "time", "waiting": True, "ageSec": 0,
                "actor": who, "jump": {"pane": a["pane"], "workspace": a.get("workspace"), "sess": a.get("sess")},
                "canBreakdown": False, "startedAt": None})
    return items


def build(tasks, live, now=None):
    now = int(now or time.time())
    ops_items, ops_src = sources_ops.read(now)
    dm_items, dm_src = sources_notify.read(now)
    items = from_herdr(live, now) + from_tasks(tasks, now) + dm_items + ops_items
    items.sort(key=lambda i: (not i["waiting"], URGENCY_RANK[i["urgency"]], i["ageSec"]))
    counts = {"waiting": sum(i["waiting"] for i in items),
              "failed": sum(1 for i in items if i["kind"] == "alert" and not i["waiting"]), "total": len(items)}
    items = items[:MAX_ITEMS]      # the list is capped; the counts above are not
    synced = sync.last_status()
    sources = {
        "gh": _aged(synced.get("gh"), now), "erp": _aged(synced.get("erp"), now) or {"state": "off", "ts": now, "detail": "ERP_MODE=off"},
        "notif": dm_src, "ops": ops_src,
        "herdr": {"state": "ok" if live is not None else "error", "ts": now, "detail": None if live is not None else "herdr unreachable"},
        "task": {"state": "ok", "ts": now, "detail": None},
        "mail": {"state": "unavailable", "ts": now, "detail": "no local mail store"},
    }
    inbox, inbox_src = inbox_counts(now)
    if inbox is not None:
        counts["inbox"] = inbox
        sources["mail"] = inbox_src
    sources["gh"] = sources["gh"] or {"state": "unavailable", "ts": now, "detail": "never synced"}
    return {"v": 1, "ts": now, "items": items, "counts": counts, "sources": sources}


STALE_SYNC = 3 * 3600


def inbox_counts(now):
    """(counts, source) from dots-inbox's inbox.json, or (None, None) when there is none.

    dots-inbox writes NUMBERS ONLY here because this file sits outside the encrypted mail
    store: no subject, sender or body can reach the dashboard. An old file is stale.
    """
    doc = atomic.read_json(config.STATE_DIR / "inbox.json", None)
    if not isinstance(doc, dict):
        return None, None
    counts = {k: v for k, v in doc.items()
              if k != "updated" and isinstance(v, int) and not isinstance(v, bool)}
    ts = int(doc.get("updated") or 0)
    state = "ok" if now - ts <= STALE_SYNC else "stale"
    return counts, {"state": state, "ts": ts, "detail": None if state == "ok" else "last mail sync over 3 h ago"}


def _aged(src, now):
    """A source last synced more than 3 h ago is stale however well it did at the time."""
    if not src:
        return None
    if src.get("state") == "ok" and now - int(src.get("ts") or 0) > STALE_SYNC:
        return dict(src, state="stale", detail="last sync over 3 h ago")
    return src
