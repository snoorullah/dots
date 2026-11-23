"""metrics.json: the numbers behind the control centre's Time tab.

Python computes everything, QML only draws (docs/shell/specs/cc-time-kpis.md). Every source is
read-only and optional: a missing file, table or tool OMITS its fields and says why in
`sources`. Nothing here writes to timetrack, ActivityWatch, Taskwarrior or git, and nothing
leaves the machine. Zone and project names are data from the user's own tables; none is
named in code.
"""
import bisect
import math
import os
import statistics
import time
from datetime import date, datetime, timedelta
from pathlib import Path

from . import atomic, config, local_tt, metrics_aw, metrics_src as src, report

VERSION = 1
KEEP_DAYS = 120          # days[] length
SPAN_DAYS = 200          # internal history: the quarter and the one before it
DEEP_MIN_SEC = 45 * 60
DEEP_GAP_SEC = 5 * 60
MAX_BREAK_WINDOW = 14

KPI_SUMS = ("workedMin", "targetMin", "focusMin", "deepWorkMin", "agentOnlyMin", "agentOnlyRawMin", "humanMin", "contextSwitches",
            "interruptions", "tasksDone", "prsMerged", "prsReviewed", "ticketsClosed", "commits", "screenSec")


def tz_name():
    v = os.environ.get("TZ")
    if v and not v.startswith(":"):
        return v
    for p in (Path("/etc/timezone"),):
        try:
            t = p.read_text().strip()
            if t:
                return t
        except OSError:
            pass
    try:
        t = os.path.realpath("/etc/localtime")
        if "zoneinfo/" in t:
            return t.split("zoneinfo/", 1)[1]
    except OSError:
        pass
    return time.tzname[0]


def _mid(day):
    d = date.fromisoformat(day)
    return local_tt.day_start(d)


def clean(v):
    """Drop None and NaN/inf everywhere: an omitted key means "no data"."""
    if isinstance(v, dict):
        out = {k: clean(x) for k, x in v.items()}
        return {k: x for k, x in out.items() if x is not None}
    if isinstance(v, list):
        return [clean(x) for x in v if x is not None]
    if isinstance(v, float):
        return None if math.isnan(v) or math.isinf(v) else v
    return v


def pct(a, b):
    return round(a * 100.0 / b, 1) if b and b > 0 else None


def slope(ys):
    """Least-squares slope of ys against 0..n-1, or None under two points."""
    n = len(ys)
    if n < 2:
        return None
    mx, my = (n - 1) / 2, sum(ys) / n
    den = sum((i - mx) ** 2 for i in range(n))
    return sum((i - mx) * (y - my) for i, y in enumerate(ys)) / den if den else None


def direction(sl, ys):
    mean = sum(ys) / len(ys)
    if sl is None:
        return None
    return "flat" if abs(sl) < 1e-9 or abs(sl) <= 0.01 * abs(mean) else ("up" if sl > 0 else "down")


# -- day attribution -----------------------------------------------------------------------

class DayOf:
    """Maps a timestamp to its work-session day: the latest login at or before it, while that
    day was still running; else the local date (a day is login to logout, not midnight)."""

    def __init__(self, rows, now):
        self.now = now
        self.logins = sorted((r["first_unix"], r["day"], r["last_unix"]) for r in rows if r.get("first_unix"))
        self.starts = [x[0] for x in self.logins]

    def __call__(self, ts):
        i = bisect.bisect_right(self.starts, ts) - 1
        if i >= 0:
            _, day, last = self.logins[i]
            latest = i == len(self.logins) - 1
            if ts <= (last or 0) + 3600 or (latest and ts <= self.now):
                return day
        return src.iso(ts)


# -- human / agent split ---------------------------------------------------------------------

AGENT_ONLY_CAP_MIN = 120        # owner rule: agent-only time is dashboard-only, at most 2 h a day
STALE_RUN_SEC = 86400


def union(iv):
    """Merge [(a, b)] into sorted disjoint intervals."""
    out = []
    for a, b in sorted(x for x in iv if x[1] > x[0]):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def subtract(iv, cut):
    """Disjoint intervals iv minus disjoint intervals cut."""
    out = []
    for a, b in iv:
        for c, d in cut:
            if d <= a or c >= b:
                continue
            if c > a:
                out.append((a, c))
            a = max(a, d)
            if a >= b:
                break
        if a < b:
            out.append((a, b))
    return out


def total(iv):
    return sum(b - a for a, b in iv)


def run_intervals(events, closed, now):
    """[(day, actor, ticket, start, end)] paired per session.

    run_stop rows carry no ticket and no slot, so a stop closes the oldest open run of its
    actor; a stop by 'system' (session end) closes every open run. A run still open at the
    end is closed at its session's close, else at now when it began within a day, else it is
    dropped (a run nobody closed for a day is a lost stop, not a day of work)."""
    out = []
    by_sid = {}
    for e in events:
        by_sid.setdefault(e["sid"], []).append(e)
    for sid, evs in by_sid.items():
        openr = {"human": [], "agent": []}
        for e in evs:
            if e["kind"] == "run_start" and e["actor"] in openr:
                openr[e["actor"]].append(e)
            elif e["kind"] == "run_stop":
                for actor in (openr if e["actor"] == "system" else [e["actor"]]):
                    q = openr.get(actor, [])
                    for s in (list(q) if e["actor"] == "system" else q[:1]):
                        q.remove(s)
                        out.append((s["day"], actor, s["ticket"], s["ts"], e["ts"]))
        end_sess = closed.get(sid)
        for actor, q in openr.items():
            for s in q:
                if end_sess is not None:
                    end = min(end_sess, now)
                elif now - s["ts"] <= STALE_RUN_SEC:
                    end = now
                else:
                    continue
                out.append((s["day"], actor, s["ticket"], s["ts"], end))
    return out


def split_by_day(events, closed, now):
    """{day: {human, agentOnly, agentRaw, tickets: {t: [human, agentOnly]}}} in minutes (agentOnly capped)."""
    by = {}
    for day, actor, tkt, a, b in run_intervals(events, closed, now):
        d = by.setdefault(day, {"human": [], "agent": [], "t": {}})
        d["human" if actor == "human" else "agent"].append((a, b))
        if tkt:
            d["t"].setdefault(tkt, {"human": [], "agent": []})["human" if actor == "human" else "agent"].append((a, b))
    out = {}
    for day, d in by.items():
        hu = union(d["human"])
        raw = total(subtract(union(d["agent"]), hu)) / 60
        tickets = {}
        for t, x in d["t"].items():
            h = round(total(union(x["human"])) / 60)
            ag = round(total(subtract(union(x["agent"]), hu)) / 60)
            if h or ag:
                tickets[t] = [h, ag]
        out[day] = {"human": round(total(hu) / 60), "agentRaw": round(raw),
                    "agentOnly": min(AGENT_ONLY_CAP_MIN, round(raw)), "tickets": tickets}
    return out


# -- per-day focus maths ---------------------------------------------------------------------

def deep_work_sec(spans):
    """Sum of runs on one ticket token, gaps under 5 min joined, each run at least 45 min."""
    tot, run = 0, None
    for s in sorted((s for s in spans if s["token"] and s["end"] > s["start"]), key=lambda s: s["start"]):
        if run and s["token"] == run[2] and s["start"] - run[1] < DEEP_GAP_SEC:
            run[1] = max(run[1], s["end"])
            continue
        if run and run[1] - run[0] >= DEEP_MIN_SEC:
            tot += run[1] - run[0]
        run = [s["start"], s["end"], s["token"]]
    if run and run[1] - run[0] >= DEEP_MIN_SEC:
        tot += run[1] - run[0]
    return tot


def switches(spans):
    n, prev = 0, None
    for s in sorted(spans, key=lambda s: s["start"]):
        if prev and (s["zone"] != prev["zone"] or s["token"] != prev["token"]):
            n += 1
        prev = s
    return n


# -- the build ---------------------------------------------------------------------------------

def build_days(ctx):
    """The per-day series, oldest first, every KPI input in one dict per day."""
    now, gaps = ctx["now"], ctx["gaps"]
    work, priv = ctx["work"], ctx["priv"]
    today = ctx["today"]
    first = (today - timedelta(days=SPAN_DAYS - 1)).isoformat()
    rows = src.day_rows(work, first, today.isoformat())
    if rows is None:
        gaps.add("timetrack", "no day_class: no days")
        return []
    ctx["rows"] = rows
    dayof = ctx["dayof"] = DayOf(rows, now)
    t0 = _mid(first) - 86400
    spans = src.focus_spans(priv, t0, now)
    brk = src.breaks(priv, first)
    tm = src.ticket_minutes(work, first)
    ev = src.run_events(work, first)
    split = split_by_day(ev[0], ev[1], now) if ev and ev[0] else {}
    split_since = min(e["day"] for e in ev[0]) if split else None
    sal = src.salah(priv, first, now)
    prm = src.prompts(priv, t0)
    log = src.logins(priv, first)
    ctx["logins"] = log
    done = src.tasks_completed(t0, gaps)
    refs = src.mirror_refs(gaps)

    by_day = {}
    for s in spans or []:
        by_day.setdefault(dayof(s["start"]), []).append(s)
    ctx["spans_by_day"] = by_day
    prompts_by_day = {}
    for ts in prm or []:
        prompts_by_day[dayof(ts)] = prompts_by_day.get(dayof(ts), 0) + 1
    done_by_day = {}
    for t in done or []:
        if t.get("end_ts"):
            d = dayof(t["end_ts"])
            done_by_day[d] = done_by_day.get(d, 0) + 1
    merged, reviewed, closed = {}, {}, {}
    ref_since = None
    for r in refs or []:
        pr = "/pull/" in (r.get("url") or "")
        if r.get("closedAt"):
            d = dayof(r["closedAt"])
            ref_since = min(ref_since or d, d)
            if pr and r.get("state") == "merged":
                merged[d] = merged.get(d, 0) + 1
            elif not pr and r.get("state") in ("closed", "done", "resolved"):
                closed[d] = closed.get(d, 0) + 1
        if r.get("reviewedAt"):
            d = dayof(r["reviewedAt"])
            ref_since = min(ref_since or d, d)
            reviewed[d] = reviewed.get(d, 0) + 1

    commits = None
    email, roots = ctx.get("email"), ctx.get("roots")
    if email and roots:
        commits = {}
        for ts in src.commit_times(roots, email, t0):
            d = dayof(ts)
            commits[d] = commits.get(d, 0) + 1
    elif rows:
        gaps.add("git", "no git identity or repositories")

    focus_since = dayof(min(s["start"] for s in spans)) if spans else None
    sal_since = min(sal) if sal else None
    prm_since = min([x for x in ((dayof(min(prm)) if prm else None), sal_since) if x], default=None)
    if not split and not tm:
        gaps.add("timetrack", "no human/agent split: clock_event has no runs and ticket_minutes is empty")

    out = []
    for r in rows:
        day = r["day"]
        d = {"day": day, "kind": r["kind"], "targetMin": r["target"]}
        span = r["span"] or 0
        worked = r["net"] if r["net"] is not None else r["span"]
        if worked is not None:          # no source row: omit, never invent a 0
            d["workedMin"] = worked
        if r["first_unix"]:
            d["spanMin"], d["loginTs"], d["logoutTs"] = span, r["first_unix"], r["last_unix"]
        if r["ded"] is not None:
            d["deductionMin"] = r["ded"]
        if brk and brk.get(day):
            d["breaks"] = brk[day]
        sp = by_day.get(day, [])
        if spans is not None and focus_since and day >= focus_since:
            d["focusMin"] = round(sum(s["end"] - s["start"] for s in sp if s["token"]) / 60)
            d["deepWorkMin"] = round(deep_work_sec(sp) / 60)
            d["contextSwitches"] = switches(sp)
            if sp and r["first_unix"]:
                d["timeToFirstFocusMin"] = max(0, round((sp[0]["start"] - r["first_unix"]) / 60))
        if split:
            if day >= split_since:      # a covered day with no runs really is 0
                x = split.get(day, {"human": 0, "agentOnly": 0, "agentRaw": 0, "tickets": {}})
                d["humanMin"], d["agentOnlyMin"], d["agentOnlyRawMin"] = x["human"], x["agentOnly"], x["agentRaw"]
                if x["tickets"]:
                    top = sorted(x["tickets"].items(), key=lambda kv: -sum(kv[1]))[:TOP_TICKETS]
                    d["tickets"] = [{"ticket": t, "humanMin": h, "agentOnlyMin": a} for t, (h, a) in top]
        elif tm and day in tm:
            d["humanMin"], d["agentOnlyMin"] = tm[day]
        if sal is not None and sal_since and day >= sal_since:
            ot, tot, _ = sal.get(day, (0, 0, 0))
            d["salahOnTime"], d["salahTotal"] = ot, tot
        if (prm is not None or sal is not None) and prm_since and day >= prm_since:
            nud = (sal or {}).get(day, (0, 0, 0))[2]
            d["interruptions"] = prompts_by_day.get(day, 0) + nud
        if done is not None:
            d["tasksDone"] = done_by_day.get(day, 0)
        if refs is not None and ref_since and day >= ref_since:
            d["prsMerged"], d["prsReviewed"], d["ticketsClosed"] = merged.get(day, 0), reviewed.get(day, 0), closed.get(day, 0)
        if commits is not None:
            d["commits"] = commits.get(day, 0)
        out.append(d)
    return out


def add_screen(ctx, days):
    """Screen time and top apps per day from ActivityWatch; the live window for today, cache for the past."""
    aw = ctx["aw"]
    today = ctx["today"].isoformat()
    for d in reversed(days):
        if not d.get("loginTs"):
            continue
        t0 = d["loginTs"]
        if d["day"] == today:
            t1 = max(ctx["now"], d.get("logoutTs") or 0)
            raw, st = aw.live(t0, t1)
            ctx["today_raw"] = (raw, t0, t1)
        else:
            t1 = d.get("logoutTs") or t0
            st = aw.past(d["day"], t0, t1) if t1 > t0 else None
        if st:
            d["screenSec"] = st["activeSec"]
            if st.get("topApps"):
                d["topApps"] = st["topApps"]
            d["_screen"] = st
    aw.prune((ctx["today"] - timedelta(days=SPAN_DAYS)).isoformat())


# -- periods -----------------------------------------------------------------------------------

def period_ranges(today):
    q = (today.month - 1) // 3 * 3 + 1
    starts = {"today": today, "week": today - timedelta(days=today.weekday()), "month": today.replace(day=1),
              "quarter": today.replace(month=q, day=1)}
    prev = {"today": (today - timedelta(days=1),) * 2}
    ws = starts["week"]
    n = (today - ws).days
    prev["week"] = (ws - timedelta(days=7), ws - timedelta(days=7) + timedelta(days=n))
    ms = starts["month"]
    pm_end = ms - timedelta(days=1)
    pm = pm_end.replace(day=1)
    prev["month"] = (pm, min(pm_end, pm + timedelta(days=(today - ms).days)))
    qs = starts["quarter"]
    pq_end = qs - timedelta(days=1)
    pq = date(pq_end.year, (pq_end.month - 1) // 3 * 3 + 1, 1)
    prev["quarter"] = (pq, min(pq_end, pq + (today - qs)))
    return {k: ((starts[k], today), prev[k]) for k in starts}


def window(days, a, b):
    lo, hi = a.isoformat(), b.isoformat()
    return [d for d in days if lo <= d["day"] <= hi]


def kpis(days, log, sal_present, att_skip=None):
    """{kpi: number} over a window of day dicts; a KPI with no input anywhere is absent.
    att_skip is a day left out of attainment: the unfinished one, so partial work is not
    divided by a full target."""
    out = {}
    for k in KPI_SUMS:
        vals = [d[k] for d in days if k in d]
        if vals:
            out[k] = sum(vals)
    both = [d for d in days if "workedMin" in d and d.get("targetMin") and d["day"] != att_skip]
    if both:
        out["attainmentPct"] = pct(sum(d["workedMin"] for d in both), sum(d["targetMin"] for d in both))
    ded = [d["deductionMin"] for d in days if "deductionMin" in d]
    if ded:
        out["breakMin"] = sum(ded)
    if days:
        if any("workedMin" in d for d in days):
            out["daysWorked"] = sum(1 for d in days if d.get("workedMin", 0) > 0)
    worked = [d for d in days if d.get("workedMin", 0) > 0]
    li = [(d["loginTs"] - _mid(d["day"])) / 60 for d in worked if d.get("loginTs")]
    lo = [(d["logoutTs"] - _mid(d["day"])) / 60 for d in worked if d.get("logoutTs")]
    if li:
        out["avgLoginMin"] = round(sum(li) / len(li))
    if lo:
        out["avgLogoutMin"] = round(sum(lo) / len(lo))
    ot, tot = sum(d.get("salahOnTime", 0) for d in days), sum(d.get("salahTotal", 0) for d in days)
    if any("salahTotal" in d for d in days) and tot:
        out["salahOnTimePct"] = pct(ot, tot)
    return out


def kpi_obj(value, prev):
    o = {"value": value}
    if prev is not None:
        o["prev"] = prev
        o["delta"] = round(value - prev, 1) if isinstance(value, float) or isinstance(prev, float) else value - prev
        if prev:
            o["deltaPct"] = round((value - prev) * 100.0 / abs(prev), 1)
    return o


def top_projects(term, a, b):
    lo, hi = a.isoformat(), b.isoformat()
    acc = {}
    for day, proj, sec, _ in term or []:
        if lo <= day <= hi:
            acc[proj] = acc.get(proj, 0) + sec
    top = sorted(((p, round(s / 60)) for p, s in acc.items() if round(s / 60) > 0), key=lambda kv: -kv[1])[:6]
    return [{"project": p, "min": m} for p, m in top]


TOP_TICKETS = 8


def top_tickets(days):
    """[{ticket, humanMin, agentOnlyMin}] summed over the window's days, busiest first, max 6."""
    acc = {}
    for d in days:
        for t in d.get("tickets", []):
            x = acc.setdefault(t["ticket"], [0, 0])
            x[0] += t["humanMin"]
            x[1] += t["agentOnlyMin"]
    rows = sorted(acc.items(), key=lambda kv: -sum(kv[1]))[:6]
    return [{"ticket": t, "humanMin": h, "agentOnlyMin": a} for t, (h, a) in rows]


def top_apps(days):
    acc = {}
    for d in days:
        for a in d.get("topApps", []):
            acc[a["app"]] = acc.get(a["app"], 0) + a["sec"]
    return [{"app": k, "sec": v} for k, v in sorted(acc.items(), key=lambda kv: -kv[1])[:6]]


def screen_cover(days):
    """(days with cached screen time, days that ought to have it) in a window."""
    have = [d for d in days if d.get("loginTs")]
    return sum(1 for d in have if "screenSec" in d), len(have)


def build_periods(ctx, days, term):
    out = {}
    today = ctx["today"]
    for name, ((a, b), (pa, pb)) in period_ranges(today).items():
        wc, wp = window(days, a, b), window(days, pa, pb)
        skip = name != "today"
        cur = kpis(wc, None, None, today.isoformat() if skip else None)
        prev = kpis(wp, None, None, pb.isoformat() if skip else None)
        p = {k: kpi_obj(v, prev.get(k)) for k, v in cur.items()}
        if "screenSec" in p:
            (hc, nc), (hp, np_) = screen_cover(wc), screen_cover(wp)
            p["screenSec"]["days"], p["screenSec"]["of"] = hc, nc
            if (hc, nc) != (hp, np_) or hc < nc or hp < np_:     # uneven coverage: a delta would lie
                p["screenSec"] = {k: v for k, v in p["screenSec"].items() if k not in ("prev", "delta", "deltaPct")}
        tt = top_tickets(wc)
        if tt:
            p["topTickets"] = tt
        tp = top_projects(term, a, b)
        if tp:
            p["topProjects"] = tp
        ta = top_apps(window(days, a, b))
        if ta:
            p["topApps"] = ta
        if p:
            out[name] = p
    return out


# -- improve ------------------------------------------------------------------------------------

def last_n(days, today, n):
    return window(days, today - timedelta(days=n - 1), today)


def finished(days, today):
    """Days that are over: today is still running and would read as a false dip."""
    return [d for d in days if d["day"] < today.isoformat()]


def trend(days, today, n):
    wd = [d for d in last_n(finished(days, today), today, n) if d["kind"] == "working" and d.get("workedMin", 0) > 0]
    series = {"workedMin": [d["workedMin"] for d in wd],
              "focusMin": [d["focusMin"] for d in wd if "focusMin" in d],
              "deepWorkRatioPct": [d["deepWorkMin"] * 100.0 / d["workedMin"] for d in wd if "deepWorkMin" in d]}
    out, dirs = {}, {}
    for k, ys in series.items():
        sl = slope(ys)
        if sl is not None:
            out[k] = round(sl, 2)
            dirs[k] = direction(sl, ys)
    if out:
        out["dir"] = dirs
    return out


def run_lengths(days, ok):
    """(current, best) run of consecutive finished working days where ok(day) is True.
    A day ok() cannot judge (None) ends a run, so a streak is never built on missing data."""
    best = cur = 0
    for d in days:
        v = ok(d)
        cur = cur + 1 if v else 0
        best = max(best, cur)
    return cur, best


def streaks(days, today, log):
    fin = [d for d in days if d["kind"] == "working" and d["day"] < today.isoformat()]
    if not fin:
        return None
    conds = {"targetMet": lambda d: None if "workedMin" not in d else (bool(d.get("targetMin")) and d["workedMin"] >= d["targetMin"]),
             "onTimeLogin": lambda d: None if d["day"] not in (log or {}) else (log[d["day"]] <= 0),
             "salahOnTime": lambda d: None if not d.get("salahTotal") else d["salahOnTime"] == d["salahTotal"]}
    cur, best = {}, {}
    for k, f in conds.items():
        if k == "onTimeLogin" and not log:
            continue
        if k == "salahOnTime" and not any(d.get("salahTotal") for d in fin):
            continue
        if k == "targetMet" and not any("workedMin" in d for d in fin):
            continue
        cur[k], best[k] = run_lengths(fin, f)
    if not cur:
        return None
    return dict(cur, best=best)


def build_improve(ctx, days, log):
    today = ctx["today"]
    out = {}
    for key, n in (("trend7", 7), ("trend30", 30)):
        t = trend(days, today, n)
        if t:
            out[key] = t
    s = streaks(days, today, log)
    if s:
        out["streaks"] = s
    pool = [d for d in last_n(finished(days, today), today, 30) if d["kind"] == "working" and d.get("workedMin", 0) > 0]
    if pool:
        b = max(pool, key=lambda d: d["workedMin"])
        w = min(pool, key=lambda d: d["workedMin"])
        out["bestDay"], out["worstDay"] = ({"day": x["day"], "workedMin": x["workedMin"]} for x in (b, w))
    target = ctx.get("loginTarget")
    if log:
        late = [v for dd, v in log.items() if dd >= (today - timedelta(days=29)).isoformat()]
        if late:
            p = {"avgLateMin": round(sum(late) / len(late), 1), "onTimeDays": sum(1 for v in late if v <= 0),
                 "days": len(late)}
            if target is not None:
                p["targetLoginMin"] = target
            out["punctuality"] = p
    ratio, iph, first = {}, {}, {}
    for key, n in (("d7", 7), ("d30", 30)):
        win = last_n(finished(days, today), today, n)
        dw = [(d["deepWorkMin"], d["workedMin"]) for d in win if "deepWorkMin" in d and d.get("workedMin", 0) > 0]
        if dw:
            ratio[key] = pct(sum(a for a, _ in dw), sum(b for _, b in dw))
        ip = [(d["interruptions"], d["workedMin"]) for d in win if "interruptions" in d and d.get("workedMin", 0) > 0]
        if ip:
            iph[key] = round(sum(a for a, _ in ip) / (sum(b for _, b in ip) / 60.0), 2)
        tf = [d["timeToFirstFocusMin"] for d in win if "timeToFirstFocusMin" in d]
        if tf:
            first[key] = statistics.median(tf)
    for k, v in (("deepWorkRatioPct", ratio), ("interruptionsPerHour", iph), ("timeToFirstFocusMin", first)):
        if v:
            out[k] = v
    return out


# -- zones --------------------------------------------------------------------------------------

def zone_list(acc):
    return [{"zone": z, "min": round(s / 60)} for z, s in sorted(acc.items(), key=lambda kv: -kv[1]) if round(s / 60) > 0]


def build_zones(ctx, term):
    out = {}
    cur = src.focus_now()
    if cur:
        out["current"] = cur
    spans = ctx.get("spans_by_day")
    today = ctx["today"]
    if spans is not None:
        by_day, by_week = {}, {}
        lo30 = (today - timedelta(days=29)).isoformat()
        wk0 = today - timedelta(days=today.weekday())
        lo12 = (wk0 - timedelta(weeks=11)).isoformat()
        for day, sp in spans.items():
            acc = {}
            for s in sp:
                z = s["zone"] or "unzoned"
                acc[z] = acc.get(z, 0) + max(0, s["end"] - s["start"])
            if day >= lo30 and day <= today.isoformat():
                zl = zone_list(acc)
                if zl:
                    by_day[day] = zl
            if day >= lo12 and day <= today.isoformat():
                monday = (date.fromisoformat(day) - timedelta(days=date.fromisoformat(day).weekday())).isoformat()
                w = by_week.setdefault(monday, {})
                for z, sec in acc.items():
                    w[z] = w.get(z, 0) + sec
        if by_day:
            out["byDay"] = dict(sorted(by_day.items()))
        weeks = [{"week": k, "zones": zone_list(v)} for k, v in sorted(by_week.items()) if zone_list(v)]
        if weeks:
            out["byWeek"] = weeks
    if term:
        lo = (today - timedelta(days=29)).isoformat()
        acc = {}
        for day, proj, sec, dele in term:
            if day >= lo:
                a = acc.setdefault(proj, [0, 0])
                a[0] += sec
                a[1] += dele
        pl = [{"project": p, "min": round(s / 60), "agentMin": round(a / 60)} for p, (s, a) in
              sorted(acc.items(), key=lambda kv: -kv[1][0]) if round(s / 60) > 0]
        if pl:
            out["projects"] = pl
    return out


# -- screen, health, reminders ------------------------------------------------------------------

def build_screen(ctx, days):
    today = ctx["today"]
    t = next((d for d in days if d["day"] == today.isoformat() and "_screen" in d), None)
    out = {}
    if t:
        st = t["_screen"]
        out["todayActiveSec"] = st["activeSec"]
        if "idleSec" in st:
            out["todayIdleSec"] = st["idleSec"]
        out["longestStretchMin"] = st["longestStretchMin"]
    wk = window([d for d in days if "_screen" in d], today - timedelta(days=today.weekday()), today)
    if wk:
        out["weekActiveSec"] = sum(d["_screen"]["activeSec"] for d in wk)
        out["lateNightSec"] = sum(d["_screen"]["lateNightSec"] for d in wk)
    raw = ctx.get("today_raw")
    if raw and raw[0]:
        sess = []
        for a, b in src.sessions_of(ctx["work"], today.isoformat()):
            e = b if b is not None else min(ctx["now"], a + local_tt.OPEN_CAP)
            sess.append({"openTs": a, "closeTs": b, "activeSec": metrics_aw.stats(raw[0], a, e)["activeSec"]})
        if sess:
            out["bySession"] = sess
    return out


def build_health(ctx):
    priv = ctx["priv"]
    today = ctx["today"]
    first = (today - timedelta(days=MAX_BREAK_WINDOW - 1)).isoformat()
    cps, doses = src.health(priv, first)
    out = {}
    if cps:
        out["checkpoints"] = [{k: v for k, v in (("day", c["day"]), ("slot", c["slot"]), ("score", c["score"]),
                                                 ("outcome", c["outcome"])) if v is not None} for c in cps]
        sc = [c["score"] for c in cps if c["score"] is not None and c["day"] >= (today - timedelta(days=6)).isoformat()]
        if sc:
            out["scoreAvg7"] = round(sum(sc) / len(sc), 2)
    if doses:
        out["doses"] = [{"day": x["day"], "ts": x["ts"]} for x in doses]
        gaps = []
        for day in {x["day"] for x in doses}:
            t0 = min(x["ts"] for x in doses if x["day"] == day)
            ans = [c["answered"] for c in cps or [] if c["day"] == day and c["slot"] != "dose" and c["answered"]
                   and c["answered"] >= t0]
            if ans:
                gaps.append((min(ans) - t0) / 60)
        if gaps:
            out["doseToFirstCheckpointMin"] = round(statistics.median(gaps))
    return out


def build_reminders(ctx, pending):
    cfg = config.Work()
    now = ctx["now"]
    out = {}

    from . import tw
    for key in ("due", "scheduled"):
        rows = []
        for t in pending or []:
            ts = tw._epoch(t.get(key)) if isinstance(t.get(key), str) else None
            if ts:
                r = {"id": t.get("id") or str(t.get("uuid", ""))[:8], "desc": report.scrub(t.get("desc", ""), cfg)[:120], key: ts}
                if key == "due":
                    r["overdue"] = ts < now
                rows.append((ts, r))
        if rows:
            out[key] = [r for _, r in sorted(rows, key=lambda x: x[0])[:10]]
    sal = ctx.get("salah_next")
    if sal:
        out["salahNext"] = sal
    return out


def salah_next(priv, today, now):
    rows = priv.rows("SELECT prayer, iqamah_unix FROM salah_log WHERE day = ? AND iqamah_unix > ?"
                     " AND enforcement != 'disabled' ORDER BY iqamah_unix LIMIT 1", (today.isoformat(), now), "salah_log")
    return {"prayer": rows[0]["prayer"], "iqamahTs": rows[0]["iqamah_unix"]} if rows else None


# -- sources ------------------------------------------------------------------------------------

def source_state(section, gaps, empty, names):
    """{state, reason} for one section from the gaps of the sources it reads."""
    why = [r for n in names for r in gaps.get(n)]
    if empty:
        return {"state": "missing", "reason": (why[0] if why else "nothing recorded yet")}
    if why:
        return {"state": "partial", "reason": "; ".join(why[:3])}
    return {"state": "ok", "reason": "all sources read"}


def safe(gaps, source, fn, default=None):
    try:
        return fn()
    except Exception as e:      # a bug in one section must not take the file down
        gaps.add(source, f"{type(e).__name__} while building")
        return default


def build(now=None, roots=None, email=None, use_git=True):
    now = int(now or time.time())
    gaps = src.Gaps()
    work, priv = src.Db("work.db", "timetrack", gaps), src.Db("private.db", "private", gaps)
    try:
        today = local_tt.workday(now)
        aw = metrics_aw.Aw(now)
        if use_git:
            email = email if email is not None else src.git_email()
            roots = roots if roots is not None else src.default_roots()
        ctx = {"now": now, "today": today, "gaps": gaps, "work": work, "priv": priv, "aw": aw,
               "email": email if use_git else None, "roots": roots if use_git else None}
        days = safe(gaps, "timetrack", lambda: build_days(ctx), [])
        safe(gaps, "aw", lambda: add_screen(ctx, days))
        if aw.down:
            gaps.add("aw", "ActivityWatch unreachable on localhost")
        elif aw.pending:
            gaps.add("aw", f"{aw.pending} past day(s) still being cached")
        term = src.term_days(priv, (today - timedelta(days=SPAN_DAYS)).isoformat())
        log = ctx.get("logins")
        ctx["loginTarget"] = safe(gaps, "timetrack", src.login_target_min)
        pending = src.tasks_pending(gaps)
        ctx["salah_next"] = safe(gaps, "private", lambda: salah_next(priv, today, now)) if priv.conn else None

        periods = safe(gaps, "timetrack", lambda: build_periods(ctx, days, term), {})
        improve = safe(gaps, "timetrack", lambda: build_improve(ctx, days, log), {})
        zones = safe(gaps, "private", lambda: build_zones(ctx, term), {})
        screen = safe(gaps, "aw", lambda: build_screen(ctx, days), {})
        health = safe(gaps, "private", lambda: build_health(ctx), {}) if priv.conn else {}
        reminders = safe(gaps, "taskwarrior", lambda: build_reminders(ctx, pending), {})
        series = [{k: v for k, v in d.items() if not k.startswith("_")} for d in days][-KEEP_DAYS:]

        sources = {
            "days": source_state("days", gaps, not series, ["timetrack", "private", "git", "taskwarrior", "mirror"]),
            "periods": source_state("periods", gaps, not periods, ["timetrack"]),
            "improve": source_state("improve", gaps, not improve, ["timetrack", "private"]),
            "zones": source_state("zones", gaps, not zones, ["private"]),
            "screen": source_state("screen", gaps, not screen, ["aw"]),
            "health": source_state("health", gaps, not health, ["private"]),
            "reminders": source_state("reminders", gaps, not reminders, ["taskwarrior"]),
            "aw": ({"state": "missing", "reason": "ActivityWatch unreachable on localhost"} if aw.down else
                   {"state": "partial" if aw.pending else "ok",
                    "reason": f"{aw.pending} past day(s) still being cached" if aw.pending else "read"}),
        }
        doc = {"v": VERSION, "ts": now, "tz": tz_name(), "today": today.isoformat(), "days": series,
               "periods": periods, "improve": improve, "zones": zones, "screen": screen, "health": health,
               "reminders": reminders, "sources": sources}
        doc = clean(doc)
        return {k: v for k, v in doc.items() if v not in ({}, []) or k in ("days", "sources")}
    finally:
        work.close()
        priv.close()


def write(doc=None, **kw):
    doc = doc if doc is not None else build(**kw)
    atomic.write_json(config.STATE_DIR / "metrics.json", doc, mode=0o600)
    return doc
