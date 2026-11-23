#!/usr/bin/env python3
"""Writes the agent-metrics and away fixtures for Time > Agents and the Agents page (tests/cc-ui.sh).

usage: mkagents.py   (rewrites tst/fixtures/agents and tst/fixtures/agents-partial)

Neutral made-up numbers, the shape in docs/shell/specs/cc-agent-metrics.md.
`agents` is a full file with live counts and an away list that has answered and unanswered gaps.
`agents-partial` leaves things out the way a real file may: a null cost, an unpriced model, no
prev or delta, no live counts, no away gaps.
"""
import json
import os
import random
import shutil
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
TODAY = date(2025, 10, 30)
TS = int(datetime(2025, 10, 30, 17, 40, tzinfo=timezone.utc).timestamp())
MODELS = [("claude-opus-5", 5.0, 25.0, 6.25, 0.5), ("claude-sonnet-5-5", 2.0, 10.0, 2.5, 0.1), ("claude-haiku-5", 0.8, 4.0, 1.0, 0.08)]


def tok(rnd, scale):
    o = int(scale * rnd.uniform(0.002, 0.004))
    i = int(scale * rnd.uniform(0.00001, 0.00004))
    cw = int(scale * rnd.uniform(0.02, 0.04))
    cr = scale - o - i - cw
    return {"in": i, "out": o, "cacheWrite": cw, "cacheRead": cr, "total": i + o + cw + cr, "msgs": max(1, int(scale / 250000))}


def price(t, m):
    return round((t["in"] * m[1] + t["out"] * m[2] + t["cacheWrite"] * m[3] + t["cacheRead"] * m[4]) / 1e6, 4)


def add(a, b):
    return {k: a[k] + b[k] for k in a}


def zero():
    return {"in": 0, "out": 0, "cacheWrite": 0, "cacheRead": 0, "total": 0, "msgs": 0}


def span(rnd, days, first, last):
    """one period: rows by agent, ticket and model, drawn from the day list"""
    runs = sum(d["runs"] for d in days)
    tk = zero()
    cost = 0.0
    for d in days:
        tk = add(tk, d["tokens"])
        cost += d["costUsd"] or 0.0
    p = {"first": first, "last": last, "runs": runs, "prompts": sum(d["prompts"] for d in days), "activeMin": round(sum(d["activeMin"] for d in days), 1),
         "waitingMin": round(sum(d["waitingMin"] for d in days), 1), "tokens": tk, "costUsd": round(cost, 4),
         "subagentShare": round(rnd.uniform(0.25, 0.6), 4), "unpricedTokens": 0}
    return p


def keyed(rnd, keys, total_tok, total_cost, total_runs, total_active, extra=None):
    w = [(1.0 - 0.14 * i) * rnd.uniform(0.95, 1.05) for i in range(len(keys))]   # the first key is the biggest
    s = sum(w)
    rows = []
    for k, x in sorted(zip(keys, w), key=lambda z: -z[1]):
        f = x / s
        t = tok(rnd, max(1000, int(total_tok * f)))
        r = {"key": k, "runs": max(1, round(total_runs * f)), "prompts": max(1, int(40 * f * 10)), "activeMin": round(total_active * f, 1), "waitingMin": round(total_active * f * 2, 1),
             "tokens": t, "costUsd": round(total_cost * f, 4), "subagentShare": round(rnd.uniform(0.2, 0.7), 4)}
        if extra:
            r.update(extra(k))
        rows.append(r)
    return rows


def build(kind):
    rnd = random.Random(7)
    days = []
    for i in range(29, -1, -1):
        d = TODAY - timedelta(days=i)
        busy = d.weekday() < 5 and rnd.random() > 0.1
        scale = int(rnd.uniform(40e6, 260e6)) if busy else (int(rnd.uniform(1e6, 8e6)) if rnd.random() > 0.5 else 0)
        t = tok(rnd, scale) if scale else zero()
        m = MODELS[0]
        days.append({"day": d.isoformat(), "runs": rnd.randint(2, 9) if scale else 0, "prompts": rnd.randint(10, 70) if scale else 0,
                     "activeMin": round(rnd.uniform(40, 220), 1) if scale else 0.0, "waitingMin": round(rnd.uniform(60, 300), 1) if scale else 0.0,
                     "tokens": t, "costUsd": price(t, m) if scale else None, "subagentShare": round(rnd.uniform(0.2, 0.6), 4) if scale else 0.0})
    agents = ["Atlas", "Vega", "billing-api", "docs-sync", "Orion", "Lyra"]
    tickets = ["HD 4398", "HD 4390", "gh:acme/charts#2291", "TASK-2026-00111", "local:ab12", "HD 4378"]
    periods = {}
    for name, n in (("today", 1), ("week", 7), ("month", 30)):
        cur = days[-n:]
        prev_days = [] if name == "month" else [dict(d) for d in days[-2 * n:-n]]
        p = span(rnd, cur, cur[0]["day"], cur[-1]["day"])
        tk = p["tokens"]["total"]
        p["byAgent"] = keyed(rnd, agents, tk, p["costUsd"] or 0, p["runs"], p["activeMin"], lambda k: {"models": [m[0] for m in MODELS[:2]]})
        p["byTicket"] = keyed(rnd, tickets, tk, p["costUsd"] or 0, p["runs"], p["activeMin"])
        mrows = []
        for m, share in zip(MODELS, (0.62, 0.3, 0.08)):
            t = tok(rnd, int(tk * share))
            mrows.append({"key": m[0], "tokens": t, "costUsd": price(t, m), "priced": True, "subagentShare": round(rnd.uniform(0.2, 0.7), 4)})
        p["byModel"] = mrows
        if prev_days:
            pp = span(rnd, prev_days, prev_days[0]["day"], prev_days[-1]["day"])
            p["prev"] = {k: pp[k] for k in ("first", "last", "runs", "prompts", "activeMin", "waitingMin", "tokens", "costUsd")}
        else:
            p["prev"] = {"first": "2025-09-01", "last": "2025-09-30", "runs": 120, "prompts": 900, "activeMin": 3000.0, "waitingMin": 9000.0, "tokens": zero(), "costUsd": 1500.0}
            p["prev"]["tokens"] = tok(rnd, 4_000_000_000)
        pv = p["prev"]
        p["delta"] = {"runs": p["runs"] - pv["runs"], "prompts": p["prompts"] - pv["prompts"], "activeMin": round(p["activeMin"] - pv["activeMin"], 1),
                      "waitingMin": round(p["waitingMin"] - pv["waitingMin"], 1), "tokens": p["tokens"]["total"] - pv["tokens"]["total"],
                      "costUsd": round((p["costUsd"] or 0) - (pv["costUsd"] or 0), 4)}
        periods[name] = p
    doc = {"v": 1, "ts": TS, "today": TODAY.isoformat(), "costIsEstimate": True,
           "prices": [{"match": m[0], "perMTok": {"in": m[1], "out": m[2], "cacheWrite": m[3], "cacheRead": m[4]}} for m in MODELS],
           "days": days, "periods": periods, "live": {"agents": 5, "byStatus": {"working": 2, "idle": 2, "blocked": 1}, "needsYou": 1}}
    if kind == "partial":
        doc.pop("live")
        for name, p in periods.items():
            p.pop("prev", None)
            p.pop("delta", None)
        p = periods["week"]
        p["costUsd"] = None
        p["unpricedTokens"] = p["tokens"]["total"]
        for r in p["byAgent"] + p["byTicket"]:
            r["costUsd"] = None
        p["byModel"][2]["costUsd"] = None
        p["byModel"][2]["priced"] = False
        for d in doc["days"]:
            d["costUsd"] = None
        periods["today"].pop("byTicket")
        periods["today"].pop("subagentShare")
        periods["today"]["costUsd"] = None
    return doc


def away(kind):
    gaps = []
    if kind == "full":
        base = datetime(2025, 10, 30, 8, 0, tzinfo=timezone.utc)
        spec = [(0, 22.5, "Walk / short break", True, "declared"), (26, 6.1, "misc", False, "deduction"), (70, 35.0, "Lunch", True, "asked"),
                (110, 12.4, "misc", False, "auto")]
        for off, mins, label, ans, src in spec:
            st = int((base + timedelta(minutes=off * 5)).timestamp())
            gaps.append({"startTs": st, "endTs": st + int(mins * 60), "day": "2025-10-30", "category": label.lower().split(" ")[0] or "misc", "label": label,
                         "answered": ans, "source": src, "minutes": mins})
        for dd, mins, label, ans in ((29, 18.0, "Salah", True), (29, 41.0, "misc", False), (28, 9.0, "Washroom", True), (27, 25.0, "misc", False), (26, 52.0, "Lunch", True),
                                     (25, 7.5, "misc", False), (24, 14.0, "Salah", True)):
            st = int(datetime(2025, 10, dd, 11, 15, tzinfo=timezone.utc).timestamp())
            gaps.append({"startTs": st, "endTs": st + int(mins * 60), "day": "2025-10-%02d" % dd, "category": label.lower(), "label": label, "answered": ans, "source": "deduction", "minutes": mins})
    un = [g for g in gaps if not g["answered"]]
    return {"v": 1, "ts": TS, "spanDays": 7, "count": len(gaps), "answered": len(gaps) - len(un), "unanswered": len(un),
            "totalMin": round(sum(g["minutes"] for g in gaps), 1), "byCategory": {}, "gaps": gaps}


def main():
    for kind, name in (("full", "agents"), ("partial", "agents-partial")):
        out = os.path.join(FIX, name)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        with open(os.path.join(out, "agent-metrics.json"), "w") as f:
            json.dump(build(kind), f, indent=1, sort_keys=True)
            f.write("\n")
        with open(os.path.join(out, "away.json"), "w") as f:
            json.dump(away(kind), f, indent=1, sort_keys=True)
            f.write("\n")
        print("wrote " + name)


if __name__ == "__main__":
    main()
