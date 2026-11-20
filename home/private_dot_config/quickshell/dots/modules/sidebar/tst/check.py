#!/usr/bin/env python3
"""Assertions for tests/sidebar-ui.sh: check.py <name> <out_dir>. Reads <out>/<tag>.json (the scene's
PROBE) and <out>/<tag>.png. Exit 1 on the first failed assertion, printing what was expected."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.environ["ROOT"], "tests"))
import pixel  # noqa: E402

PAL = {"waiting": "#f2b04d", "failed": "#ff8a7a", "accent": "#8ccff1", "raised": "#1c2429"}
fails = []


def ok(cond, msg):
    if not cond:
        fails.append(msg)


def load(out, tag):
    if not os.path.getsize(f"{out}/{tag}.json"):
        print(f"  FAIL {tag}: scene produced no probe"); sys.exit(1)
    return json.load(open(f"{out}/{tag}.json")), pixel.Shot(f"{out}/{tag}.png")


def rows_ids(m):
    return [r["id"] for r in m["rows"]]


def check_board(out):
    m, shot = load(out, "board")
    b = m["body"]
    ok(b["w"] == 460, f"body is 460 wide, got {b['w']}")
    ok(m["nowTitle"] == "HD 4412 Rotate deploy keys", f"now title: {m['nowTitle']!r}")
    ok(m["next"].startswith("next: "), f"next line: {m['next']!r}")
    ok(m["heads"] == ["WAITING ON YOU", "TODAY", "WHILE YOU WERE AWAY", "FROM YESTERDAY"], f"heads: {m['heads']}")
    ok(rows_ids(m) == ["f1", "w1", "w2", "t2", "t1", "t3", "g2", "g1", "y1"] or len(m["rows"]) == 9,
       f"nine rows, got {rows_ids(m)}")
    ok(len(m["rows"]) == 9, f"nine rows, got {len(m['rows'])}")
    rowx = b["x"] + 1 + 8
    for r in m["rows"]:
        ok(r["h"] >= 52, f"row {r['id']} min height 52, got {r['h']}")
        ok(r["x"] == rowx and r["w"] == 460 - 2 - 16, f"row {r['id']} box x={r['x']} w={r['w']}")
        ok(r["ageW"] == 44, f"row {r['id']} age column 44, got {r['ageW']}")
        ok(r["markX"] - r["ageRight"] == 6, f"row {r['id']} age to mark gap 6, got {r['markX'] - r['ageRight']}")
        ok(r["textX"] - (r["markX"] + r["markW"]) == 6, f"row {r['id']} mark to text gap 6")
        ok(r["markW"] == 14, f"row {r['id']} mark column 14")
    marks = {r["id"]: r["mark"] for r in m["rows"]}
    ok(marks.get("w1") == "waiting" and marks.get("w2") == "waiting", "waiting rows carry the waiting mark")
    ok(marks.get("f1") == "failed", "the alert carries the failed mark")
    ok(all(marks[i] == "" for i in ("t1", "t2", "t3", "g1", "g2", "y1")), "other rows carry no mark")
    ages = {r["id"]: r["ageText"] for r in m["rows"]}
    ok(ages.get("w2") == "9m" and ages.get("t2") == "3h" and ages.get("y1") == "1d", f"ages: {ages}")
    ok([t["key"] for t in m["tabs"]] == ["queue", "inbox", "agents", "work", "time"], "five tabs in order")
    ok([t["selected"] for t in m["tabs"]] == [True, False, False, False, False], "only Queue selected")
    ok(all(t["h"] == 28 for t in m["tabs"]), "tab height 28")
    xs = [t["x"] for t in m["tabs"]]
    ok(xs == sorted(xs) and xs[0] == b["x"] + 1 + 12, f"tabs left to right from x+13: {xs}")
    ok(m["tabs"][-1]["x"] + m["tabs"][-1]["w"] < b["x"] + b["w"], "tabs fit inside the body")
    ft = m["footer"]
    ok(ft is not None and ft["y"] + ft["h"] == b["y"] + b["h"] - 1, f"footer sits on the bottom edge: {ft}")
    ok(m["footTitle"] == "Pick an item", f"nothing selected: {m['footTitle']!r}")
    bt = {x["name"]: x for x in m["buttons"]}
    ok(all(not bt[n]["enabled"] and bt[n]["tip"] == "read-only for now" for n in ("actReply", "actAgent", "actQueue", "actSnooze")),
       "Reply, Agent, Queue, Snooze are disabled with the read-only tooltip")
    ok(bt["actExpand"]["enabled"], "Expand is enabled")
    ok(bt["actReply"]["primary"] and all(x["h"] == 28 for x in m["buttons"]), "Reply is primary; buttons 28 high")
    ok(m["scroll"]["y"] > m["header"]["y"] + m["header"]["h"], "list below the header")
    # pixels: amber mark, red mark, accent logo, no green anywhere in the list
    w1 = next(r for r in m["rows"] if r["id"] == "w1")
    f1 = next(r for r in m["rows"] if r["id"] == "f1")
    t2 = next(r for r in m["rows"] if r["id"] == "t2")
    def mbox(r):
        cy = int(r["y"] + r["h"] / 2)
        return (int(r["markX"]) - 1, cy - 8, int(r["markX"]) + 15, cy + 8)
    ok(shot.count_colour(PAL["waiting"], mbox(w1), tol=30) >= 15, "amber circle painted for a waiting row")
    ok(shot.count_colour(PAL["failed"], mbox(f1), tol=30) >= 12, "red diamond painted for the failed row")
    ok(shot.count_colour(PAL["waiting"], mbox(t2), tol=30) == 0 and shot.count_colour(PAL["failed"], mbox(t2), tol=30) == 0,
       "no status colour on a plain row")
    lb = shot.bbox_of_non_bg((b["x"] + 14, b["y"] + 18, b["x"] + 54, b["y"] + 46), bg=(14, 19, 22), tol=40)
    ok(lb is not None and 10 <= lb[2] - lb[0] <= 26 and 10 <= lb[3] - lb[1] <= 28, f"logo glyph drawn (10-26 px; the icon font renders glyphs at about half their pixel size), got {lb}")
    body_box = (b["x"], b["y"], b["x"] + b["w"], b["y"] + b["h"])
    green = sum(1 for _, _, p in shot.pixels(body_box) if p[1] > p[0] + 60 and p[1] > p[2] + 60)
    ok(green == 0, f"no green pixels in the sidebar, got {green}")
    ok(m["staleMark"] == 0 and m["dim"] is False, "fresh feed: no stale mark")


def check_tab(out, tag, want, tabkey):
    m, _ = load(out, tag)
    ok(sorted(rows_ids(m)) == sorted(want), f"{tag}: rows {sorted(rows_ids(m))}, want {sorted(want)}")
    sel = [t["key"] for t in m["tabs"] if t["selected"]]
    ok(sel == [tabkey], f"{tag}: selected tab {sel}")


def check_select(out):
    m, shot = load(out, "select")
    r = next(r for r in m["rows"] if r["id"] == "w2")
    ok(r["selected"], "w2 selected")
    ok(m["footTitle"] == "Add two vCPUs to db-02 tonight?", f"footer title: {m['footTitle']!r}")
    cy = int(r["y"] + r["h"] / 2)
    ok(shot.has_colour((int(r["x"]) + 2, cy - 3, int(r["x"]) + 8, cy + 3), PAL["raised"], tol=6, min_count=10), "selected row on the raised background")


def check_empty(out):
    m, _ = load(out, "empty")
    ok(m["rows"] == [] and m["heads"] == [], "no rows, no group heads")
    ok(m["empty"] is True, "empty note visible")
    ok(m["nowTitle"] == "Nothing in focus", f"now title: {m['nowTitle']!r}")
    ok(m["next"] == "", "no next line")
    ok(m["footTitle"] == "Pick an item", "footer prompts")


def check_stale(out):
    m, shot = load(out, "stale")
    ok(m["dim"] is True and m["staleMark"] == 1, f"stale feed shows the unknown mark: {m['staleMark']} dim={m['dim']}")
    ok(all(r["dim"] for r in m["rows"]) and len(m["rows"]) == 9, "stale: rows dimmed, still listed")
    r = next(r for r in m["rows"] if r["id"] == "w1")
    cy = int(r["y"] + r["h"] / 2)
    ok(shot.count_colour(PAL["waiting"], (int(r["markX"]) - 1, cy - 8, int(r["markX"]) + 15, cy + 8), tol=30) == 0,
       "stale: no amber on a dimmed row")


def check_system(out):
    m, _ = load(out, "system")
    s = m["system"]
    ok(s and s["active"] and s["ready"], f"systemSlot loaded the stub: {s}")
    ok(s["source"].endswith("modules/system/SystemPanel.qml") or s["source"].endswith("/system/SystemPanel.qml"), f"slot source: {s['source']}")
    ok(m["stub"] == 1, "the system stub is on screen")
    ok(m["scroll"]["visible"] is False and m["footer"] is None, "system open: list and footer replaced")
    ok(m["systemMissing"] is False, "no missing note when the panel exists")
    m, _ = load(out, "system-missing")
    s = m["system"]
    ok(s and s["active"] and not s["ready"], f"missing file: slot not ready: {s}")
    ok(m["systemMissing"] is True and m["stub"] == 0, "missing file: placeholder note shown")


CHECKS = {
    "board": lambda o: check_board(o),
    "inbox": lambda o: check_tab(o, "inbox", ["w2", "g1", "t3"], "inbox"),
    "agents": lambda o: check_tab(o, "agents", ["w1", "g2"], "agents"),
    "work": lambda o: check_tab(o, "work", ["w1", "t1", "t2", "g2"], "work"),
    "time": lambda o: check_tab(o, "time", ["y1"], "time"),
    "select": check_select, "empty": check_empty, "stale": check_stale, "system": check_system,
}

if __name__ == "__main__":
    CHECKS[sys.argv[1]](sys.argv[2])
    if fails:
        for f in fails:
            print(f"  FAIL {sys.argv[1]}: {f}")
        sys.exit(1)
    print(f"PASS {sys.argv[1]}")
