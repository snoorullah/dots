#!/usr/bin/env python3
"""Writes the metrics fixtures for the Time tab (tests/cc-ui.sh), neutral made-up data only.

usage: mkmetrics.py   (rewrites tst/fixtures/metrics, metrics-partial, metrics-empty)

Each fixture is a full state dir: the board's six files plus metrics.json (v 1, the shape in
docs/shell/specs/cc-time-kpis.md). `metrics` has every section, `metrics-partial` has no
ActivityWatch and no private log (screen, health, zones and reminders omitted, as the spec says a
missing source must be), `metrics-empty` is a valid file whose sections are all missing.
"""
import json
import os
import random
import shutil
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
BOARD = os.path.join(FIX, "board")
TODAY = date(2025, 10, 30)  # a Thursday, so the week has four real bars
TS = int(datetime(2025, 10, 30, 17, 40, tzinfo=timezone.utc).timestamp())
ZONES = ["Platform", "Reviews", "Planning", "Docs", "Ops"]
PROJECTS = ["alpha-api", "beta-ui", "gamma-ops", "delta-docs", "epsilon-lab"]
APPS = ["terminal", "browser", "editor", "chat", "mail"]
BREAKS = ["walk", "salah", "lunch", "call"]


def unix(d, minutes):
    return int(datetime(d.year, d.month, d.day, tzinfo=timezone.utc).timestamp()) + int(minutes) * 60


def make_days(rnd):
    days = []
    for i in range(119, -1, -1):
        d = TODAY - timedelta(days=i)
        row = {"day": d.isoformat(), "kind": "working", "targetMin": 480}
        if d.weekday() >= 5:
            row.update(kind="weekend", targetMin=0, workedMin=0, spanMin=0, deductionMin=0, focusMin=0, deepWorkMin=0)
            days.append(row)
            continue
        if d.isoformat() in ("2025-09-15", "2025-10-02"):
            row.update(kind="holiday", targetMin=0, workedMin=0, spanMin=0, deductionMin=0, focusMin=0, deepWorkMin=0)
            days.append(row)
            continue
        if d.isoformat() in ("2025-08-21", "2025-08-22"):
            row.update(kind="leave_paid", targetMin=0, workedMin=0, spanMin=0, deductionMin=0, focusMin=0, deepWorkMin=0)
            days.append(row)
            continue
        trend = (119 - i) / 119.0
        login = int(515 + rnd.randint(-35, 55) - trend * 12)
        worked = int(rnd.gauss(430 + 40 * trend, 55))
        worked = max(150, min(560, worked))
        br = {}
        for name in rnd.sample(BREAKS, rnd.randint(2, 3)):
            br[name] = rnd.choice([10, 15, 20, 30, 45]) if name == "lunch" else rnd.choice([5, 9, 12, 15, 20])
        ded = sum(br.values())
        focus = int(worked * rnd.uniform(0.5, 0.78))
        deep = int(focus * rnd.uniform(0.25, 0.6))
        agent = int(worked * rnd.uniform(0.15, 0.4))
        total_salah = 5
        on_time = rnd.choice([3, 4, 4, 5, 5])
        screen = int((worked + ded) * 60 * rnd.uniform(0.9, 1.15))
        row.update(
            workedMin=worked, spanMin=worked + ded, deductionMin=ded, loginTs=unix(d, login), logoutTs=unix(d, login + worked + ded),
            breaks=br, focusMin=focus, deepWorkMin=deep, agentOnlyMin=agent, humanMin=max(0, worked - agent),
            salahOnTime=on_time, salahTotal=total_salah, contextSwitches=rnd.randint(18, 70), interruptions=rnd.randint(2, 18),
            tasksDone=rnd.randint(0, 6), prsMerged=rnd.randint(0, 3), prsReviewed=rnd.randint(0, 4), ticketsClosed=rnd.randint(0, 3),
            commits=rnd.randint(0, 14), screenSec=screen,
            topApps=[{"app": a, "sec": int(screen * w)} for a, w in zip(rnd.sample(APPS, 4), (0.4, 0.25, 0.15, 0.1))],
        )
        days.append(row)
    return days


def total(rows, key):
    return sum(r.get(key, 0) for r in rows)


def period_rows(days, lo, hi):
    return [r for r in days if lo.isoformat() <= r["day"] <= hi.isoformat()]


def make_periods(days, by_day):
    ranges = {
        "today": (TODAY, TODAY, TODAY - timedelta(days=1), TODAY - timedelta(days=1)),
        "week": (TODAY - timedelta(days=TODAY.weekday()), TODAY, TODAY - timedelta(days=TODAY.weekday() + 7), TODAY - timedelta(days=7)),
    }
    m0 = TODAY.replace(day=1)
    pm_end = m0 - timedelta(days=1)
    pm0 = pm_end.replace(day=1)
    ranges["month"] = (m0, TODAY, pm0, pm0 + (TODAY - m0))
    q0 = date(TODAY.year, ((TODAY.month - 1) // 3) * 3 + 1, 1)
    pq0 = date(q0.year, q0.month - 3, 1) if q0.month > 3 else date(q0.year - 1, 10, 1)
    ranges["quarter"] = (q0, TODAY, pq0, pq0 + (TODAY - q0))
    out = {}
    for name, (lo, hi, plo, phi) in ranges.items():
        cur, prv = period_rows(days, lo, hi), period_rows(days, plo, phi)
        p = {}

        def put(key, a, b):
            d = {"value": round(a, 1) if isinstance(a, float) else a, "prev": round(b, 1) if isinstance(b, float) else b}
            d["delta"] = round(a - b, 1) if isinstance(a, float) or isinstance(b, float) else a - b
            if b:
                d["deltaPct"] = round(100.0 * (a - b) / b, 1)
            p[key] = d

        for key in ("workedMin", "targetMin", "focusMin", "deepWorkMin", "agentOnlyMin", "humanMin", "contextSwitches", "interruptions",
                    "tasksDone", "prsMerged", "prsReviewed", "ticketsClosed", "commits", "screenSec"):
            put(key, total(cur, key), total(prv, key))
        put("breakMin", total(cur, "deductionMin"), total(prv, "deductionMin"))
        put("daysWorked", sum(1 for r in cur if r["workedMin"] > 0), sum(1 for r in prv if r["workedMin"] > 0))
        put("attainmentPct", 100.0 * total(cur, "workedMin") / max(1, total(cur, "targetMin")), 100.0 * total(prv, "workedMin") / max(1, total(prv, "targetMin")))
        for key, field in (("avgLoginMin", "loginTs"), ("avgLogoutMin", "logoutTs")):
            def avg(rows):
                v = [datetime.fromtimestamp(r[field], timezone.utc) for r in rows if field in r]
                return int(sum(x.hour * 60 + x.minute for x in v) / len(v)) if v else 0
            put(key, avg(cur), avg(prv))
        put("salahOnTimePct", 100.0 * total(cur, "salahOnTime") / max(1, total(cur, "salahTotal")), 100.0 * total(prv, "salahOnTime") / max(1, total(prv, "salahTotal")))
        proj = {}
        for r in cur:
            for z in by_day.get(r["day"], []):
                proj[z["zone"]] = proj.get(z["zone"], 0) + z["min"]
        # screen time covers only the days the watcher saw: the daemon then says "n of m days" and drops prev and delta
        have = sum(1 for r in cur if "screenSec" in r)
        p["screenSec"]["days"], p["screenSec"]["of"] = (have - 1 if name == "week" and have > 1 else have), have
        if name == "week" and have > 1:
            p["screenSec"] = {k: v for k, v in p["screenSec"].items() if k not in ("prev", "delta", "deltaPct")}
        p["topProjects"] = [{"project": PROJECTS[ZONES.index(k)], "min": v} for k, v in sorted(proj.items(), key=lambda kv: -kv[1])][:6]
        apps = {}
        for r in cur:
            for a in r.get("topApps", []):
                apps[a["app"]] = apps.get(a["app"], 0) + a["sec"]
        p["topApps"] = [{"app": k, "sec": v} for k, v in sorted(apps.items(), key=lambda kv: -kv[1])][:6]
        out[name] = p
    return out


def slope(vals):
    n = len(vals)
    if n < 2:
        return 0.0
    mx, my = (n - 1) / 2.0, sum(vals) / float(n)
    den = sum((i - mx) ** 2 for i in range(n))
    return sum((i - mx) * (v - my) for i, v in enumerate(vals)) / den


def make_improve(days):
    work = [r for r in days if r["kind"] == "working" and r["workedMin"] > 0]

    def trend(n):
        w = work[-n:]
        ratio = [100.0 * r["deepWorkMin"] / r["workedMin"] for r in w]
        t = {"workedMin": round(slope([r["workedMin"] for r in w]), 2), "focusMin": round(slope([r["focusMin"] for r in w]), 2),
             "deepWorkRatioPct": round(slope(ratio), 2)}
        mean = sum(r["workedMin"] for r in w) / float(len(w))
        t["dir"] = "up" if t["workedMin"] > 0.01 * mean else ("down" if t["workedMin"] < -0.01 * mean else "flat")
        return t

    def run(pred):
        cur = 0
        for r in reversed(work):
            if pred(r):
                cur += 1
            else:
                break
        return cur

    last30 = work[-30:]
    best = max(last30, key=lambda r: r["workedMin"])
    worst = min(last30, key=lambda r: r["workedMin"])
    late = [max(0, (datetime.fromtimestamp(r["loginTs"], timezone.utc).hour * 60 + datetime.fromtimestamp(r["loginTs"], timezone.utc).minute) - 540) for r in last30]

    def ratio(n):
        w = work[-n:]
        return round(100.0 * sum(r["deepWorkMin"] for r in w) / sum(r["workedMin"] for r in w), 1)

    return {
        "trend7": trend(7), "trend30": trend(30),
        "streaks": {"targetMet": run(lambda r: r["workedMin"] >= r["targetMin"]), "onTimeLogin": run(lambda r: datetime.fromtimestamp(r["loginTs"], timezone.utc).hour * 60 + datetime.fromtimestamp(r["loginTs"], timezone.utc).minute <= 540),
                    "salahOnTime": run(lambda r: r["salahOnTime"] == r["salahTotal"]), "best": {"targetMet": 9, "onTimeLogin": 14, "salahOnTime": 6}},
        "bestDay": {"day": best["day"], "workedMin": best["workedMin"]}, "worstDay": {"day": worst["day"], "workedMin": worst["workedMin"]},
        "punctuality": {"targetLoginMin": 540, "avgLateMin": round(sum(late) / float(len(late)), 1), "onTimeDays": sum(1 for x in late if x == 0), "days": len(late)},
        "deepWorkRatioPct": {"d7": ratio(7), "d30": ratio(30)},
        "interruptionsPerHour": {"d7": round(sum(r["interruptions"] for r in work[-7:]) / (sum(r["workedMin"] for r in work[-7:]) / 60.0), 2),
                                 "d30": round(sum(r["interruptions"] for r in work[-30:]) / (sum(r["workedMin"] for r in work[-30:]) / 60.0), 2)},
        "timeToFirstFocusMin": {"d7": 34, "d30": 41},
    }


def make_zones(days, rnd):
    by_day = {}
    for r in days[-30:]:
        if r["kind"] != "working" or r["focusMin"] == 0:
            continue
        left, rows = r["focusMin"], []
        picks = rnd.sample(ZONES, rnd.randint(2, 4))
        for k, z in enumerate(picks):
            m = left if k == len(picks) - 1 else int(left * rnd.uniform(0.3, 0.6))
            rows.append({"zone": z, "min": m})
            left -= m
        by_day[r["day"]] = rows
    weeks = []
    for k in range(12, 0, -1):
        mon = TODAY - timedelta(days=TODAY.weekday() + 7 * (k - 1))
        zs = [{"zone": z, "min": rnd.randint(40, 520)} for z in rnd.sample(ZONES, rnd.randint(3, 5))]
        weeks.append({"week": mon.isoformat(), "zones": zs})
    projects = [{"project": p, "min": rnd.randint(300, 2600)} for p in PROJECTS]
    for p in projects:
        p["agentMin"] = int(p["min"] * rnd.uniform(0.1, 0.5))
    return {"current": {"zone": "Platform", "state": "running"}, "byDay": by_day, "byWeek": weeks, "projects": projects}, by_day


def make_screen():
    return {"todayActiveSec": 5 * 3600 + 1260, "todayIdleSec": 2 * 3600 + 600, "weekActiveSec": 21 * 3600 + 540, "lateNightSec": 4100, "longestStretchMin": 134,
            "bySession": [{"openTs": unix(TODAY, 545), "closeTs": unix(TODAY, 725), "activeSec": 9300}, {"openTs": unix(TODAY, 770), "closeTs": unix(TODAY, 905), "activeSec": 6900},
                          {"openTs": unix(TODAY, 930), "closeTs": None, "activeSec": 4300}]}


def make_health(rnd):
    cps = []
    for i in range(13, -1, -1):
        d = (TODAY - timedelta(days=i)).isoformat()
        for slot in ("dose", "h1", "h3", "h6", "wrap"):
            if i == 0 and slot in ("h6", "wrap"):
                continue
            cps.append({"day": d, "slot": slot, "score": rnd.randint(3, 9), "outcome": rnd.choice(["answered", "answered", "answered", "skipped", "timeout"])})
    return {"checkpoints": cps, "scoreAvg7": 6.4, "doses": [{"day": (TODAY - timedelta(days=i)).isoformat(), "ts": unix(TODAY - timedelta(days=i), 520 + rnd.randint(0, 30))} for i in range(6, -1, -1)],
            "doseToFirstCheckpointMin": 63}


def make_reminders():
    return {
        "due": [{"id": "r1", "desc": "Renew the staging certificate", "due": TS - 7200, "overdue": True},
                {"id": "r2", "desc": "Send the weekly status note", "due": TS + 5400, "overdue": False},
                {"id": "r3", "desc": "Rotate the shared backup keys", "due": TS + 86400, "overdue": False},
                {"id": "r4", "desc": "Review the capacity plan", "due": TS + 3 * 86400, "overdue": False}],
        "scheduled": [{"id": "r5", "desc": "Prepare the quarterly summary", "scheduled": TS + 2 * 86400},
                      {"id": "r6", "desc": "Archive the old dashboards", "scheduled": TS + 5 * 86400}],
        "salahNext": {"prayer": "Asr", "iqamahTs": TS + 2400},
    }


def build(kind):
    rnd = random.Random(11)
    days = make_days(rnd)
    zones, by_day = make_zones(days, rnd)
    doc = {"v": 1, "ts": TS, "tz": "UTC", "today": TODAY.isoformat(), "days": days, "periods": make_periods(days, by_day), "improve": make_improve(days),
           "zones": zones, "screen": make_screen(), "health": make_health(rnd), "reminders": make_reminders(),
           "sources": {k: {"state": "ok", "reason": "all sources read"} for k in ("days", "periods", "improve", "zones", "screen", "health", "reminders")}}
    if kind == "partial":
        for k, why in (("zones", "the focus log has no rows"), ("screen", "ActivityWatch is not running"), ("health", "no health log yet"), ("reminders", "task is not installed")):
            doc.pop(k)
            doc["sources"][k] = {"state": "missing", "reason": why}
        for d in doc["days"]:
            for k in ("screenSec", "topApps"):
                d.pop(k, None)
        for p in doc["periods"].values():
            p.pop("screenSec", None)
            p.pop("topApps", None)
        doc["sources"]["aw"] = {"state": "missing", "reason": "ActivityWatch is not running"}
    if kind == "empty":
        doc = {"v": 1, "ts": TS, "tz": "UTC", "today": TODAY.isoformat(),
               "sources": {k: {"state": "missing", "reason": "the source could not be opened"} for k in ("days", "periods", "improve", "zones", "screen", "health", "reminders")}}
    return doc


def main():
    for kind, name in (("full", "metrics"), ("partial", "metrics-partial"), ("empty", "metrics-empty")):
        out = os.path.join(FIX, name)
        shutil.rmtree(out, ignore_errors=True)
        shutil.copytree(BOARD, out)
        with open(os.path.join(out, "metrics.json"), "w") as f:
            json.dump(build(kind), f, indent=1, sort_keys=True)
            f.write("\n")
        print("wrote " + name)


if __name__ == "__main__":
    main()
