"""The slow cycle's fetch half: GitHub + ERP -> mirror tasks + mirror.json.

Idempotency key is `ref`: `task ref.is:<REF> export` returns 0 or 1 task, so a second run
creates nothing. Personal repos are mirrored too but without the `+work` tag, which is
what keeps them out of the brief.
"""
import time

from . import atomic, config, sources_erp, sources_gh, tw

STATUS = "sync-status.json"
ATTN_KINDS = ("review", "hd", "todo", "task")     # items somebody is waiting on me for


def ensure(item, now):
    """Create the mirror task for `item` if it has none. Returns True when it created one."""
    if tw.by_ref(item["ref"]) is not None:
        return False
    tags = ["mirror"]
    if item.get("work"):
        tags.append("work")
    if item["kind"] in ATTN_KINDS:
        tags.append("attn")
    tw.add(item["title"], tags=tags, ref=item["ref"], src=item["src"], url=item.get("url"),
           srcstate=f"{item['kind']}:{item['state']}", srcsync=now)
    return True


def mirror_doc(now):
    """mirror.json from the tasks carrying a ref: open ones, plus those closed in the last 30 days."""
    rows = tw.export("+mirror", "status:pending") + tw.completed_since(now - 30 * 86400)
    refs, seen = [], set()
    for t in rows:
        ref = t.get("ref")
        if not ref or ref in seen or t.get("src") not in ("gh", "erp"):
            continue
        seen.add(ref)
        _, state = (t.get("srcstate") or "").partition(":")[0::2]
        closed = t.get("end_ts") if t.get("status") == "completed" else None
        refs.append({"ref": ref, "src": t["src"], "url": t.get("url"), "title": t.get("desc", ""),
                     "state": state or None, "updatedAt": t.get("srcsync_ts") or t.get("entry_ts"),
                     "taskUuid": t.get("uuid"), "closedAt": closed,
                     "reviewedAt": closed if state == "reviewed" else None})
    return {"v": 1, "ts": now, "refs": refs}


GONE_FLOOR = 0.5   # an open list under half the mirror is a bad read, not mass completion


def close_gone(got, now):
    """mcp mode has no per-item status read, so completion is: no longer in the open list.

    Read-only on the ERP side; marks done in local Taskwarrior only. A list that shrank by
    more than half is treated as a failed or truncated model answer, and closes nothing --
    unreachable or partial is never read as "done". Returns the count closed, or None.
    """
    fetched = {it["ref"] for it in got}
    pending = [t for t in tw.export("status:pending", "+mirror") if t.get("src") == "erp"]
    if not pending:
        return 0
    if len(fetched) < GONE_FLOOR * len(pending):
        return None
    n = 0
    for t in pending:
        if t.get("ref") and t["ref"] not in fetched:
            kind = (t.get("srcstate") or "erp:").split(":", 1)[0]
            tw.done(t["uuid"], srcstate=f"{kind}:gone", srcsync=now)
            n += 1
    return n


def run(cfg, erp_mcp=False, gh=sources_gh, erp=sources_erp, sleep=time.sleep, now=None):
    """Fetch, mirror, write. Returns (created count, per-source state, errors)."""
    now = int(now or time.time())
    status, errors, items = {}, [], []
    try:
        got = gh.fetch(cfg, sleep=sleep)
        items += got
        status["gh"] = {"state": "ok", "ts": now, "detail": f"{len(got)} item(s)"}
    except sources_gh.GhError as e:
        status["gh"] = {"state": "stale", "ts": now, "detail": str(e)[:80]}
        errors.append({"source": "gh", "msg": str(e)[:120]})
    st, detail = erp.state_for(cfg, erp_mcp)
    if st == "off":
        status["erp"] = {"state": "off", "ts": now, "detail": detail}
    else:
        try:
            got = erp.fetch_token(cfg) if cfg.erp_mode == "token" else erp.fetch_mcp(cfg)
            items += got
            status["erp"] = {"state": "ok", "ts": now, "detail": f"{len(got)} item(s)"}
            if cfg.erp_mode == "mcp":
                closed = close_gone(got, now)
                if closed is None:
                    status["erp"]["detail"] += "; open list looked partial, nothing closed"
                elif closed:
                    status["erp"]["detail"] += f"; {closed} closed upstream"
        except (sources_erp.ErpError, OSError) as e:
            status["erp"] = {"state": "stale", "ts": now, "detail": str(e)[:80]}
            errors.append({"source": "erp", "msg": str(e)[:120]})
    created = 0
    for it in items:
        try:
            created += ensure(it, now)
        except tw.TwError as e:
            errors.append({"source": "task", "msg": str(e)[:120]})
    atomic.write_json(config.STATE_DIR / STATUS, {"v": 1, "ts": now, "sources": status})
    return created, status, errors


def last_status():
    return (atomic.read_json(config.STATE_DIR / STATUS, {}) or {}).get("sources", {})
