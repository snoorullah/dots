#!/usr/bin/env python3
"""Regenerates tst/fixtures/<name>/{now,activity,attention,heatmap,mirror,meta}.json.

Only needed when a fixture changes; the generated files are committed. Every
fixture is "now" = NOW (the tests export DOTS_OVERVIEW_NOW=NOW), so no result
depends on the wall clock. Values are invented; no real task, person or project.
"""
import datetime
import json
import os
import sys

NOW = 1761600000
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fixtures")
SHELL_REF = 'HD-7; touch "$PWN" `id` $(id) #'   # must reach the program as ONE argument


def meta(ts, v=1):
    return {"v": v, "generatedAt": ts, "generationMs": 120, "writer": "dots-overview fixture",
            "schema": "1", "cycle": "fast", "errors": []}


def item(i, kind, urgency, waiting, title, ref=None, age=600, actor="ada", brk=False, jump=True):
    return {"id": i, "kind": kind, "title": title, "ref": ref or "", "src": "gh", "url": "https://example.invalid/" + i,
            "urgency": urgency, "waiting": waiting, "ageSec": age, "actor": actor,
            "jump": {"pane": "p1", "workspace": "w1", "sess": "s1"} if jump else None,
            "canBreakdown": brk, "startedAt": None}


def attention(ts, items, v=1, bad_source=None):
    waiting = sum(1 for i in items if i["waiting"])
    failed = sum(1 for i in items if i["kind"] == "alert" and not i["waiting"])
    srcs = {n: {"state": "ok", "ts": ts, "detail": ""} for n in ["gh", "erp", "notif", "ops", "herdr", "task"]}
    srcs["erp"]["state"] = "off"
    srcs["mail"] = {"state": "unavailable", "ts": ts, "detail": "no local store"}
    if bad_source:
        srcs[bad_source]["state"] = "stale"
    return {"v": v, "ts": ts, "items": items, "counts": {"waiting": waiting, "failed": failed, "total": len(items)},
            "sources": srcs}


def bucket(worked, done, projects, refs, apps):
    return {"workedSec": worked, "tasksDone": done,
            "byProject": [{"project": p, "sec": s} for p, s in projects],
            "byApp": [{"app": a, "sec": s} for a, s in apps],
            "byRef": [{"ref": r, "sec": s, "title": t} for r, s, t in refs]}


def activity(ts, v=1, empty=False):
    if empty:
        z = bucket(0, 0, [], [], [])
        return {"v": v, "ts": ts, "buckets": {"today": z, "week": z, "month": z, "quarter": z}}
    today = bucket(14400 + 900, 3, [("alpha", 9000), ("beta", 4500), ("misc", 1800)],
                   [("HD-101", 5400, "Fix the login redirect"), ("TASK-2026-0042", 3600, "Quarterly cleanup"),
                    ("gh:acme/widgets#12", 2700, "Review widget parser")],
                   [("editor", 8000), ("terminal", 5000), ("browser", 2300)])
    week = bucket(5 * 25200, 11, [("alpha", 70000), ("beta", 40000), ("misc", 16000)],
                  [("HD-101", 30000, "Fix the login redirect"), ("HD-088", 22000, "Backfill report")], [("editor", 90000)])
    month = bucket(20 * 25200, 38, [("alpha", 300000)], [], [])
    quarter = bucket(60 * 25200, 120, [("alpha", 900000)], [], [])
    return {"v": v, "ts": ts, "buckets": {"today": today, "week": week, "month": month, "quarter": quarter}}


def heatmap(ts, v=1, flat=False):
    end = datetime.date(2025, 10, 27)
    days = []
    for i in range(119):
        d = end - datetime.timedelta(days=118 - i)
        score = 0 if flat else i % 5            # 0..4 all present
        worked = [0, 1800, 7200, 14400, 25200][score]
        days.append({"d": d.isoformat(), "workedSec": worked, "done": score, "score": score})
    return {"v": v, "ts": ts, "spanDays": 119, "maxSec": 0 if flat else 25200, "days": days}


def now_doc(ts, v=1, task=True, focus=None):
    f = focus or {"state": "idle", "zone": "", "startedAt": None, "endsAt": None, "elapsedSec": 0, "targetSec": 1500}
    t = {"uuid": "u-1", "id": 4, "desc": "Fix the login redirect loop", "ref": "HD-101", "src": "erp",
         "project": "alpha", "tags": [], "startedAt": NOW - 900, "agent": None, "pane": None,
         "workspace": None, "sess": None} if task else None
    return {"v": v, "ts": ts, "task": t, "agent": None, "focus": f, "clock": {"state": "in", "awayReason": "", "sinceTs": NOW - 7200}}


def running(elapsed, target=1500):
    return {"state": "running", "zone": "alpha", "startedAt": NOW - elapsed, "endsAt": NOW - elapsed + target,
            "elapsedSec": elapsed, "targetSec": target}


def write(name, files):
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    for k, doc in files.items():
        with open(os.path.join(d, k + ".json"), "w") as f:
            json.dump(doc, f, indent=1, sort_keys=True)
            f.write("\n")


def bundle(ts, items, v=1, task=True, focus=None, flat=True, empty_act=True, bad_source=None):
    return {"now": now_doc(ts, v, task, focus), "activity": activity(ts, v, empty_act),
            "attention": attention(ts, items, v, bad_source), "heatmap": heatmap(ts, v, flat),
            "mirror": {"v": v, "ts": ts, "refs": []}, "meta": meta(ts, v)}


def main():
    ts = NOW - 10
    waiting = [
        item("a1", "review", "active", True, "Review the widget parser change", ref="gh:acme/widgets#12", actor="grace", brk=True, age=7200),
        item("a2", "blocker", "time", True, "Release is blocked on your sign-off", ref="HD-88", actor="linus", age=3600),
        item("a3", "task", "passive", False, "Tidy the backlog", ref="HD-12", brk=True, jump=False),
    ]
    shell_item = item("a4", "task", "active", False, "Item whose ref tries to escape quoting", ref=SHELL_REF, brk=True, jump=False)
    failed = [item("f1", "alert", "critical", False, "Nightly sync job failed", ref="ops:sync", actor="cron", age=1800)]

    write("nominal", bundle(ts, [], task=False))
    write("waiting", bundle(ts, waiting + [shell_item], flat=True))
    write("failed", bundle(ts, failed, task=False))
    write("stale", bundle(NOW - 600, waiting, flat=True))
    write("v2", bundle(ts, waiting, v=2))
    write("full", bundle(ts, waiting + failed + [
        item("b1", "dm", "active", True, "Question about the deploy window", actor="ada"),
        item("b2", "erp", "time", True, "Ticket needs your reply", ref="HD-9", actor="client", age=90000),
        item("b3", "review", "passive", True, "Second review waiting", ref="gh:acme/widgets#13", actor="ken"),
        item("b4", "alert", "active", False, "Disk usage high on a build host", ref="ops:disk", age=300),
    ], flat=False, empty_act=False))
    write("focus-90", bundle(ts, [], focus=running(375), flat=False, empty_act=False))
    write("focus-200", bundle(ts, [], focus=running(833), flat=False, empty_act=False))
    # the live-update test starts from "nominal" and swaps in this attention.json
    write("live-next", bundle(ts, waiting[:2]))
    print("fixtures written to", OUT)


if __name__ == "__main__":
    sys.exit(main())
