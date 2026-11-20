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
    report(p["navTabs"] == ["Queue:8*", "Inbox:6", "Agents:5", "Tasks:4", "Time:0"], "queue nav tabs and counts", str(p["navTabs"]))
    report(p["detail"] and p["detail"]["w"] == 500 and p["detail"]["x"] == 1100, "queue detail is 500 px at the right", str(p["detail"]))
    names = [s["text"] for s in p["sections"]]
    report(names == ["WAITING ON YOU", "TODAY", "WHILE YOU WERE AWAY", "FROM YESTERDAY"], "queue sections in board order", str(names))
    report(ids(p, "WAITING ON YOU") == ["a1", "a3", "a2"] and ids(p, "TODAY") == ["b2", "b1"]
           and ids(p, "WHILE YOU WERE AWAY") == ["c2", "c1"] and ids(p, "FROM YESTERDAY") == ["d1"],
           "queue rows land in the right sections, urgency first")
    report(len(p["rows"]) == 8 and all(r["h"] == 56 for r in p["rows"]), "queue 8 rows, 56 px each")
    report(non_overlap(p["rows"]) and non_overlap(p["sections"]), "queue rows and headings do not overlap")
    report(all(r["w"] == p["rows"][0]["w"] for r in p["rows"]), "queue rows share one width")
    cur = [r["id"] for r in p["rows"] if r["current"]]
    report(cur == ["a1"] and p["sel"] == "a1", "queue first row is selected", str(cur))
    marks = {r["id"]: r["mark"] for r in p["rows"]}
    report(marks == {"a1": True, "a3": True, "a2": True, "b2": False, "b1": False, "c2": False, "c1": False, "d1": False},
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
    report(sorted(names) == sorted(["AGENT", "ALERT", "SLACK", "ERP", "GITHUB", "YOU"]), "group by Source: one section per source", str(names))
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
    report(len(p["rows"]) == 6 and "a1" not in ids(p) and "c2" not in ids(p), "inbox is the queue without agent items", str(ids(p)))
    report(p["navTabs"][1] == "Inbox:6*", "inbox tab is current", str(p["navTabs"]))
    report(p["sel"] == "a3", "inbox selects its own first row", p["sel"])


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
    report(all(r["dim"] for r in p["rows"]) and len(p["rows"]) == 8, "stale feed: every row dims", "dim=%s" % [r["dim"] for r in p["rows"]])
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


def check_time():
    p = probe("time")
    layout("time", p)
    report(p["time"]["today"] == 1 and p["time"]["week"] == 0 and p["time"]["noData"] == 0, "time: Today sub-tab shows its grid", str(p["time"]))
    report(p["stats"][:3] == ["1:00", "31:20", "118:03"], "time: day, week and month from the files", str(p["stats"]))
    report(len(p["timeTabs"]) == 9 and [t["t"] for t in p["timeTabs"] if t["on"]] == ["Today"], "time: nine sub-tabs, Today active")
    report(p["time"]["bar"] is not None and p["time"]["bar"]["w"] > 400, "time: the Today bar spans its card", str(p["time"]["bar"]))
    report(p["time"]["whereRows"] == 1, "time: Where time went card present")
    w = probe("time-week")
    report(w["time"]["week"] == 1 and w["time"]["today"] == 0, "time: Week sub-tab")
    h = probe("time-heat")
    report(h["time"]["heat"] == 1 and h["heatCells"] >= 100, "time: Heatmap sub-tab draws its cells", str(h["heatCells"]))
    d = probe("time-days")
    report(d["time"]["noData"] == 1 and d["time"]["today"] == 0, "time: a sub-tab with no data says so")
    report(Img("time").count(is_green) == 0, "time: no green")
    report(Img("time-heat").count(is_green) == 0, "time heatmap: no green")


def check_argv(name, tag, want):
    got = sorted(execs(tag))
    want = sorted(want)
    report(got == want, name, "got %s want %s" % (got, want))


def check_argv_local():
    check_argv("local actions exec the exact argv (Open pane, Open review, Break down)", "act-local",
               [["dots-jump", "INFRA-88"], ["xdg-open", "https://example.invalid/b1"],
                ["dots-overview", "breakdown", "gh:acme/charts#2291", "--start"]])


def check_argv_stub():
    e = execs("act-stub")
    p = probe("act-stub")
    report(e == [], "read-only stubs exec nothing", str(e))
    report(p["hidden"] == "" and p["status"] == "Nothing else is waiting on you past these.", "read-only stubs change nothing", p["status"])


def check_hide():
    p = probe("act-hide")
    report(p["hidden"] == "b1" and len(p["rows"]) == 7 and "b1" not in ids(p), "Queue hides the item for this session", p["hidden"])
    report(p["status"] == "Queued. Hidden for this session." and p["undo"], "Queue says so and offers Undo", p["status"])
    report(p["sel"] == "c2", "selection moves to the row that followed", p["sel"])
    report(execs("act-hide") == [], "Queue execs nothing")
    report(p["navTabs"][0] == "Queue:7*", "Queue count drops", str(p["navTabs"]))


def check_undo():
    p = probe("act-undo")
    report(p["hidden"] == "" and len(p["rows"]) == 8 and p["sel"] == "b1" and p["status"] == "Back on the list." and not p["undo"],
           "Undo puts the item back and selects it", p["status"])


def check_snooze():
    p = probe("act-snooze")
    report(p["hidden"] == "a3" and p["status"] == "Snoozed: tonight. It stays listed under Snoozed.", "Snooze hides and says where it went", p["status"])
    report(len(p["rows"]) == 7 and p["navTabs"][0] == "Queue:7*", "Snooze drops the count")


def check_argv_meta():
    ref = 'HD-7; touch "$PWN" `id` $(id) #'
    check_argv("a ref full of shell metacharacters reaches the program as one argument", "act-meta",
               [["dots-overview", "breakdown", ref, "--start"], ["dots-jump", ref]])


def check_back():
    p = probe("act-back")
    report(p["closes"] == 1, "Back to task asks to close (Ui.toggleCc)", str(p["closes"]))


CHECKS = {
    "queue": check_queue, "groups": check_groups, "inbox": check_inbox, "compose": check_compose, "empty": check_empty,
    "stale": check_stale, "agents": check_agents, "work": check_work, "time": check_time,
    "argv-local": check_argv_local, "argv-stub": check_argv_stub, "hide": check_hide, "undo": check_undo,
    "snooze": check_snooze, "argv-meta": check_argv_meta, "back": check_back,
}

if __name__ == "__main__":
    name, OUT = sys.argv[1], sys.argv[2]
    try:
        CHECKS[name]()
    except Exception as e:  # a missing probe or png is a failure, not a crash
        report(False, name, "%s: %s" % (type(e).__name__, e))
    sys.exit(1 if failures else 0)
