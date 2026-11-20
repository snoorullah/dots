#!/usr/bin/env python3
"""Writes the fixture state dirs for tests/cc-ui.sh (board sample text, neutral data).

usage: mkfixtures.py   (rewrites tst/fixtures/*)
"""
import copy
import json
import os

NOW = 1761600000
HERE = os.path.dirname(os.path.abspath(__file__))
OV = os.path.join(HERE, "..", "..", "overview", "tst", "fixtures", "full")


def item(id, kind, title, actor, age, urgency="active", waiting=False, ref=None, src="gh", jump=True, url=True, bd=False):
    return {
        "id": id, "kind": kind, "title": title, "actor": actor, "ageSec": age, "urgency": urgency,
        "waiting": waiting, "ref": ref, "src": src,
        "url": ("https://example.invalid/" + id) if url else None,
        "jump": {"pane": "p1", "sess": "s1", "workspace": "w1"} if jump else None,
        "canBreakdown": bd, "startedAt": None,
    }


ITEMS = [
    item("a1", "blocker", "Permission: terraform plan on staging", "billing-api", 720, "critical", True, "INFRA-88", "herdr"),
    item("a2", "dm", "Can you add two vCPUs to db-02 tonight?", "Priya N.", 540, "time", True, "HD 4398", "notif", jump=False),
    item("a3", "alert", "New: DiskPressure on node-7", "monitoring", 120, "critical", False, "ops:node-7", "ops", jump=False),
    item("b1", "review", "Review: move tenant-app to its own chart", "Marcus T.", 1200, "active", False, "gh:acme/charts#2291", "gh", bd=True),
    item("b2", "erp", "HD 4390 Back up the repo metadata", "Sam R.", 2700, "time", False, "HD 4390", "erp", jump=False),
    item("c1", "dm", "Replied to your question on the chart split", "Marcus T.", 7200, "passive", False, "", "notif", jump=False),
    item("c2", "blocker", "Finished: opened draft PR #2310", "docs-sync", 10800, "passive", False, "gh:acme/docs#2310", "herdr"),
    item("d1", "untracked", "Ask Sam about ballooning on db-03", None, 90000, "passive", False, None, "timetrack", jump=False, url=False),
    item("m1", "mail", "CVE advisory for the ingress controller", "Security vendor", 18000, "active", False, "", "mail", jump=False, url=False),
    item("t1", "task", "Add vCPUs to db-02", "You", 600, "time", False, "HD 4398", "erp", jump=False, bd=True),
    item("t2", "task", "Back up the repo metadata", "You", 600, "critical", False, "HD 4390", "erp", jump=False, bd=True),
    item("t3", "task", "Review tenant-app chart", "You", 600, "active", False, "gh:acme/charts#2291", "gh", jump=False),
    item("t4", "task", "CVE advisory for ingress", "You", 600, "passive", False, "", "gh", jump=False),
]

SOURCES = {k: {"detail": "", "state": "ok", "ts": NOW - 10} for k in ("gh", "herdr", "notif", "ops", "task")}
SOURCES["erp"] = {"detail": "", "state": "off", "ts": NOW - 10}
SOURCES["mail"] = {"detail": "no local store", "state": "unavailable", "ts": NOW - 10}


def att(items, ts=NOW - 10):
    shown = [i for i in items if i["kind"] not in ("task", "mail")]
    w = sum(1 for i in shown if i["waiting"])
    f = sum(1 for i in shown if not i["waiting"] and i["kind"] == "alert")
    return {"v": 1, "ts": ts, "items": items, "counts": {"waiting": w, "failed": f, "total": w + f}, "sources": SOURCES}


def now(ts=NOW - 10, agent=True):
    return {
        "v": 1, "ts": ts,
        "task": {"uuid": "u-1", "id": 4, "desc": "Rotate deploy keys", "ref": "HD 4412", "src": "erp", "project": "infra",
                 "tags": [], "startedAt": NOW - 6120, "agent": None, "pane": None, "workspace": None, "sess": None},
        "agent": {"name": "ingress-upgrade", "pane": "p3", "tab": None, "workspace": "w1", "sess": "s3", "status": "Working", "cwd": "infra/ingress"} if agent else None,
        "focus": {"state": "running", "zone": "infra", "startedAt": NOW - 360, "endsAt": None, "elapsedSec": 360, "targetSec": 1500},
        "clock": {"state": "in", "sinceTs": NOW - 3600, "loginTs": NOW - 3600, "awayReason": ""},
    }


def bucket(w, done, proj, app, agent, ref):
    return {"workedSec": w, "tasksDone": done, "byProject": [{"project": p, "sec": s} for p, s in proj],
            "byApp": [{"app": a, "sec": s} for a, s in app], "byAgent": [{"agent": a, "sec": s} for a, s in agent],
            "byRef": [{"ref": r, "title": t, "sec": s} for r, t, s in ref]}


def activity(ts=NOW - 10):
    today = bucket(17280, 4, [("Infra", 10320), ("Review", 2880), ("Comms", 1320), ("Billing", 1080)],
                   [("VS Code", 7440), ("Terminal", 5880), ("Browser", 3120), ("Slack", 1860)],
                   [("tenant-chart", 1440), ("ingress-upgrade", 840), ("docs-sync", 480)],
                   [("HD 4412", "Rotate deploy keys", 6120), ("", "No ticket: observability", 4200), ("PR #2291", "PR reviews", 2880),
                    ("HD 4405", "With agents", 2760), ("", "Slack and mail", 1320)])
    week = bucket(112800, 11, [("Infra", 51600), ("Billing", 24300), ("Review", 15000), ("Comms", 9300)], [("VS Code", 90000)], [],
                  [("HD 4412", "Rotate deploy keys", 27600), ("PR #2291", "chart split", 14700), ("HD 4390", "Metadata backup", 12600)])
    month = bucket(425000, 38, [("Infra", 300000)], [], [], [])
    quarter = bucket(1447000, 120, [("Infra", 900000)], [], [], [])
    return {"v": 1, "ts": ts, "buckets": {"today": today, "week": week, "month": month, "quarter": quarter}}


MIRROR = {"v": 1, "ts": NOW - 10, "refs": [
    {"ref": "HD 4378", "src": "erp", "url": None, "title": "HD 4378", "state": "closed", "updatedAt": NOW - 900, "taskUuid": None, "closedAt": NOW - 900, "reviewedAt": None},
    {"ref": "PR #2288", "src": "gh", "url": None, "title": "PR #2288", "state": "merged", "updatedAt": NOW - 1800, "taskUuid": None, "closedAt": None, "reviewedAt": NOW - 1800},
]}


def write(name, files):
    d = os.path.join(HERE, "fixtures", name)
    os.makedirs(d, exist_ok=True)
    for f, doc in files.items():
        with open(os.path.join(d, f + ".json"), "w") as fh:
            json.dump(doc, fh, indent=1, sort_keys=True)


def heat():
    with open(os.path.join(OV, "heatmap.json")) as fh:
        h = json.load(fh)
    h["ts"] = NOW - 10
    return h


with open(os.path.join(OV, "meta.json")) as fh:
    META = json.load(fh)
META["ts"] = NOW - 10

board = {"attention": att(ITEMS), "now": now(), "activity": activity(), "heatmap": heat(), "mirror": MIRROR, "meta": META}
write("board", board)

# nothing waiting, nothing listed
empty = copy.deepcopy(board)
empty["attention"] = att([i for i in ITEMS if i["kind"] == "task"])
write("empty", empty)

# every fast file ten minutes old: Feed.dim, the rows dim and the ? shows
stale = copy.deepcopy(board)
stale["attention"]["ts"] = NOW - 600
stale["now"]["ts"] = NOW - 600
stale["activity"]["ts"] = NOW - 600
stale["heatmap"]["ts"] = NOW - 600
write("stale", stale)

# one waiting item with shell metacharacters in its ref: argv must stay one inert argument
meta = copy.deepcopy(board)
meta["attention"]["items"][3]["ref"] = 'HD-7; touch "$PWN" `id` $(id) #'
write("meta", meta)

# board plus: a previous pending review, a Slack alert-channel post (kind alert), and two agent
# tasks that sit in herdr panes with a session record each (For / Working on / Jump)
extra = copy.deepcopy(board)
prev = item("p1", "review", "Review: retire the old queue worker", "Marcus T.", 400000, "active", True, "gh:acme/worker#77", "gh")
prev["section"] = "previous"
slack_alert = item("s1", "alert", "Alert channel: disk pressure on node-9", None, 300, "active", False, "", "notif", jump=False)
agent_a = item("g1", "task", "TASK-2026-00111 verify the inventory keys", None, 900, "active", False, "TASK-2026-00111", "claude")
agent_a["jump"] = {"pane": "w2:p1", "workspace": "w2", "sess": "sess-aaaa"}
agent_b = item("g2", "task", "tidy the chart values", None, 1500, "passive", False, "local:ab12", "lanes")
agent_b["jump"] = {"pane": "w3:p1", "workspace": "w3", "sess": "sess-bbbb"}
extra["attention"] = att(ITEMS + [prev, slack_alert, agent_a, agent_b])
write("extra", extra)
sd = os.path.join(HERE, "fixtures", "extra", "sessions")
os.makedirs(sd, exist_ok=True)
for sid, rec in (("sess-aaaa", {"agent": "Atlas", "pane": "w2:p1", "ticket": "lane:TASK-2026-00111", "prompt_head": "verify the inventory keys"}),
                 ("sess-bbbb", {"agent": "Vega", "pane": "w3:p1", "ticket": "local:ab12", "prompt_head": "tidy the chart values"})):
    with open(os.path.join(sd, sid + ".json"), "w") as fh:
        json.dump(dict(rec, v=1, ts=NOW - 10, action="stop", sess=sid), fh, indent=1, sort_keys=True)
