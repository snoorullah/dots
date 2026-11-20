#!/usr/bin/env python3
"""Assertions on the bar scenes for tests/bar-ui.sh.

  check.py <out dir>      reads <out>/<state>.json (the PROBE of each scene) and <state>.png

Geometry and visibility probes first, then a few pixel probes on the PNG (status colours
exist where they should, and there is no green anywhere).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402

out = sys.argv[1]
fails = 0
GUTTER = 8
PILL = 40


def ok(msg):
    print("PASS " + msg)


def bad(msg):
    global fails
    fails += 1
    print("FAIL " + msg)


def check(cond, msg):
    ok(msg) if cond else bad(msg)


def load(name):
    p = os.path.join(out, name + ".json")
    return json.load(open(p)) if os.path.exists(p) else None


def vis(b):
    return bool(b) and b.get("visible") and b.get("w", 0) > 0


def count_near(img, rect, rgb, tol=48):
    w, h, _, _ = img
    x0, y0 = int(rect["x"]), int(rect["y"])
    n = 0
    for y in range(max(0, y0), min(h, y0 + int(rect["h"]))):
        for x in range(max(0, x0), min(w, x0 + int(rect["w"]))):
            p = pngio.pixel(img, x, y)
            if all(abs(p[i] - rgb[i]) <= tol for i in range(3)):
                n += 1
    return n


def greenish(img, rect):
    w, h, _, _ = img
    n = 0
    for y in range(int(rect["y"]), min(h, int(rect["y"] + rect["h"]))):
        for x in range(int(rect["x"]), min(w, int(rect["x"] + rect["w"]))):
            r, g, b = pngio.pixel(img, x, y)
            if g > r + 30 and g > b + 30:
                n += 1
    return n


AMBER = (0xF2, 0xB0, 0x4D)
RED = (0xFF, 0x8A, 0x7A)
ACCENT = (0x8C, 0xCF, 0xF1)

for name in ["quiet", "waiting", "detour", "failed", "hover", "stale", "paused", "overflow", "bare"]:
    m = load(name)
    if m is None:
        bad(name + ": no probe")
        continue
    W = m["stageW"]
    L, C, R = m["left"], m["centre"], m["right"]
    check(all(vis(p) and p["h"] == PILL for p in (L, C, R)), name + ": three pills, 40 high")
    check(L["x"] == GUTTER, name + ": left pill sits on the 8 px gutter")
    check(abs(R["x"] + R["w"] - (W - GUTTER)) < 1.0, name + ": right pill sits on the right gutter")
    check(abs(C["x"] + C["w"] / 2 - W / 2) < 1.5, name + ": centre pill is centred")
    check(L["x"] + L["w"] + 8 <= C["x"] and C["x"] + C["w"] + 8 <= R["x"], name + ": pills do not touch")
    check(L["y"] == C["y"] == R["y"], name + ": pills share one baseline")
    check(vis(m["logo"]) and m["logo"]["w"] == 30, name + ": logo disc is 30")
    check(len(m["profiles"]) == 7, name + ": seven profiles")
    check(m["clockText"] == "22:28", name + ": clock text")
    check(vis(m["clockChip"]), name + ": clock chip shown")
    check(vis(m["bell"]) and vis(m["bellDot"]), name + ": bell with a dot (and no count)")
    inside = all(m[k]["x"] >= R["x"] and m[k]["x"] + m[k]["w"] <= R["x"] + R["w"] + 0.5
                 for k in ("bell",) if m.get(k))
    check(inside, name + ": bell inside the right pill")

q = load("quiet")
if q:
    check(len(q["waits"]) == 0, "quiet: no waiting symbols")
    check(not vis(q["fault"]), "quiet: no fault chip")
    check(vis(q["music"]) and q["music"]["w"] == 270, "quiet: music block is 270 wide")
    check(q["eq"] and q["eq"]["bars"] == 36 and q["eq"]["w"] == 71, "quiet: equalizer is 36 bars, 71 wide")
    check(len(q["metrics"]) == 3, "quiet: three metrics")
    check(vis(q["logout"]), "quiet: logout chip")
    check(len(q["workspaces"]) == 3 and len(q["wsLogos"]) == 6, "quiet: three workspaces with six logos")
    check(q["wsNames"] == [True, False, False], "quiet: only the active workspace keeps its name")
    check(vis(q["detour"]) is False, "quiet: no detour chip")
    check(vis(q["salahChip"]), "quiet: prayer chip")
    check(not vis(q["tray"]), "quiet: no tray (zero width)")

w = load("waiting")
if w:
    check(len(w["waits"]) == 3, "waiting: three symbols")
    xs = [b["x"] for b in w["waits"]]
    check(xs == sorted(xs), "waiting: left to right, oldest first")
    check(not vis(w["waitMore"]), "waiting: no +n at three")
    check(all(vis(b) for b in w["waits"]), "waiting: every symbol has width")

d = load("detour")
if d:
    check(vis(d["detour"]), "detour: chip shown")
    check(len(d["waits"]) == 1, "detour: one waiting symbol")
    check(d["wsNames"][0] is True, "detour: active workspace named")

f = load("failed")
if f:
    check(vis(f["fault"]), "failed: fault chip shown")

h = load("hover")
if h:
    check(h["wsNames"] == [True, True, False], "hover: hovered workspace shows its name")

s = load("stale")
if s:
    check(vis(s["fault"]), "stale: hollow ? chip shown")

p = load("paused")
if p and q:
    check(p["eq"]["opacity"] < 1 and abs(p["eq"]["opacity"] - 0.55) < 0.01, "paused: equalizer dimmed to 0.55")

o = load("overflow")
if o:
    check(len(o["waits"]) == 3 and vis(o["waitMore"]), "overflow: three symbols and +n")

b = load("bare")
if b:
    check(not vis(b["music"]), "bare: no player, no music block")
    check(len(b["metrics"]) == 0, "bare: no metrics")
    check(vis(b["tray"]), "bare: tray chip shown with icons")
    check(not vis(b["logout"]), "bare: no logout chip")
    check(not vis(b["salahChip"]), "bare: no prayer chip when there is no data")

# the equalizer moves when playing and holds when paused (two scenes, two clock values)
a1, a2 = load("quiet-t1"), load("quiet-t2")
if a1 and a2:
    check(a1["eqHeights"] != a2["eqHeights"], "equalizer: heights change with time")
p1, p2 = load("paused-t1"), load("paused-t2")
if p1 and p2:
    check(p1["eqHeights"] == p2["eqHeights"], "equalizer: paused bars hold still")

# narrow screen: the three pills still do not collide (task text elides)
n = load("narrow")
if n:
    L, C, R = n["left"], n["centre"], n["right"]
    check(L["x"] + L["w"] < C["x"] and C["x"] + C["w"] < R["x"],
          "narrow 1600: pills keep apart (left %.0f centre %.0f-%.0f right %.0f)" % (L["x"] + L["w"], C["x"], C["x"] + C["w"], R["x"]))

# clicks: which popout each spot asks for, and where its notch points
def want(state, expect, label):
    m = load(state)
    if not m:
        bad(label + ": no probe")
        return
    got = [(e.get("name") or e["kind"]) for e in m["emitted"]]
    check(got == expect, "%s -> %s (got %s)" % (label, expect, got))
    for e in m["emitted"]:
        if e["kind"] == "toggle":
            check(0 < e["x"] < m["stageW"], label + ": notch x is on screen")


want("click-clock", ["calendar"], "click clock")
want("click-salah", ["salah"], "click salah")
want("click-agent", ["agent"], "click agent symbol")
want("click-wait2", ["waiting"], "click a waiting symbol")
want("click-bell", ["center"], "click bell")
want("click-logo", ["logo"], "click logo")
want("click-tray", ["tray"], "click tray")
want("click-metrics", ["system"], "click metrics")
want("click-fault", ["system"], "click fault chip")
want("click-music", ["media"], "click music")

# pixels
sh = {k: os.path.join(out, k + ".png") for k in ("quiet", "waiting", "failed", "stale", "detour")}
if all(os.path.exists(v) for v in sh.values()) and q and w and f:
    iq, iw, ifl = pngio.read(sh["quiet"]), pngio.read(sh["waiting"]), pngio.read(sh["failed"])
    check(count_near(iw, w["right"], AMBER) > 40, "pixels: waiting symbols are amber")
    check(count_near(iw, w["right"], RED) > 20, "pixels: the alert is red")
    check(count_near(iq, q["right"], AMBER) == 0, "pixels: quiet right pill has no amber")
    check(count_near(ifl, f["right"], RED) > 20, "pixels: failed chip is red")
    check(count_near(iq, q["right"], ACCENT) > 20, "pixels: XP and the bell dot use the accent")
    for nm, im, mm in (("quiet", iq, q), ("waiting", iw, w), ("failed", ifl, f)):
        total = sum(greenish(im, mm[k]) for k in ("left", "centre", "right"))
        check(total == 0, "pixels: no green in %s (%d)" % (nm, total))

print("bar scenes: %d failure(s)" % fails)
sys.exit(1 if fails else 0)
