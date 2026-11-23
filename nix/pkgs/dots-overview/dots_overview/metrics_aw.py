"""ActivityWatch screen time for metrics.py: loopback only, read-only, cached per past day.

A past day never changes, so its stats are written once to STATE_DIR/metrics-cache/ and read
back for free. Only a few uncached days are fetched per run (BUDGET_DAYS, BUDGET_SEC), newest
first, so a cold start fills in over a few cycles instead of blowing the time budget.
"""
import bisect
import time
import urllib.parse
from datetime import datetime, timedelta

from . import atomic, config, local_tt

BUDGET_DAYS = 12
BUDGET_SEC = 1.2
GAP_JOIN = 120           # two not-afk spans closer than this are one stretch
NIGHT = (22, 5)          # local hours: late-night screen time is 22:00 to 05:00


def merge(spans, gap=0):
    out = []
    for a, b in sorted(s for s in spans if s[1] > s[0]):
        if out and a <= out[-1][1] + gap:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def clip(spans, t0, t1):
    return [[max(a, t0), min(b, t1)] for a, b in spans if min(b, t1) > max(a, t0)]


def total(spans):
    return sum(b - a for a, b in spans)


def overlap(a, b, spans, starts):
    """Seconds of [a, b) inside the merged `spans` (`starts` is their start list, for bisect)."""
    i = max(0, bisect.bisect_right(starts, a) - 1)
    s = 0.0
    while i < len(spans) and spans[i][0] < b:
        s += max(0.0, min(b, spans[i][1]) - max(a, spans[i][0]))
        i += 1
    return s


def night_spans(t0, t1):
    """The 22:00-05:00 local windows touching [t0, t1]."""
    out = []
    d = datetime.fromtimestamp(t0).date() - timedelta(days=1)
    end = datetime.fromtimestamp(t1).date()
    while d <= end:
        a = datetime(d.year, d.month, d.day, NIGHT[0]).timestamp()
        b = datetime(d.year, d.month, d.day, NIGHT[1]).timestamp() + 86400
        out.append([a, b])
        d += timedelta(days=1)
    return out


def stats(raw, t0, t1):
    """Screen stats of window [t0, t1) from raw {notafk, afk, win}."""
    here = merge(clip(raw["notafk"], t0, t1))
    starts = [s[0] for s in here]
    apps = {}
    for a, b, app in raw["win"]:
        sec = overlap(max(a, t0), min(b, t1), here, starts) if raw["has_afk"] else max(0.0, min(b, t1) - max(a, t0))
        if sec > 0:
            apps[app] = apps.get(app, 0) + sec
    top = sorted(((k, int(v)) for k, v in apps.items() if int(v) > 0), key=lambda kv: -kv[1])[:5]
    stretches = merge(here, GAP_JOIN)
    out = {"activeSec": int(total(here)),
           "lateNightSec": int(sum(overlap(a, b, here, starts) for a, b in night_spans(t0, t1))),
           "longestStretchMin": int(max((b - a for a, b in stretches), default=0) // 60)}
    if raw["has_afk"]:
        out["idleSec"] = int(total(merge(clip(raw["afk"], t0, t1))))
    if top:
        out["topApps"] = [{"app": k, "sec": v} for k, v in top]
    return out


class Aw:
    def __init__(self, now):
        self.now = now
        self.down = False
        self._buckets = None
        self.fetched = 0
        self.started = time.monotonic()
        self.pending = 0
        self.dir = config.STATE_DIR / "metrics-cache"

    def _names(self):
        if self._buckets is None:
            b = local_tt._aw("/buckets/", timeout=2)
            self._buckets = (next((n for n, m in b.items() if m.get("type") == "currentwindow"), None),
                             next((n for n, m in b.items() if m.get("type") == "afkstatus"), None))
        return self._buckets

    def raw(self, t0, t1, past=True):
        """{notafk, afk, win, has_afk} of [t0, t1), or None when ActivityWatch is unreachable."""
        if self.down:
            return None
        try:
            win, afk = self._names()
            q = urllib.parse.urlencode({"start": datetime.fromtimestamp(t0).astimezone().isoformat(),
                                        "end": datetime.fromtimestamp(t1).astimezone().isoformat(), "limit": 100000})
            quote = urllib.parse.quote
            win_ev = local_tt._aw(f"/buckets/{quote(win)}/events?{q}", timeout=8) if win else []
            afk_ev = local_tt._aw(f"/buckets/{quote(afk)}/events?{q}", timeout=8) if afk else []
        except (OSError, ValueError):
            self.down = True
            return None
        if not win and not afk:
            return None

        def span(e):
            a = local_tt._aw_ts(e)
            return [a, a + float(e.get("duration") or 0)]

        notafk = [span(e) for e in afk_ev if (e.get("data") or {}).get("status") == "not-afk"]
        away = [span(e) for e in afk_ev if (e.get("data") or {}).get("status") == "afk"]
        wins = [(*span(e), (e.get("data") or {}).get("app")) for e in win_ev if (e.get("data") or {}).get("app")]
        self.fetched += 1 if past else 0       # today's window is not charged to the past-days budget
        return {"notafk": merge(notafk), "afk": merge(away), "win": wins, "has_afk": bool(afk)}

    def live(self, t0, t1):
        """(raw, stats) for a window that is still open (today); never cached."""
        raw = self.raw(t0, t1, past=False)
        return (raw, stats(raw, t0, t1)) if raw else (None, None)

    def past(self, day, t0, t1):
        """Cached stats of a finished day, or None. Fetches only while the per-run budget lasts."""
        path = self.dir / f"aw-{day}.json"
        hit = atomic.read_json(path)
        if isinstance(hit, dict) and hit.get("t0") == t0 and hit.get("t1") == t1 and isinstance(hit.get("s"), dict):
            return hit["s"]
        if self.down:
            return None
        if self.fetched >= BUDGET_DAYS or time.monotonic() - self.started > BUDGET_SEC:
            self.pending += 1
            return None
        raw = self.raw(t0, t1)
        if raw is None:
            return None
        s = stats(raw, t0, t1)
        try:
            atomic.write_json(path, {"t0": t0, "t1": t1, "s": s})
        except OSError:
            pass
        return s

    def prune(self, keep_from):
        try:
            for p in self.dir.glob("aw-*.json"):
                if p.stem[3:] < keep_from:
                    p.unlink()
        except OSError:
            pass
