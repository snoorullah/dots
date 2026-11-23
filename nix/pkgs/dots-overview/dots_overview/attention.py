"""attention.json: what needs me, ranked, with the health of every source.

Fast-cycle safe: it reads Taskwarrior (where the slow cycle already mirrored GitHub and
ERP), the herdr snapshot, dots-ops state and the notification log. No network.

amber = `waiting` (somebody is blocked on ME). red = `failed` (an alert and nobody waits).
Those are the only two counts the pill spends colour on.
"""
import time

from . import atomic, config, herdr, local_tt, names, nowstate, sources_notify, sources_ops, sync, untracked

URGENCY_RANK = {"critical": 0, "time": 1, "active": 2, "passive": 3}
CLAUDE_TTL = 24 * 3600
MAX_ITEMS = 30

KIND_OF = {"review": "review", "mention": "task", "hd": "erp", "todo": "erp", "task": "erp", "issue": "task", "pr": "task"}
# An open ERP item is assigned work, not somebody blocked on me. Only these states are:
# a task past its due date, and a ticket the customer has replied on.
ERP_WAITS = {"task:overdue", "hd:replied"}


def _jump(t):
    if t.get("pane") or t.get("wspace") or t.get("sess"):
        return {"pane": t.get("pane"), "workspace": t.get("wspace"), "sess": t.get("sess")}
    return None


def _rule(t, kind, m, login):
    """Apply the repo's ATTN_REPO_RULES mode. Returns (keep, previous)."""
    mode = m["mode"]
    if mode == "explicit":
        if not m.get("trust", True):       # no usable gh-meta: keep what is tagged rather than hide it all
            return True, False
        return bool(m["meta"].get("individual") or m["meta"].get("mention") or m["meta"].get("feedback")), False
    if kind != "review" or not login:
        return True, False
    upd = m["meta"].get("updatedTs")
    old = upd is not None and upd < login
    if mode == "new":
        return not old, False
    return True, mode == "split" and old


def from_tasks(tasks, now, cfg=None, meta=None, login=None, trust_meta=True, tickets=None):
    """Attention items from mirror tasks.

    `meta` is gh-meta.json's refs (GitHub's own times and who-asked flags, see sync.write_meta);
    `login` is today's session start. Both optional: without them the rules that need them pass.
    `trust_meta=False` (meta missing or stale) makes `explicit` repos pass attn-tagged items through.
    """
    cfg = cfg or config.Work()
    meta = meta or {}
    items = []
    for t in tasks:
        ref = t.get("ref")
        mode = cfg.attn_mode(ref)
        if mode == "block" or cfg.attn_below_min(ref):   # owner rules: blocked repo, or below its PR cutoff
            continue
        gm = meta.get(ref) or {}
        tags = t.get("tags") or []
        # an `explicit` repo can surface a PR of mine that got feedback: no attn tag was ever set for it
        if "attn" not in tags and not t.get("start_ts") and not (mode == "explicit" and gm.get("feedback")):
            continue
        sk = (t.get("srcstate") or "").partition(":")[0]
        previous = False
        if mode and t.get("src") == "gh":
            keep, previous = _rule(t, KIND_OF.get(sk, "task"), {"mode": mode, "meta": gm, "trust": trust_meta}, login)
            if not keep:
                continue
        age = max(0, now - (t.get("entry_ts") or now))
        if t.get("src") == "gh" and gm.get("updatedTs"):
            age = max(0, now - gm["updatedTs"])      # GitHub's time beats mirror creation
        if t.get("src") == "claude":
            if age > CLAUDE_TTL:
                continue
            kind, waiting, urgency = "task", False, "passive"
        else:
            kind = KIND_OF.get(sk, "task")
            ss = (t.get("srcstate") or "").lower()
            waiting = kind == "review" or (kind == "erp" and ss in ERP_WAITS)
            urgency = "active" if waiting else "passive"
        if previous:        # shown in its own list, never counted and never on the bar
            waiting, urgency = False, "passive"
        items.append({
            "id": f"{kind}:{ref or t['uuid'][:8]}", "kind": kind, "title": (t.get("desc") or "")[:140],
            "ref": ref, "ticket": nowstate.ticket_for(t, tickets), "src": t.get("src"), "url": t.get("url"),
            "urgency": urgency, "waiting": waiting,
            "ageSec": age, "actor": t.get("agent"), "jump": _jump(t),
            "canBreakdown": bool(ref) and t.get("src") in ("gh", "erp") and "sub" not in tags,
            "startedAt": t.get("start_ts"), "section": "previous" if previous else "main"})
    return items


def from_herdr(live, now):
    items = []
    for a in live or []:
        if herdr.waiting(a["status"], a.get("sub")):
            who = a.get("name") or names.for_session(a.get("sess"))
            items.append({
                "id": f"blocker:{a['pane']}", "kind": "blocker", "title": f"{who} needs you",
                "ref": a.get("ticket") or None, "src": "herdr", "url": None, "urgency": "time", "waiting": True, "ageSec": 0,
                "actor": who, "jump": {"pane": a["pane"], "workspace": a.get("workspace"), "sess": a.get("sess")},
                "canBreakdown": False, "startedAt": None, "section": "main"})
    return items


def mail_items(counts, now):
    """One numbers-only item per mail state that wants me. dots-inbox exports no subject, sender or
    body outside the encrypted store, so nothing more specific can exist here."""
    out = []
    for key, waiting, one, many in (("waiting_me", True, "1 mail waiting on you", "{n} mails waiting on you"),
                                    ("replied", False, "1 reply to your mail", "{n} replies to your mail")):
        n = int((counts or {}).get(key) or 0)
        if n > 0:
            out.append({"id": f"mail:{key}", "kind": "mail", "title": one if n == 1 else many.format(n=n),
                        "ref": None, "src": "mail", "url": None, "urgency": "active", "waiting": waiting,
                        "ageSec": 0, "actor": None, "jump": None, "canBreakdown": False, "startedAt": None,
                        "section": "main"})
    return out


def build(tasks, live, now=None):
    now = int(now or time.time())
    cfg = config.Work()
    ops_items, ops_src = sources_ops.read(now)
    dm_items, dm_src = sources_notify.read(now, cfg)
    inbox, inbox_src = inbox_counts(now)
    synced = sync.last_status()
    meta_doc = atomic.read_json(config.STATE_DIR / sync.META, None)
    meta = (meta_doc or {}).get("refs") or {} if isinstance(meta_doc, dict) else {}
    trust = meta_trusted(meta_doc, synced.get("gh"), now)
    try:
        login = local_tt.login_ts()
    except Exception:       # noqa: BLE001 -- no timetrack: the rules that need the session start pass through
        login = None
    try:
        un_items = untracked.items(now)
    except Exception:       # noqa: BLE001 -- a hint, never the reason attention.json is not written
        un_items = []
    items = (from_herdr(live, now) + from_tasks(tasks, now, cfg, meta, login, trust, nowstate.load_ticket_map()) + dm_items + ops_items + un_items
             + mail_items(inbox if inbox_src and inbox_src["state"] == "ok" else None, now))
    for i in items:
        i.setdefault("section", "main")
    items.sort(key=lambda i: (not i["waiting"], URGENCY_RANK[i["urgency"]], i["ageSec"]))
    counts = {"waiting": sum(i["waiting"] for i in items), "previous": sum(i["section"] == "previous" for i in items),
              "failed": sum(1 for i in items if i["kind"] == "alert" and not i["waiting"]),
              "total": sum(i["section"] != "previous" for i in items)}
    items = items[:MAX_ITEMS]      # the list is capped; the counts above are not
    sources = {
        "gh": _aged(synced.get("gh"), now), "erp": _aged(synced.get("erp"), now) or {"state": "off", "ts": now, "detail": "ERP_MODE=off"},
        "notif": dm_src, "ops": ops_src,
        "herdr": {"state": "ok" if live is not None else "error", "ts": now, "detail": None if live is not None else "herdr unreachable"},
        "task": {"state": "ok", "ts": now, "detail": None},
        "mail": {"state": "unavailable", "ts": now, "detail": "no local mail store"},
    }
    if inbox is not None:
        counts["inbox"] = inbox
        sources["mail"] = inbox_src
    sources["gh"] = sources["gh"] or {"state": "unavailable", "ts": now, "detail": "never synced"}
    return {"v": 1, "ts": now, "items": items, "counts": counts, "sources": sources}


STALE_SYNC = 3 * 3600


def meta_trusted(doc, gh_status, now):
    """True when gh-meta.json can decide `explicit` repos: it exists, is recent, and the last gh sync was ok."""
    if not isinstance(doc, dict) or not isinstance(doc.get("refs"), dict):
        return False
    if now - int(doc.get("ts") or 0) > STALE_SYNC:
        return False
    return bool(gh_status) and gh_status.get("state") == "ok"


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
