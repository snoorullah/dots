"""Invariants. A non-zero exit means "look at this"; the dots-ops job turns that into amber.

Checks what a quiet failure would otherwise hide: the tools exist, the state files are the
right shape and mode and not stale, and no `ref` is carried by two tasks.
"""
import shutil
import stat
import time

from . import atomic, config, herdr, tw

FILES = ("now", "activity", "attention", "heatmap", "mirror", "meta")
FAST_MAX_AGE = 5 * 60
SLOW_MAX_AGE = 3 * 3600


def check(now=None):
    """-> list of (level, message), level in ok / warn / fail."""
    now = int(now or time.time())
    out = []
    for tool in ("task", "herdr"):
        if shutil.which(tool):
            out.append(("ok", f"{tool} on PATH"))
        else:
            out.append(("fail", f"{tool} is not on PATH"))
    d = config.STATE_DIR
    if not d.is_dir():
        out.append(("fail", f"{d} does not exist; run `dots-overview fast` once"))
        return out
    if stat.S_IMODE(d.stat().st_mode) & 0o077:
        out.append(("warn", f"{d} is not mode 0700"))
    for name in FILES:
        p = d / f"{name}.json"
        j = atomic.read_json(p)
        if j is None:
            out.append(("fail", f"{name}.json is missing or not JSON"))
            continue
        if j.get("v") != 1:
            out.append(("fail", f"{name}.json has v={j.get('v')!r}, expected 1"))
        if stat.S_IMODE(p.stat().st_mode) != 0o600:
            out.append(("warn", f"{name}.json is not mode 0600"))
        age = now - int(j.get("ts") or j.get("generatedAt") or 0)
        limit = SLOW_MAX_AGE if name == "mirror" else FAST_MAX_AGE
        if age > limit:
            out.append(("warn", f"{name}.json is {age // 60} min old"))
    try:
        refs = [t["ref"] for t in tw.export("+mirror") if t.get("ref") and t.get("status") != "deleted"]
        dup = sorted({r for r in refs if refs.count(r) > 1})
        out.append(("fail", f"ref carried by two tasks: {', '.join(dup[:3])}") if dup else ("ok", "refs are unique"))
    except tw.TwError as e:
        out.append(("fail", f"taskwarrior: {e}"))
    live = herdr.snapshot()
    out.append(("ok", "herdr reachable") if live is not None else ("warn", "herdr did not answer"))
    return out


def summarize(results):
    """('ok'|'warn'|'fail', one-line summary) for ops_state."""
    bad = [m for lvl, m in results if lvl == "fail"]
    warn = [m for lvl, m in results if lvl == "warn"]
    if bad:
        return "fail", "; ".join(bad[:3])
    if warn:
        return "warn", "; ".join(warn[:3])
    return "ok", "invariants hold"
