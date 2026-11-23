#!/usr/bin/env python3
"""Probe, argv and pixel assertions for tests/cc-ui.sh (stdlib only, no PIL).

usage: check.py <name> <outdir>

Reads <outdir>/<tag>.json (one PROBE line from tst/Scene.qml), <tag>.png and <tag>.exec
(the argv lines the stub commands logged), prints one "PASS|FAIL <name>: detail" line per
assertion and exits non-zero on any FAIL. Colours are the stub Theme's, derived from the
palette exactly as the real Tokens.qml derives them.
"""
import colorsys
import json
import os
import re
import struct
import sys
import zlib

failures = 0
OUT = ""


def report(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print("%s %s%s" % ("PASS" if ok else "FAIL", name, (": " + detail) if (detail and not ok) else ""))


def probe(tag):
    with open(os.path.join(OUT, tag + ".json")) as f:
        return json.loads(f.read().strip().splitlines()[-1])


def execs(tag):
    p = os.path.join(OUT, tag + ".exec")
    if not os.path.exists(p):
        return []
    return [l.rstrip("\n").split("\t") for l in open(p) if l.strip()]


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png: " + path
    pos, idat, w, h, depth, ctype = 8, b"", 0, 0, 8, 6
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
        elif typ == b"IDAT":
            idat += body
    assert depth == 8 and ctype in (2, 6), "unsupported png"
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[p]
        cur = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                cur[i] = (cur[i] + a) & 255
            elif ft == 2:
                cur[i] = (cur[i] + b) & 255
            elif ft == 3:
                cur[i] = (cur[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        rows.append(cur)
        prev = cur
    return w, h, bpp, rows


class Img:
    def __init__(self, tag):
        self.w, self.h, self.bpp, self.rows = read_png(os.path.join(OUT, tag + ".png"))

    def px(self, x, y):
        x, y = int(x), int(y)
        if not (0 <= x < self.w and 0 <= y < self.h):
            return (0, 0, 0)
        r, i = self.rows[y], x * self.bpp
        return (r[i], r[i + 1], r[i + 2])

    def count(self, pred, box=None):
        x0, y0, x1, y1 = box or (0, 0, self.w, self.h)
        n = 0
        for y in range(max(0, y0), min(self.h, y1)):
            r = self.rows[y]
            for x in range(max(0, x0), min(self.w, x1)):
                i = x * self.bpp
                if pred(r[i], r[i + 1], r[i + 2]):
                    n += 1
        return n


def hue(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    d = h * 360
    return (d - 360 if d > 180 else d), s, v


def is_amber(r, g, b):
    d, s, v = hue(r, g, b)
    return 22 <= d <= 50 and s >= 0.45 and v >= 0.75


def is_red(r, g, b):
    d, s, v = hue(r, g, b)
    return -15 <= d <= 15 and s >= 0.30 and v >= 0.70


def is_green(r, g, b):
    d, s, v = hue(r, g, b)
    return 80 <= d <= 170 and s >= 0.25 and v >= 0.30


def ids(p, sec=None):
    return [r["id"] for r in p["rows"] if sec is None or r["sec"] == sec]


def row_box(p, id):
    return [r for r in p["rows"] if r["id"] == id][0]


def non_overlap(rows):
    rs = sorted(rows, key=lambda r: r["y"])
    return all(rs[i]["y"] + rs[i]["h"] <= rs[i + 1]["y"] for i in range(len(rs) - 1))


def layout(tag, p):
    report(p["size"] == {"w": 1600, "h": 1000}, tag + " stage is the board's 1600 x 1000", str(p["size"]))
    report(p["header"]["h"] == 72 and p["header"]["w"] == 1600, tag + " header 72 px", str(p["header"]))
    report(p["nav"]["w"] == 208 and p["nav"]["y"] == 72, tag + " nav 208 px wide", str(p["nav"]))
    report(p["footer"]["h"] == 40 and p["footer"]["y"] == 960, tag + " footer 40 px", str(p["footer"]))
    report(p["page"]["x"] == 208 and p["page"]["w"] == 1392, tag + " page fills the rest", str(p["page"]))


def check_queue():
    p = probe("queue")
    layout("queue", p)
    report(p["navTabs"] == ["Queue:9*", "Inbox:9", "Agents:5", "Tasks:4", "Time:0"], "queue nav tabs and counts", str(p["navTabs"]))
    report(p["detail"] and p["detail"]["w"] == 500 and p["detail"]["x"] == 1100, "queue detail is 500 px at the right", str(p["detail"]))
    names = [s["text"] for s in p["sections"]]
    report(names == ["WAITING ON YOU", "TODAY", "WHILE YOU WERE AWAY", "FROM YESTERDAY"], "queue sections in board order", str(names))
    report(ids(p, "WAITING ON YOU") == ["a1", "a3", "a2"] and ids(p, "TODAY") == ["b2", "b1"]
           and ids(p, "WHILE YOU WERE AWAY") == ["m1", "c2", "c1"] and ids(p, "FROM YESTERDAY") == ["d1"],
           "queue rows land in the right sections, urgency first")
    report(len(p["rows"]) == 9 and all(r["h"] == 56 for r in p["rows"]), "queue 9 rows, 56 px each")
    report(non_overlap(p["rows"]) and non_overlap(p["sections"]), "queue rows and headings do not overlap")
    report(all(r["w"] == p["rows"][0]["w"] for r in p["rows"]), "queue rows share one width")
    cur = [r["id"] for r in p["rows"] if r["current"]]
    report(cur == ["a1"] and p["sel"] == "a1", "queue first row is selected", str(cur))
    marks = {r["id"]: r["mark"] for r in p["rows"]}
    report(marks == {"a1": True, "a3": True, "a2": True, "b2": False, "b1": False, "m1": False, "c2": False, "c1": False, "d1": False},
           "queue marks only on waiting and failed", str(marks))
    report(p["detailTitle"] == "Permission: terraform plan on staging", "queue detail shows the selected item", p["detailTitle"])
    acts = [(a["t"], a["stub"], a["blocked"]) for a in p["actions"]]
    want = [("Allow once", True, False), ("Deny", True, False), ("Open pane", False, False), ("Snooze", False, False),
            ("Break down & start", False, True), ("Jump", False, False)]
    report(acts == want, "queue agent actions: remote ones are stubs, local ones live", str(acts))
    report(all(a["h"] == 30 for a in p["actions"]) and p["actions"][0]["primary"], "queue action buttons 30 px, first is primary")
    report([c["t"] for c in p["chips"]] == ["All", "Agent", "Slack", "Mail", "GitHub", "ERP", "Alert"] and all(c["h"] == 26 for c in p["chips"]),
           "queue source chips, 26 px")
    report([g["t"] for g in p["groups"] if g["on"]] == ["Urgency"], "queue grouped by Urgency")
    report("Mail=unavailable" in p["sources"] and "ERP=off" in p["sources"] and not any("ok" in s.split("=")[1] for s in p["sources"]),
           "queue sources say what they are", str(p["sources"]))
    report(p["status"] == "Nothing else is waiting on you past these." and not p["undo"], "queue footer status and no Undo yet")
    img = Img("queue")
    a1, a3 = row_box(p, "a1"), row_box(p, "a3")
    amber = img.count(is_amber, (a1["x"] + 60, a1["y"], a1["x"] + 100, a1["y"] + a1["h"]))
    red = img.count(is_red, (a3["x"] + 60, a3["y"], a3["x"] + 100, a3["y"] + a3["h"]))
    report(amber > 15, "queue amber circle and age on the waiting row", "%d px" % amber)
    report(red > 15, "queue red diamond and age on the failed row", "%d px" % red)
    report(img.count(is_amber, (a3["x"] + 60, a3["y"], a3["x"] + 100, a3["y"] + a3["h"])) == 0, "queue failed row has no amber")
    report(img.count(is_green) == 0, "queue has no green pixel anywhere")
    sel_bg, rest_bg = img.px(a1["x"] + 400, a1["y"] + 28), img.px(a3["x"] + 400, a3["y"] + 28)
    report(sel_bg != rest_bg and sum(sel_bg) > sum(rest_bg), "queue selected row sits on a raised surface", "%s vs %s" % (sel_bg, rest_bg))
    accent = img.count(lambda r, g, b: abs(r - 0x8c) < 8 and abs(g - 0xcf) < 8 and abs(b - 0xf1) < 8, (0, 0, 80, 72))
    report(accent > 20, "queue logo uses the accent colour", "%d px" % accent)


def check_groups():
    p = probe("queue-source")
    names = [s["text"] for s in p["sections"]]
    report(sorted(names) == sorted(["AGENT", "ALERT", "SLACK", "ERP", "MAIL", "GITHUB", "YOU"]), "group by Source: one section per source", str(names))
    report([g["t"] for g in p["groups"] if g["on"]] == ["Source"], "group by Source is the active toggle")
    p = probe("queue-person")
    names = [s["text"] for s in p["sections"]]
    report("MARCUS T." in names and "YOU" in names and "BILLING-API" in names, "group by Person: one section per person", str(names))
    report(p["sel"] == "b1" and [r["id"] for r in p["rows"] if r["current"]] == ["b1"], "SELECT picks the row", p["sel"])
    report(non_overlap(p["rows"]), "group by Person: rows do not overlap")
    p = probe("queue-slack")
    report(sorted(ids(p)) == ["a2", "c1"] and [c["t"] for c in p["chips"] if c["on"]] == ["Slack"], "Slack filter keeps the two Slack items", str(ids(p)))


def check_inbox():
    p = probe("inbox")
    report(len(p["rows"]) == 9 and "a1" in ids(p) and "c2" in ids(p), "inbox lists the agents that need me too", str(ids(p)))
    report(p["navTabs"][1] == "Inbox:9*", "inbox tab is current", str(p["navTabs"]))
    report(p["sel"] == ids(p)[0], "inbox selects its own first row", p["sel"])


def check_compose():
    p = probe("queue-reply")
    report(p["sel"] == "a2" and p["compose"]["reply"] and not p["compose"]["agent"], "reply panel opens under the actions", str(p["compose"]))
    report(len(p["send"]) == 1 and p["send"][0]["stub"] and not p["send"][0]["live"] and p["send"][0]["tip"] == "read-only for now",
           "Send is a disabled stub with the read-only tooltip", str(p["send"]))
    acts = {a["t"]: a for a in p["actions"]}
    report(acts["Reply"]["primary"], "Reply is the primary action of a message")
    report(acts["Send to agent"]["stub"] is False, "Send to agent opens its panel (typing is local)")
    report(Img("queue-reply").count(is_green) == 0, "reply panel has no green")
    p = probe("queue-agent")
    report(p["compose"]["agent"] and not p["compose"]["reply"] and len(p["hand"]) == 1 and p["hand"][0]["stub"] and not p["hand"][0]["live"],
           "agent panel: Hand to agent is a disabled stub", str(p["hand"]))
    p = probe("queue-snooze")
    report(p["compose"]["snooze"] and p["sel"] == "a3", "snooze panel opens", str(p["compose"]))


def check_empty():
    p = probe("queue-empty")
    report(len(p["rows"]) == 0 and p["empty"] == 1, "empty feed: the list says so", "rows=%d empty=%d" % (len(p["rows"]), p["empty"]))
    report(p["detailTitle"] == "" and p["actions"] == [], "empty feed: detail asks for a pick, no actions")
    report(p["navTabs"][0] == "Queue:0*", "empty feed: counts are zero", str(p["navTabs"]))
    layout("empty", p)


def check_stale():
    p = probe("queue-stale")
    report(all(r["dim"] for r in p["rows"]) and len(p["rows"]) == 9, "stale feed: every row dims", "dim=%s" % [r["dim"] for r in p["rows"]])
    report(p["staleMark"] == 1, "stale feed: the ? shows beside SOURCES", str(p.get("staleMark")))
    report(probe("queue")["staleMark"] == 0, "fresh feed: no ? mark")


def check_agents():
    p = probe("agents")
    layout("agents", p)
    report(p["navTabs"][2] == "Agents:5*", "agents tab is current", str(p["navTabs"]))
    report(p["agentRows"] == 5, "agents: one row per agent", str(p["agentRows"]))
    report(len(p["rows"]) == 0, "agents: the queue list is hidden")
    img = Img("agents")
    report(img.count(is_amber, (208, 150, 700, 260)) > 10, "agents: the waiting row carries amber")
    report(img.count(is_green) == 0, "agents: no green")


def check_work():
    p = probe("work")
    layout("work", p)
    report(p["now"] is not None and p["now"]["h"] == 150, "tasks: NOW card is 150 px", str(p["now"]))
    report(p["todayRows"] == 4 and p["board"] == 0 and p["all"] == 0, "tasks: Today view lists the four picked tasks", "rows=%d" % p["todayRows"])
    report([v["t"] for v in p["taskViews"] if v["on"]] == ["Today"], "tasks: Today view is active")
    report(p["stats"] and p["stats"][0] == "1:42", "tasks: time on this task from today's refs", str(p["stats"]))
    b = probe("work-board")
    report(b["board"] == 1 and b["todayRows"] == 0, "tasks: Board view replaces Today")
    a = probe("work-all")
    report(a["all"] == 1 and a["board"] == 0, "tasks: All view replaces Today")
    report(Img("work").count(is_green) == 0, "tasks: no green")


def work_geometry(tag, label, expect_scrolls, long_list=False, key="work"):
    p = probe(tag)
    w = p[key]
    page = w["page"]
    report(not w["flickPage"], label + ": the page itself is not a Flickable", str(page))
    names = sorted(f["name"] for f in w["flicks"])
    report(names == sorted(expect_scrolls), label + ": only the list areas scroll", str(names))
    report(all(f["clip"] for f in w["flicks"]), label + ": every list area clips", str(w["flicks"]))
    inside = all(c["x"] >= page["x"] and c["y"] >= page["y"] and c["x"] + c["w"] <= page["x"] + page["w"] and (c.get("inFlick") or c["y"] + c["h"] <= page["y"] + page["h"]) for c in w["cols"])
    report(inside, label + ": no card or column leaves the page", str(w["cols"]))
    report(not w["out"], label + ": no text runs outside the box it sits in", str(w["out"][:3]))
    for f in w["flicks"]:
        report(f["box"]["y"] + f["box"]["h"] <= page["y"] + page["h"], label + ": " + f["name"] + " ends inside the page", str(f["box"]))
    if long_list:
        report(any(f["contentH"] > f["box"]["h"] for f in w["flicks"]), label + ": the long list is taller than its area, so it scrolls", str(w["flicks"]))
    bad = [t for t in w["texts"] + [w["headerNow"]] if re.search(r"TASK-\d{4}-\d+|local:|lane:", t)]
    report(not bad, label + ": no TASK-/local:/lane: id on screen", str(bad[:3]))
    return p


def check_work_layout():
    work_geometry("work", "tasks Today", ["todayScroll", "untickScroll"])
    work_geometry("work-board", "tasks Board", ["boardScroll"] * 4)
    work_geometry("work-all", "tasks All", ["allScroll"])
    m = work_geometry("work-many", "tasks Today (24 tasks)", ["todayScroll", "untickScroll"], True)
    report(any(re.match(r"^(HD \d{4}|[a-z]+#\d+)", t) for t in m["work"]["rowsText"]), "tasks: rows lead with a ticket", str(m["work"]["rowsText"][:3]))
    work_geometry("work-many-board", "tasks Board (24 tasks)", ["boardScroll"] * 4, True)
    work_geometry("work-many-all", "tasks All (24 tasks)", ["allScroll"], True)
    work_geometry("work-wide", "tasks 1920x1080", ["todayScroll", "untickScroll"], True)
    work_geometry("work-short", "tasks Today short", ["todayScroll", "untickScroll"], True)
    work_geometry("work-short-board", "tasks Board short", ["boardScroll"] * 4, True)
    work_geometry("work-short-all", "tasks All short", ["allScroll"], True)
    n = probe("work-many")
    report(n["work"]["page"]["h"] > 0 and any("Move every tenant database" in t for t in n["work"]["texts"]) and not any("00781" in t for t in n["work"]["texts"]), "tasks: the NOW header says the ticket and description, not TASK- ref", str([t for t in n["work"]["texts"] if "tenant database" in t]))
    report(n["work"]["headerNow"].startswith("Move every tenant") or n["work"]["headerNow"].startswith("HD"), "tasks: the header's now text is ticket first", n["work"]["headerNow"])


def check_time_layout():
    tabs = [("time", "Today", ["doneScroll", "whereScroll"]), ("time-week", "Week", ["weekSideScroll"]),
            ("time-days", "Days", ["daysScroll"]), ("time-heat", "Heatmap", ["monthsScroll", "improveScroll"]), ("time-focus", "Focus zones", ["zoneScroll"]),
            ("time-progress", "Progress", ["progressScroll"]), ("time-report", "Report", ["reportScroll"]), ("time-screen", "Screen and health", ["screenScroll", "healthScroll"]),
            ("time-reminders", "Reminders", ["remScroll"]), ("time-agents", "Agents", ["agentTableScroll", "agentSideScroll"])]
    for tag, name, scrolls in tabs:
        for suffix, size in (("", "1600x1000"), ("-wide", "1920x1080"), ("-short", "short")):
            work_geometry(tag + suffix, "time %s %s" % (name, size), scrolls, key="timePg")
    h = probe("time-heat-wide")["timePg"]
    g = [c for c in h["cols"] if c["name"] == "heatGrid"]
    k = [c for c in h["cols"] if c["name"] == "timeHeat"]
    report(g and k and g[0]["x"] + g[0]["w"] <= k[0]["x"] + k[0]["w"], "time Heatmap: the grid sits inside its card at 1920 wide", str((g, k)))
    t = probe("time-week")["timePg"]
    report(t["cols"] and all(c["y"] < 400 for c in t["cols"] if c["name"] == "weekCard"), "time Week: content starts at the top, not centred", str(t["cols"]))
    for tag in ("time-days", "time-report", "time-focus", "time-progress", "time-screen", "time-reminders"):
        q = probe(tag)["timePg"]
        report(q["cols"] and min(c["y"] for c in q["cols"]) < 300, "time %s: cards sit under the sub-tabs" % tag, str(q["cols"]))
    # the cards fill the page: nothing stops half way down a tall window
    for tag in ("time-week", "time-days", "time-heat", "time-focus", "time-reminders"):
        q = probe(tag + "-wide")["timePg"]
        cards = [c for c in q["cols"] if c["name"] in ("weekCard", "daysCard", "monthsCard", "zoneRank", "zoneDays", "zoneProjects", "remindersCard")]
        report(cards and max(c["y"] + c["h"] for c in cards) >= q["page"]["y"] + q["page"]["h"] - 80, "time %s: the card runs down to the hint line at 1920x1080" % tag, str(cards))
    # the screenshots show data under every sub-tab, and the keyboard hint line
    for tag in ("time-week", "time-days", "time-heat", "time-focus", "time-progress", "time-report", "time-screen", "time-reminders", "time-agents"):
        report(probe(tag)["tm"]["hintBar"] == 1, "time %s: the key hint line is on screen" % tag)


def check_agents_time():
    """Time > Agents and the Agents page cards, against tst/fixtures/agents (mkagents.py)."""
    p = probe("time-agents")
    a = p["ag"]
    report(a["tab"] and p["time"]["noData"] == 0 and a["noData"] == 0, "agents tab: shows with the agent-metrics fixture, no empty note", str(a["noData"]))
    report([t["t"] for t in p["timeTabs"] if t["on"]] == ["Agents"] and p["timeTabs"][-1]["t"] == "Agents", "agents tab: Agents is the last sub-tab and active", str([t["t"] for t in p["timeTabs"]]))
    report(a["kpi"] == 6 and len(a["kpiValues"]) == 6 and "no data" not in a["kpiValues"], "agents tab: six KPI cards with values", str(a["kpiValues"]))
    report(any(v.startswith("est. $") for v in a["kpiValues"]) and "list price estimate" in a["kpiNotes"], "agents tab: cost says est. and the list price note", str((a["kpiValues"], a["kpiNotes"])))
    report(any(re.match(r"^\d+(\.\d+)?[KMB]$", v) for v in a["kpiValues"]), "agents tab: tokens are shown as a total", str(a["kpiValues"]))
    report(a["deltas"] >= 6, "agents tab: every card carries its change against the previous period", str(a["deltas"]))
    report([s["t"] for s in a["periodSegs"] if s["on"]] == ["This week"] and len(a["periodSegs"]) == 3, "agents tab: period switch today, week, month (week first)", str(a["periodSegs"]))
    report(a["kindSegs"] == 4 and a["legend"] == 4, "agents tab: tokens by kind is one stacked bar of four kinds with a legend", str((a["kindSegs"], a["legend"])))
    report(a["tblRows"] == 6 + 6 + 3, "agents tab: rows by agent, ticket and model", str(a["tblRows"]))
    report(a["dailyTokens"] == 1 and a["dailyCost"] == 1, "agents tab: 30-day tokens and cost bars", str((a["dailyTokens"], a["dailyCost"])))
    report(re.match(r"^\d+%$", a["subShare"]) is not None, "agents tab: subagent share", a["subShare"])
    report(a["live"]["shown"] == 1 and (a["live"]["working"], a["live"]["needs"], a["live"]["idle"]) == ("2", "1", "2"), "agents tab: live working, needs you, idle", str(a["live"]))
    tx = " ".join(p["timePg"]["texts"])
    report(not re.search(r"TASK-\d{4}-\d+|local:|lane:", tx), "agents tab: no TASK-/local:/lane: id on screen", tx[:200])
    report("Atlas" in tx and "HD 4398" in tx and "Local task" in tx and "opus-5" in tx, "agents tab: agent, ticket and model names", tx[:300])
    report(p["k"]["hint"] and a["ks"]["row"] == 0, "agents tab: cursor on the first row", str(a["ks"]))
    img = Img("time-agents-wide")
    report(img.count(is_green) == 0, "agents tab: no green")
    w = probe("time-agents-wide")
    report(w["ag"]["tblRows"] == 15, "agents tab at 1920: every row is there", str(w["ag"]["tblRows"]))
    s = probe("time-agents-short")["ag"]
    report(s["sideScroll"] and s["sideScroll"][0]["contentH"] > s["sideScroll"][0]["h"], "agents tab short: the side cards scroll inside their own clip", str(s["sideScroll"]))
    report(s["tableScroll"] and s["tableScroll"][0]["clip"], "agents tab short: the table scrolls inside its own clip", str(s["tableScroll"]))
    # partial: null costs, no prev or delta, no live counts
    q = probe("time-agents-partial")["ag"]
    report(q["tab"] and q["kpi"] == 6 and "no data" in q["kpiValues"], "agents partial: a null cost reads no data, tokens stay", str(q["kpiValues"]))
    report(q["deltas"] == 0, "agents partial: omitted prev and delta draw no change", str(q["deltas"]))
    report(q["live"]["shown"] == 0, "agents partial: no live counts says so", str(q["live"]))
    qt = " ".join(probe("time-agents-partial")["timePg"]["texts"])
    report("NaN" not in qt and "undefined" not in qt and "no price" in qt, "agents partial: no NaN or undefined, the unpriced model says so", qt[:200])
    n = probe("time-agents-nofile")["ag"]
    report(n["noData"] == 1 and n["kpi"] == 0, "agents tab: no file says so", str(n))
    # period keys and the jump
    k = probe("keys-time-agents-period")["ag"]
    report([s["t"] for s in k["periodSegs"] if s["on"]] == ["This month"], "agents keys: p steps week to month", str(k["periodSegs"]))
    k = probe("keys-time-agents-today")["ag"]
    report([s["t"] for s in k["periodSegs"] if s["on"]] == ["Today"], "agents keys: P steps week back to Today", str(k["periodSegs"]))
    report(probe("keys-time-agents-rows")["ag"]["ks"]["row"] == 2, "agents keys: j j moves the row cursor")
    jx = execs("keys-time-agents-jump")
    report(len(jx) == 1 and jx[0][0] == "dots-jump", "agents keys: Enter on a live agent row runs dots-jump (one argv)", str(jx))
    report(execs("keys-time-agents-nojump") == [] and "Only an agent row" in probe("keys-time-agents-nojump")["k"]["status"], "agents keys: Enter on a non-live row says so and runs nothing", probe("keys-time-agents-nojump")["k"]["status"])
    report([e[0] for e in execs("keys-time-agents-o")] == ["dots-jump"], "agents keys: o jumps too", str(execs("keys-time-agents-o")))
    report("o|Jump to the agent's pane" in probe("keys-time-agents-help")["k"]["helpRows"], "agents keys: help lists o", str(probe("keys-time-agents-help")["k"]["helpRows"]))
    report(probe("keys-time-agents-sub")["k"]["timeTab"] == "Agents", "agents keys: [ from Today goes to Agents", probe("keys-time-agents-sub")["k"]["timeTab"])
    # the Agents page
    g = probe("agents-metrics")
    a = g["ag"]
    report(a["metricRuns"] not in ("", "-") and re.match(r"^\d+(\.\d+)?[KMB]?$", a["metricTokens"]) and a["metricCost"].startswith("est. $"), "agents page: runs, tokens and est. cost from agent-metrics.json", str((a["metricRuns"], a["metricTokens"], a["metricCost"])))
    report(a["openLink"] == 1, "agents page: a link to Time > Agents")
    report(a["awayRows"] == 8 and a["awaySummary"].startswith("11 gaps") and a["awayEmpty"] == 0, "agents page: away list from away.json (eight shown of eleven)", str((a["awayRows"], a["awaySummary"])))
    img = Img("agents-metrics-wide")
    report(img.count(is_amber, (208, 150, 1700, 1060)) > 30, "agents page: unanswered gaps are amber")
    layout("agents-metrics", g)
    gw = probe("agents-metrics-wide")["agPg"]
    report(not gw["out"], "agents page 1920x1080: no text runs outside the box it sits in", str(gw["out"][:3]))
    report(all(c["x"] + c["w"] <= gw["page"]["x"] + gw["page"]["w"] for c in gw["cols"]), "agents page 1920x1080: no card leaves the page", str(gw["cols"]))
    p2 = probe("agents-metrics-none")["ag"]
    report(p2["metricTokens"] == "-" and p2["metricCost"] == "n/a" and p2["awayRows"] == 0 and p2["awayEmpty"] == 1, "agents page: no files says so, not zeros", str((p2["metricTokens"], p2["awayEmpty"])))
    p3 = probe("agents-metrics-partial")["ag"]
    report(p3["metricCost"] == "n/a" and p3["awayRows"] == 0 and p3["awayEmpty"] == 1, "agents page: null cost reads n/a, an empty away list says so", str((p3["metricCost"], p3["awayEmpty"])))
    kx = probe("keys-agents-time")
    report(kx["k"]["page"] == "time" and kx["k"]["timeTab"] == "Agents" and kx["k"]["pane"] == "list", "agents page: t opens Time > Agents", str((kx["k"]["page"], kx["k"]["timeTab"])))


def check_time_tabs():
    """Each Time sub-tab against the metrics fixture (tests/cc-ui.sh gives every time scene one)."""
    w = probe("time-week")
    m = w["tm"]
    texts = w["timePg"]["texts"]
    report(w["time"]["week"] == 1 and w["time"]["today"] == 0 and m["state"] == "ok", "time Week: sub-tab shows, metrics.json read", str((w["time"], m["state"])))
    report(m["weekChart"] == 1 and m["weekBars"] == 4 and m["targetLine"] == 1, "time Week: a bar for each of the four days so far and the target line", str((m["weekBars"], m["targetLine"])))
    report(m["kpi"] == 4 and m["deltas"] >= 3, "time Week: four headline cards, each with a change and its arrow", str((m["kpi"], m["deltas"])))
    report("27 Oct to 2 Nov" in " ".join(texts), "time Week: the week is named", str(texts[:6]))
    report("target 8:00" in texts, "time Week: the target line says 8:00", str(texts))
    report(len(w["timeTabs"]) == 10 and [t["t"] for t in w["timeTabs"] if t["on"]] == ["Week"], "time Week: ten sub-tabs, Week active")
    d = probe("time-days")
    report(d["tm"]["dayRows"] >= 12 and "Thu 30 Oct" in d["timePg"]["texts"] and d["tm"]["dayDetail"] == 0, "time Days: a row per day, newest first, no detail until Enter", str((d["tm"]["dayRows"], d["tm"]["dayDetail"])))
    report(d["time"]["noData"] == 0 and d["tm"]["sparks"] >= 12, "time Days: no empty note, a sparkline on each row", str(d["tm"]["sparks"]))
    h = probe("time-heat")
    report(h["tm"]["cells"] >= 100 and h["time"]["heat"] == 1, "time Heatmap: the grid draws a cell per day", str(h["tm"]["cells"]))
    ht = " ".join(h["timePg"]["texts"])
    report("Oct 2025" in ht and "WEEK BY WEEK" in ht and "STREAKS" in ht and "PUNCTUALITY" in ht and "TRENDS" in ht, "time Heatmap: monthly totals, weekly totals, trends, streaks and punctuality", ht[:200])
    report("Thu 30 Oct" in h["tm"]["readout"], "time Heatmap: the cursor starts on today", h["tm"]["readout"])
    z = probe("time-focus")
    report(z["tm"]["zoneRank"] == 1 and z["tm"]["zoneWeeks"] == 1 and z["tm"]["zoneDays"] == 1 and "Docs" in z["timePg"]["texts"], "time Focus zones: ranking, twelve weeks, fourteen days", str(z["timePg"]["texts"][:8]))
    p = probe("time-progress")
    report(p["tm"]["kpi"] == 19 and p["tm"]["sparks"] >= 17, "time Progress: a card for each of 19 KPIs with a sparkline", str((p["tm"]["kpi"], p["tm"]["sparks"])))
    report("32:54" in p["tm"]["kpiValues"] and "no data" not in p["tm"]["kpiValues"], "time Progress: worked this week", str(p["tm"]["kpiValues"][:4]))
    report("3 of 4 days" in p["ag"]["kpiNotes"], "time Progress: screen time says how many days it covers", str(p["ag"]["kpiNotes"]))
    report("This week, 3 of 4 days" in probe("time-screen")["timePg"]["texts"], "time Screen and health: this week says 3 of 4 days", str([t for t in probe("time-screen")["timePg"]["texts"] if "week" in t.lower()]))
    r = probe("time-report")
    tx = r["timePg"]["texts"]
    first = next((i for i, t in enumerate(tx) if t.startswith("Time report:")), 0)
    last = tx.index("Copy") if "Copy" in tx else len(tx)
    rt = " ".join(tx[first:last])
    report("Time report: this week" in rt and "Worked 32:54" in rt and "Top projects" in rt, "time Report: the week written from the numbers", rt[:240])
    report(not re.search(r"screen|health", rt, re.I), "time Report: no screen time or health in the report", rt[:240])
    sc = probe("time-screen")
    report(sc["tm"]["screenCard"] == 1 and sc["tm"]["healthCard"] == 1 and "private" in sc["timePg"]["texts"], "time Screen and health: both halves, marked private", str(sc["timePg"]["texts"][:6]))
    rm = probe("time-reminders")
    report(rm["tm"]["remRows"] == 6 and "Asr" in rm["timePg"]["texts"], "time Reminders: four due, two scheduled, the next prayer", str((rm["tm"]["remRows"], rm["timePg"]["texts"][:4])))
    # empty states say which source is missing
    e = probe("time-nofile-week")
    report(any("metrics.json" in t for t in e["tm"]["noData"]) and e["tm"]["weekBars"] == 0 and e["tm"]["weekScrolls"] == 2, "time Week: no metrics.json says so and keeps the activity lists", str(e["tm"]["noData"]))
    e = probe("time-empty-days")
    report(e["tm"]["noData"] and "work.db" in e["tm"]["noData"][0] and "could not be opened" in e["tm"]["noData"][0], "time Days: an empty file names work.db and the daemon's reason", str(e["tm"]["noData"]))
    e = probe("time-partial-screen")
    nd = " ".join(e["tm"]["noData"])
    report(len(e["tm"]["noData"]) == 2 and "ActivityWatch on localhost:5600" in nd and "private.db" in nd and "ActivityWatch is not running." in nd and "No health log yet." in nd, "time Screen and health: each half names its own source", nd)
    e = probe("time-partial-zones")
    report(e["tm"]["zoneRank"] == 0 and any("focus log" in t and "has no rows." in t for t in e["tm"]["noData"]), "time Focus zones: a missing focus log is named", str(e["tm"]["noData"]))
    e = probe("time-partial-reminders")
    report(any("Taskwarrior" in t and "Task is not installed." in t for t in e["tm"]["noData"]), "time Reminders: a missing task list is named", str(e["tm"]["noData"]))
    # keyboard: the day opens, rings show
    e = probe("time-days-detail")
    report(e["tm"]["dayDetail"] == 1 and e["k"]["pane"] == "detail" and any(k.startswith("pane:") for k in e["k"]["ringKinds"]), "time Days: Enter opens the day with a pane ring", str((e["tm"]["dayDetail"], e["k"]["ringKinds"])))
    e = probe("time-heat-keys")
    report("Wed 29 Oct" in e["tm"]["readout"] and any(k.startswith("element:") for k in e["k"]["ringKinds"]), "time Heatmap: k moves the cursor one day up, with an element ring", str((e["tm"]["readout"], e["k"]["ringKinds"])))
    e = probe("time-report-save")
    report("Could not write" in e["tm"]["report"] or "Saved to" in e["tm"]["report"], "time Report: Enter says whether the file was written", e["tm"]["report"])


def check_time():
    p = probe("time")
    layout("time", p)
    report(p["time"]["today"] == 1 and p["time"]["week"] == 0 and p["time"]["noData"] == 0, "time: Today sub-tab shows its grid", str(p["time"]))
    report(p["stats"][:3] == ["1:00", "31:20", "118:03"], "time: day, week and month from the files", str(p["stats"]))
    report(len(p["timeTabs"]) == 10 and [t["t"] for t in p["timeTabs"] if t["on"]] == ["Today"], "time: ten sub-tabs, Today active")
    report(p["time"]["bar"] is not None and p["time"]["bar"]["w"] > 400, "time: the Today bar spans its card", str(p["time"]["bar"]))
    report(p["time"]["whereRows"] == 1, "time: Where time went card present")
    bar, card, segs = p["time"]["bar"], p["time"]["card"], p["time"]["barSegs"]
    report(bar and card and bar["x"] >= card["x"] and bar["x"] + bar["w"] <= card["x"] + card["w"], "time: the Today bar sits inside its card", str((bar, card)))
    report(segs and segs[-1]["x"] + segs[-1]["w"] == bar["w"] and all(a["x"] + a["w"] <= b["x"] for a, b in zip(segs, segs[1:])),
           "time: Today segments sum to the bar exactly, no overlap", str(segs))
    report(p["time"]["page"] and not p["time"]["page"]["flick"], "time: the page itself is not a Flickable", str(p["time"]["page"]))
    report(sorted(p["time"]["flicks"]) == ["doneScroll", "whereScroll"], "time: only the Where time went and Done today lists scroll", str(p["time"]["flicks"]))
    check_time_tabs()
    report(Img("time").count(is_green) == 0, "time: no green")
    for tag in ("time-heat", "time-week", "time-progress", "time-zones", "time-screen"):
        if os.path.exists(os.path.join(OUT, tag + ".png")):
            report(Img(tag).count(is_green) == 0, "%s: no green" % tag)


def check_argv(name, tag, want):
    got = sorted(execs(tag))
    want = sorted(want)
    report(got == want, name, "got %s want %s" % (got, want))


HYPR_FOCUS = ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "class:^(zen-beta|zen|firefox|librewolf|chromium|google-chrome|brave-browser)$" })']


def check_extra():
    p = probe("filter-mail")
    report(ids(p) == ["m1"] and [c["t"] for c in p["chips"] if c["on"]] == ["Mail"], "Mail filter shows the mail item", str(ids(p)))
    p = probe("filter-slack")
    report(sorted(ids(p)) == ["a2", "c1"], "Slack filter shows only Slack, not the alert-channel post", str(ids(p)))
    p = probe("filter-alert")
    report(sorted(ids(p)) == ["a3", "s1"], "Alert filter shows alerts and the Slack alert-channel post", str(ids(p)))
    p = probe("queue-extra")
    names = [s["text"] for s in p["sections"]]
    report(names[-2:] == ["FROM YESTERDAY", "PREVIOUS PENDING REVIEWS"], "previous reviews get their own last section", str(names))
    report(ids(p, "PREVIOUS PENDING REVIEWS") == ["p1"], "the previous review sits in it", str(ids(p, "PREVIOUS PENDING REVIEWS")))
    p = probe("agents-extra")
    report("TASK-2026-00111" in p["agentFor"], "agents: For carries the ticket ref", str(p["agentFor"]))
    report("verify the inventory keys" in p["agentWork"] and "tidy the chart values" in p["agentWork"], "agents: Working on is filled", str(p["agentWork"]))
    report(sum(1 for j in p["agentJump"] if not j["blocked"]) >= 4, "agents: session and queue rows can jump", str(p["agentJump"]))


def check_agent_jump():
    e = execs("act-agent-jump")
    p = probe("act-agent-jump")
    report(len(e) == 1 and e[0][0] == "dots-jump" and e[0][1] == "TASK-2026-00111", "agent row jump execs dots-jump once", str(e))
    report(p["ccOpen"] is False, "agent row jump closes the control centre", str(p["ccOpen"]))


def check_argv_local():
    check_argv("local actions exec the exact argv (Open pane, Open review, Break down)", "act-local",
               [["dots-jump", "INFRA-88"], ["xdg-open", "https://example.invalid/b1"], HYPR_FOCUS,
                ["dots-overview", "breakdown", "gh:acme/charts#2291", "--start"]])


def check_argv_stub():
    e = execs("act-stub")
    p = probe("act-stub")
    report(e == [], "read-only stubs exec nothing", str(e))
    report(p["hidden"] == "" and p["status"] == "Nothing else is waiting on you past these.", "read-only stubs change nothing", p["status"])


def check_hide():
    p = probe("act-hide")
    report(p["hidden"] == "b1" and len(p["rows"]) == 8 and "b1" not in ids(p), "Queue hides the item for this session", p["hidden"])
    report(p["status"] == "Queued. Hidden for this session." and p["undo"], "Queue says so and offers Undo", p["status"])
    report(p["sel"] == "m1", "selection moves to the row that followed", p["sel"])
    report(execs("act-hide") == [], "Queue execs nothing")
    report(p["navTabs"][0] == "Queue:8*", "Queue count drops", str(p["navTabs"]))


def check_undo():
    p = probe("act-undo")
    report(p["hidden"] == "" and len(p["rows"]) == 9 and p["sel"] == "b1" and p["status"] == "Back on the list." and not p["undo"],
           "Undo puts the item back and selects it", p["status"])


def check_snooze():
    p = probe("act-snooze")
    report(p["hidden"] == "a3" and p["status"] == "Snoozed: tonight. It stays listed under Snoozed.", "Snooze hides and says where it went", p["status"])
    report(len(p["rows"]) == 8 and p["navTabs"][0] == "Queue:8*", "Snooze drops the count")


def check_argv_meta():
    ref = 'HD-7; touch "$PWN" `id` $(id) #'
    check_argv("a ref full of shell metacharacters reaches the program as one argument", "act-meta",
               [["dots-overview", "breakdown", ref, "--start"], ["dots-jump", ref]])


def check_back():
    p = probe("act-back")
    report(p["closes"] == 1, "Back to task asks to close (Ui.toggleCc)", str(p["closes"]))


# ---- keyboard: key sequences through CcView.handle, no mouse -------------------------------
def kp(tag):
    return probe(tag)["k"]


def check_keys():
    base = probe("queue")
    report(base["k"]["rings"] == 0 and not base["k"]["keyboard"], "keys: no focus ring before any key press", str(base["k"]["rings"]))
    p = probe("keys-digits")
    report(p["tab"] == "inbox" and p["k"]["page"] == "inbox" and p["k"]["pane"] == "list", "keys: 2 goes to Inbox", str(p["tab"]))
    for tag, tab in (("keys-tab-agents", "agents"), ("keys-tab-tasks", "work"), ("keys-tab-time", "time")):
        p = probe(tag)
        report(p["tab"] == tab, "keys: digit opens " + tab, p["tab"])
    report(probe("keys-tab-time")["k"]["pane"] == "tabs", "keys: Time opens on its sub-tab strip")
    p = probe("keys-move")
    report(p["sel"] == "a2" and p["k"]["keyboard"], "keys: j j moves to the third row", p["sel"])
    report(probe("keys-ne")["sel"] == "a3", "keys: n moves down, e up (n n e)", probe("keys-ne")["sel"])
    report(probe("keys-bottom")["sel"] == "d1", "keys: G jumps to the last row", probe("keys-bottom")["sel"])
    report(probe("keys-gg")["sel"] == "a1", "keys: g g jumps back to the top", probe("keys-gg")["sel"])
    report(kp("keys-g")["pending"] == "g" and probe("keys-g")["sel"] == "a1", "keys: a lone g waits for the second")
    report(probe("keys-page")["sel"] == "d1", "keys: Ctrl+d pages down", probe("keys-page")["sel"])
    p = probe("keys-detail")
    report(p["k"]["zone"] == "detail" and p["k"]["pane"] == "detail", "keys: Enter on a row focuses the detail", p["k"]["zone"])
    report("pane:1:0" in p["k"]["ringKinds"] and "element:2:2" in p["k"]["ringKinds"],
           "keys: detail shows the pane hairline and the primary-button ring (accent, 1 px and 2 px / 2 px)", str(p["k"]["ringKinds"]))
    p = probe("keys-tab-pane")
    report(p["k"]["zone"] == "detail", "keys: Tab moves list to detail", p["k"]["zone"])
    p = probe("keys-detail-back")
    report(p["k"]["zone"] == "list" and p["closes"] == 0, "keys: h goes back to the list", p["k"]["zone"])
    p = probe("keys-esc-detail")
    report(p["k"]["zone"] == "list" and p["closes"] == 0, "keys: Esc in the detail returns to the list, not out", p["k"]["zone"])
    report(probe("keys-esc-close")["closes"] == 1, "keys: Esc on the list leaves the control centre")
    p = probe("keys-ring")
    report(p["k"]["rings"] >= 2 and "pane:1:0" in p["k"]["ringKinds"] and "element:2:2" in p["k"]["ringKinds"],
           "keys: a key press shows the focused row ring and the list pane border", str(p["k"]["ringKinds"]))
    report(Img("keys-ring").count(is_green) == 0, "keys: the focus ring is never green")
    p = probe("keys-snooze")
    report(p["hidden"] == "a3" and p["status"] == "Snoozed: tonight. It stays listed under Snoozed.",
           "keys: Enter s 3 snoozes the row until tonight", p["status"])
    p = probe("keys-snooze-nav")
    report(p["hidden"] == "a1" and p["status"].startswith("Snoozed: tonight") and p["k"]["snooze"] == 2, "keys: j j Enter picks the highlighted snooze option (Tonight)", p["status"])
    report(probe("keys-snooze-open")["k"]["zone"] == "panel" and probe("keys-snooze-open")["k"]["mode"] == "snooze", "keys: s opens the snooze panel")
    p = probe("keys-snooze-esc")
    report(p["k"]["mode"] == "" and p["hidden"] == "" and p["k"]["zone"] == "detail", "keys: Esc closes the snooze panel and keeps the row")
    p = probe("keys-reply")
    report(p["k"]["mode"] == "reply" and p["k"]["zone"] == "panel" and p["compose"]["reply"], "keys: r opens the reply panel (a draft, nothing sent)")
    p = probe("keys-reply-submit")
    report(p["status"].startswith("Sending stays off") and execs("keys-reply-submit") == [], "keys: Ctrl+Enter in a draft sends nothing", p["status"])
    p = probe("keys-reply-esc")
    report(p["k"]["mode"] == "" and p["k"]["zone"] == "detail", "keys: Esc closes the reply panel")
    p = probe("keys-filter")
    report(p["k"]["filter"] == "mail" and p["k"]["zone"] == "list" and [r["id"] for r in p["rows"]] == ["m1"] and p["k"]["filterBar"],
           "keys: / types a filter, Enter keeps it and leaves the field", str([r["id"] for r in p["rows"]]))
    p = probe("keys-filter-typing")
    report(p["k"]["zone"] == "filter" and p["k"]["filter"] == "jg" and p["tab"] == "queue",
           "keys: in the filter field every key types (j g stay text, no row moved)", p["k"]["filter"])
    p = probe("keys-filter-esc")
    report(p["k"]["filter"] == "mail" and p["k"]["zone"] == "list" and len(p["rows"]) == 1, "keys: Esc leaves the field and keeps the text")
    p = probe("keys-filter-clear")
    report(p["k"]["filter"] == "" and len(p["rows"]) == 9 and p["closes"] == 0, "keys: a second Esc clears the filter, not the control centre")
    p = probe("keys-filter-ctrlu")
    report(p["k"]["filter"] == "" and p["k"]["zone"] == "list", "keys: Ctrl+u clears the filter")
    p = probe("keys-help")
    rows = " ".join(p["k"]["helpRows"])
    report(p["k"]["help"] and p["k"]["zone"] == "help", "keys: ? opens the help overlay")
    for key, label in (("a", "Allow once"), ("d", "Deny"), ("o", "Open pane"), ("s", "Snooze"), ("b", "Break down and start"), ("j", "Jump to source")):
        report((key + "|" + label) in p["k"]["helpRows"], "keys: help lists %s %s on the Queue page" % (key, label), rows[:200])
    report("1 2 3 4 5|Queue, Inbox, Agents, Tasks, Time" in p["k"]["helpRows"] and "/|Filter" in p["k"]["helpRows"], "keys: help lists the global keys")
    p = probe("keys-help-swallow")
    report(p["k"]["help"] and p["tab"] == "queue" and p["sel"] == "a1", "keys: help swallows other keys (3 and j do nothing)")
    p = probe("keys-help-esc")
    report(not p["k"]["help"] and p["closes"] == 0, "keys: Esc closes help only")
    p = probe("keys-chip")
    report(p["k"]["src"] == "Slack" and p["k"]["chipFocus"] and [c["t"] for c in p["chips"] if c["on"]] == ["Slack"], "keys: ] ] moves the source chip to Slack", p["k"]["src"])
    p = probe("keys-chip-back")
    report(p["k"]["src"] == "Agent", "keys: [ steps the chip back")
    p = probe("keys-agent-open")
    report(p["ccOpen"] is False and [e[0] for e in execs("keys-agent-open")] == ["dots-jump"], "keys: Enter then o on an agent item runs dots-jump", str(execs("keys-agent-open")))
    p = probe("keys-stub")
    report(p["k"]["mode"] == "" and "read-only" in p["status"] and execs("keys-stub") == [], "keys: a stub key (Allow once) says so and runs nothing", p["status"])
    p = probe("keys-agents-page")
    report(p["tab"] == "agents" and p["k"]["agent"] == 2, "keys: Agents page moves a row cursor (j j)", str(p["k"]["agent"]))
    report([e[0] for e in execs("keys-agents-open")] == ["dots-jump"] and probe("keys-agents-open")["k"]["agent"] == 2, "keys: Agents o opens the pane of the focused row")
    p = probe("keys-agents-filter")
    report(p["k"]["agentsShown"] == 1 and p["agentRows"] == 1, "keys: / filters the Agents page", str(p["k"]["agentsShown"]))
    p = probe("keys-tasks")
    report(p["tab"] == "work" and p["k"]["taskView"] == "Board", "keys: ] switches Tasks to Board", p["k"]["taskView"])
    p = probe("keys-tasks-move")
    report(p["k"]["task"] == 2 and p["k"]["taskView"] == "All", "keys: Tasks: ] ] is All, j j moves the cursor", str(p["k"]["task"]))
    p = probe("keys-tasks-break")
    report([e[:2] for e in execs("keys-tasks-break")] == [["dots-overview", "breakdown"]], "keys: Tasks b breaks the focused task down (one argv)", str(execs("keys-tasks-break")))
    p = probe("keys-tasks-filter")
    report(p["k"]["tasksShown"] == 1, "keys: / filters the Tasks page", str(p["k"]["tasksShown"]))
    p = probe("keys-time-sub")
    report(p["k"]["timeTab"] == "Week" and p["k"]["page"] == "time", "keys: Time: ] moves to the Week sub-tab", p["k"]["timeTab"])
    p = probe("keys-time-strip")
    report(p["k"]["pane"] == "tabs" and p["k"]["timeTab"] == "Days", "keys: Time strip: l l goes Today, Week, Days", p["k"]["timeTab"])
    p = probe("keys-time-help")
    report(p["k"]["help"] and "p  P|Where time went: next, previous grouping" in p["k"]["helpRows"], "keys: Time help lists the sub-tab and period keys")
    p = probe("keys-hint")
    report(p["k"]["hint"].startswith("j k move") and "? help" in p["k"]["hint"], "keys: the footer hint follows the page", p["k"]["hint"])
    p = probe("keys-inbox")
    report(p["tab"] == "inbox" and p["k"]["zone"] == "detail", "keys: Inbox rows open into the detail pane with Enter", p["k"]["zone"])
    check_keys_reach()


# every control that used to need the mouse, and the Time page driven by keys alone
def check_keys_reach():
    ELEM = "element:2:2"
    p = probe("keys-undo")
    report(p["hidden"] == "" and p["k"]["status"] == "Back on the list.", "keys: u undoes the last done", p["k"]["status"])
    report(probe("keys-undo-none")["k"]["status"] == "Nothing to undo.", "keys: u with nothing to undo says so")
    p = probe("keys-view")
    report(p["k"]["view"] == "Overdue" and p["k"]["viewFocus"] and ELEM in p["k"]["ringKinds"], "keys: } } picks the Overdue saved view and rings it", str((p["k"]["view"], p["k"]["ringKinds"])))
    report(probe("keys-view-back")["k"]["view"] == "VIPs" or probe("keys-view-back")["k"]["view"] == "", "keys: { steps the saved view back", probe("keys-view-back")["k"]["view"])
    p = probe("keys-group")
    report(p["k"]["group"] == "Source" and [g["t"] for g in p["groups"] if g["on"]] == ["Source"] and p["k"]["groupFocus"] and ELEM in p["k"]["ringKinds"],
           "keys: = steps Group by to Source and rings it", str((p["k"]["group"], p["k"]["ringKinds"])))
    report(probe("keys-group-wrap")["k"]["group"] == "Urgency", "keys: = = = wraps Group by back to Urgency", probe("keys-group-wrap")["k"]["group"])
    p = probe("keys-grant")
    report(p["k"]["mode"] == "agent" and p["k"]["grant"] is False and "No reply" in p["k"]["status"], "keys: Ctrl+g in the agent panel turns the grant off", str((p["k"]["grant"], p["k"]["status"])))
    report(probe("keys-grant-twice")["k"]["grant"] is True, "keys: Ctrl+g twice turns the grant back on")
    # Time
    p = probe("keys-time-esc")
    report(p["k"]["pane"] == "tabs" and p["closes"] == 0, "keys: Time: Esc in the body returns to the sub-tab strip, not out", str((p["k"]["pane"], p["closes"])))
    report(probe("keys-time-esc-out")["closes"] == 1, "keys: Time: Esc on the strip leaves the control centre")
    p = probe("keys-time-ring")
    report(p["k"]["timeTab"] == "Week" and ELEM in p["k"]["ringKinds"], "keys: Time: l on the strip moves the sub-tab and rings it", str(p["k"]["ringKinds"]))
    p = probe("keys-time-body")
    report(p["k"]["zone"] == "list" and "pane:1:0" in p["k"]["ringKinds"], "keys: Time: Tab into the body draws the pane hairline", str(p["k"]["ringKinds"]))
    report("Esc tabs" in p["k"]["hint"] and "p P period" not in probe("keys-time-ring")["k"]["hint"], "keys: Time hints are true (Esc tabs in the body, no period on the strip)", p["k"]["hint"])
    report(probe("keys-time-today-by")["k"]["timeBy"] == "Agent", "keys: Time Today: p steps Where time went to Agent", probe("keys-time-today-by")["k"]["timeBy"])
    report(probe("keys-time-today-by-back")["k"]["timeBy"] == "Project", "keys: Time Today: P steps it back to Project", probe("keys-time-today-by-back")["k"]["timeBy"])
    e = execs("keys-time-focus")
    report(len(e) == 1 and e[0][:2] == ["dots-overview", "focus"] and e[0][2] in ("start", "stop"), "keys: Time Today: s starts or stops focus (one argv)", str(e))
    report([x[:3] for x in execs("keys-time-break")] == [["dots-overview", "focus", "break"]], "keys: Time Today: b takes a break (one argv)", str(execs("keys-time-break")))
    p = probe("keys-time-week")
    report(p["k"]["tks"]["col"] == 5 and p["k"]["tks"]["weekOff"] == -1, "keys: Time Week: l l P moves two days on from Thursday and back one week", str(p["k"]["tks"]))
    report(probe("keys-time-week-rows")["k"]["tks"]["row"] == 2, "keys: Time Week: j j moves down the zone legend", str(probe("keys-time-week-rows")["k"]["tks"]))
    p = probe("keys-time-days")
    report(p["k"]["tks"]["row"] == 2 and p["k"]["tks"]["detail"] and p["k"]["pane"] == "detail", "keys: Time Days: j j Enter opens the third day", str((p["k"]["tks"], p["k"]["pane"])))
    p = probe("keys-time-days-back")
    report(not p["k"]["tks"]["detail"] and p["k"]["pane"] == "list" and p["closes"] == 0, "keys: Time Days: Esc closes the day detail, not the control centre", str((p["k"]["tks"], p["k"]["pane"])))
    p = probe("keys-time-heat")
    report(p["k"]["timeTab"] == "Days" and p["k"]["tks"]["detail"], "keys: Time Heatmap: Enter opens that day on Days", str((p["k"]["timeTab"], p["k"]["tks"])))
    p = probe("keys-time-zones")
    report(p["k"]["tks"]["period"] == 2 and p["k"]["tks"]["row"] == 1, "keys: Time Focus zones: j p moves a zone and switches to the month window", str(p["k"]["tks"]))
    p = probe("keys-time-progress")
    report(p["k"]["tks"]["period"] == 2 and p["k"]["tks"]["col"] == 1 and p["k"]["tks"]["row"] == 1, "keys: Time Progress: l j p moves a card and steps the period", str(p["k"]["tks"]))
    p = probe("keys-time-report")
    report(p["k"]["tks"]["period"] == 2 and execs("keys-time-report") == [], "keys: Time Report: p P c change the period and copy locally (no exec, no network)", str(p["k"]["tks"]))
    report(probe("keys-time-reminders")["k"]["rem"] == 1, "keys: Time Reminders: d hides the first row for this session", str(probe("keys-time-reminders")["k"]["rem"]))
    report(probe("keys-time-reminders-snooze")["k"]["rem"] == 1, "keys: Time Reminders: j s hides the second row", str(probe("keys-time-reminders-snooze")["k"]["rem"]))


CHECKS = {
    "queue": check_queue, "groups": check_groups, "inbox": check_inbox, "compose": check_compose, "empty": check_empty,
    "agents-time": check_agents_time, "extra": check_extra, "agent-jump": check_agent_jump, "stale": check_stale, "agents": check_agents, "work": check_work, "work-layout": check_work_layout, "time-layout": check_time_layout, "time": check_time,
    "argv-local": check_argv_local, "argv-stub": check_argv_stub, "hide": check_hide, "undo": check_undo,
    "keys": check_keys, "snooze": check_snooze, "argv-meta": check_argv_meta, "back": check_back,
}

if __name__ == "__main__":
    name, OUT = sys.argv[1], sys.argv[2]
    try:
        CHECKS[name]()
    except Exception as e:  # a missing probe or png is a failure, not a crash
        report(False, name, "%s: %s" % (type(e).__name__, e))
    sys.exit(1 if failures else 0)
