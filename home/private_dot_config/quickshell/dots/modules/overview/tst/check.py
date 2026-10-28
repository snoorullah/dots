#!/usr/bin/env python3
"""Pixel and geometry assertions for tests/overview-ui.sh (stdlib only, no PIL).

usage: check.py <name> <outdir>

Each check reads the PROBE json lines (<outdir>/<scenario>-<tag>.json, written by
the shell script from the scene log) and the PNG of the same stem. It prints one
"PASS|FAIL <name>: detail" line per assertion and exits non-zero on any FAIL.
Colours are the stub Theme's (derived from the palette exactly like the real Tokens.qml).
"""
import json
import math
import os
import struct
import sys
import zlib

AMBER = (0xFF, 0xB8, 0x6C)
RED = (0xFF, 0x55, 0x55)
FGFAINT = (0x48, 0x52, 0x72)   # mix(bg, comment, 0.55), as the stub derives it
ACCENT = (0xBD, 0x93, 0xF9)
STAGE_BG = (0x1A, 0x1A, 0x2E)

failures = 0


def report(ok, name, detail=""):
    global failures
    if not ok:
        failures += 1
    print("%s %s%s" % ("PASS" if ok else "FAIL", name, (": " + detail) if detail else ""))


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
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
    assert depth == 8 and ctype in (2, 6), "unsupported png (depth %d type %d)" % (depth, ctype)
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
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
    def __init__(self, path):
        self.w, self.h, self.bpp, self.rows = read_png(path)

    def px(self, x, y):
        x, y = int(round(x)), int(round(y))
        if not (0 <= x < self.w and 0 <= y < self.h):
            return (0, 0, 0)
        r = self.rows[y]
        i = x * self.bpp
        return (r[i], r[i + 1], r[i + 2])

    def alpha(self, x, y):
        x, y = int(round(x)), int(round(y))
        if self.bpp != 4 or not (0 <= x < self.w and 0 <= y < self.h):
            return 255
        return self.rows[y][x * 4 + 3]

    def count_tone(self, tone, box=None):
        """Pixels that read as the status tone, by hue: wash plates are dark, and text on
        its own wash is the tone lifted toward fg (Look.legible), so a fixed RGB would miss it."""
        import colorsys
        lo, hi = {"red": (-15, 15), "amber": (22, 50)}[tone]
        x0, y0, x1, y1 = box or (0, 0, self.w, self.h)
        n = 0
        for y in range(max(0, y0), min(self.h, y1)):
            r = self.rows[y]
            for x in range(max(0, x0), min(self.w, x1)):
                i = x * self.bpp
                h, sat, v = colorsys.rgb_to_hsv(r[i] / 255, r[i + 1] / 255, r[i + 2] / 255)
                deg = h * 360
                if deg > 180: deg -= 360
                if lo <= deg <= hi and sat >= 0.30 and v >= 0.70:
                    n += 1
        return n

    def count_near(self, rgb, tol, box=None):
        x0, y0, x1, y1 = box or (0, 0, self.w, self.h)
        n = 0
        for y in range(max(0, y0), min(self.h, y1)):
            r = self.rows[y]
            for x in range(max(0, x0), min(self.w, x1)):
                i = x * self.bpp
                if abs(r[i] - rgb[0]) <= tol and abs(r[i + 1] - rgb[1]) <= tol and abs(r[i + 2] - rgb[2]) <= tol:
                    n += 1
        return n


def dist(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def load(outdir, scenario, tag):
    stem = os.path.join(outdir, "%s-%s" % (scenario, tag))
    with open(stem + ".json") as f:
        m = json.load(f)
    return m, Img(stem + ".png")


def near(a, b, tol):
    return abs(a - b) <= tol


# ---- the eight assertions from the spec (5.4) --------------------------------------------

def t1_nominal(out):
    m, im = load(out, "pill", "nominal")
    p = m["pill"]
    report(p["w"] == 0 and p["implicitWidth"] == 0 and p["implicitHeight"] == 0,
           "1 nominal pill has zero width and height", "w=%s iw=%s ih=%s" % (p["w"], p["implicitWidth"], p["implicitHeight"]))
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a == 0 and r == 0, "1 nominal screenshot has no amber or red pixel", "amber=%d red=%d" % (a, r))
    # mock slab = 10 + 40 + 6 + 40 + 10: a nominal pill adds no width and no chip gap
    report(m["slabW"] == 106, "1 nominal pill adds no width and no gap to the slab", "slab=%s" % m["slabW"])
    report(not any(c and c["visible"] for c in m["chips"].values()), "1 nominal: no chip is visible")


def t2_waiting(out):
    n, _ = load(out, "pill", "nominal")
    m, im = load(out, "pill", "waiting")
    grew = m["slabW"] - n["slabW"]
    pw = m["pill"]["w"]
    gap = 6   # the slab's own chip gap, paid once when the pill becomes visible
    report(pw > 0 and near(grew, pw + gap, 1), "2 slab grows by the badge width plus one chip gap", "grew=%s pill=%s" % (grew, pw))
    report(near(m["leftX"], n["leftX"], 0.5), "2 nothing left of the badge moves", "%s -> %s" % (n["leftX"], m["leftX"]))
    report(near(m["rightX"] - n["rightX"], pw + gap, 1), "2 the right neighbour moves by the badge width and the gap only",
           "dx=%s pill=%s" % (m["rightX"] - n["rightX"], pw))
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a >= 4 and r == 0, "2 amber present, red absent", "amber=%d red=%d" % (a, r))
    c = m["chips"]
    report(c["waitingChip"]["visible"] and not c["failedChip"]["visible"], "2 only the waiting chip is visible")


def t3_failed(out):
    m, im = load(out, "pill", "failed")
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(r >= 4 and a == 0, "3 red present, amber absent", "amber=%d red=%d" % (a, r))
    c = m["chips"]
    report(c["failedChip"]["visible"] and not c["waitingChip"]["visible"], "3 only the failed chip is visible")


def t4_stale(out):
    m, im = load(out, "pill", "stale")
    report(m["stale"] >= 1 and m["chips"]["staleChip"]["visible"], "4 hollow ? renders", "marks=%s" % m["stale"])
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a == 0 and r == 0, "4 numbers are not amber or red when stale", "amber=%d red=%d" % (a, r))
    f = im.count_near(FGFAINT, 30)
    report(f >= 8, "4 fgFaint pixels present", "fgFaint=%d" % f)
    report(m["dim"] is True, "4 State.dim is set")


def t5_card(out):
    m, im = load(out, "card", "waiting")
    c = m["card"]
    report(near(c["w"], 380, 1), "5 card is 380 wide", "w=%s" % c["w"])
    report(c["h"] <= 520, "5 card is at most 520 tall", "h=%s" % c["h"])
    report(near(m["notchCx"], m["pill"]["cx"], 1), "5 notch centre within 1px of the pill centre",
           "notch=%.2f pill=%.2f" % (m["notchCx"], m["pill"]["cx"]))
    report(m["notchW"] == 8 and m["notchH"] == 4, "5 notch is 8x4")
    report(c["radius"] == 16, "5 card radius property is 16", "r=%s" % c["radius"])
    # radius in pixels: with r=16, (4,4) from the corner lies outside the arc, (7,7) inside
    x0, y0 = int(round(c["x"])), int(round(c["y"]))
    # the grabbed stage is transparent outside the card, so alpha tells card from nothing
    outside, inside = im.alpha(x0 + 3, y0 + 3), im.alpha(x0 + 8, y0 + 8)
    report(outside < 16 and inside > 100, "5 corner is rounded to 16 px", "alpha outside=%s inside=%s" % (outside, inside))
    # notch pixel centre: the lit span on the notch's widest row
    y = int(round(c["y"])) - 1
    row = [x for x in range(im.w) if im.alpha(x, y) > 20 and abs(x - m["notchCx"]) < 12]
    if row:
        mid = (min(row) + max(row) + 1) / 2.0
        report(near(mid, m["pill"]["cx"], 1.5), "5 notch pixels centred under the pill", "mid=%.1f pill=%.1f" % (mid, m["pill"]["cx"]))
    else:
        report(False, "5 notch pixels found above the card")
    report(m["rows"] >= 1, "5 card lists attention rows", "rows=%s" % m["rows"])


def ramp_checks(m, im, tag):
    h = m["heat"]
    colours = {}
    for (x, y) in h["centres"]:
        px = im.px(x, y)
        colours[tuple(v // 6 for v in px)] = px
    report(len(colours) >= 5, "%s five distinct ramp colours" % tag, "distinct=%d" % len(colours))
    # ramp must be monotonic toward the accent: collect by score order of the fixture (score = i % 5)
    base = im.px(h["centres"][0][0], h["centres"][0][1])      # cell 0 has score 0 -> panel background
    lum = [dist(im.px(*h["centres"][i]), base) for i in range(1, 5)]
    report(all(lum[i] < lum[i + 1] for i in range(3)), "%s ramp rises with score" % tag, "d=%s" % lum)


def fixture_days(name="full"):
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "fixtures", name, "heatmap.json")) as f:
        return json.load(f)["days"]


def hm_fmt(sec):
    m = int(max(0, sec) // 60)
    return "%dm" % m if m < 60 else "%dh %02dm" % (m // 60, m % 60)


def t6_compact(out):
    """The 235x95 grid of the card: unchanged by the page's large variant."""
    m, im = load(out, "heatcompact", "main")
    h = m["heat"]
    report(h["count"] == 119, "6c 119 cells", "n=%s" % h["count"])
    report(h["sizeOk"] and h["cell"] == 11, "6c every cell is 11x11", "cell=%s" % h["cell"])
    report(h["gapX"] == 3 and h["gapY"] == 3, "6c gap is 3", "gx=%s gy=%s" % (h["gapX"], h["gapY"]))
    report(near(h["w"], 235, 1) and near(h["h"], 95, 1), "6c grid box is 235x95", "%sx%s" % (h["w"], h["h"]))
    report(m["heatBox"]["w"] == 235 and m["heatBox"]["h"] == 95, "6c compact part carries no labels", "box=%sx%s" % (m["heatBox"]["w"], m["heatBox"]["h"]))
    report(not m["heatLabels"]["weekdays"] and not m["heatLabels"]["months"], "6c no weekday or month labels")
    report(h["cols"] == 17 and h["rows"] == 7, "6c 17 columns x 7 rows", "%dx%d" % (h["cols"], h["rows"]))
    ramp_checks(m, im, "6c")


def t6_heatmap(out):
    """The Heatmap page: big token-fitted cells, labels, streak and best-week figures."""
    m, im = load(out, "panel", "heatmap")
    h, days = m["heat"], fixture_days()
    pageW, pageH = 920 - 48 - 148 - 1 - 24, 640 - 48          # panel padding, nav, divider, gaps
    report(h["count"] == 119, "6 119 cells", "n=%s" % h["count"])
    report(h["sizeOk"], "6 every cell is square and the same size", "cell=%s" % h["cell"])
    report(h["cell"] >= 2 * 11, "6 cells are at least twice the compact size", "cell=%s" % h["cell"])
    report(h["gapX"] == 4 and h["gapY"] == 4, "6 gap is space.s (4)", "gx=%s gy=%s" % (h["gapX"], h["gapY"]))
    report(h["cols"] == 17 and h["rows"] == 7, "6 17 columns x 7 rows", "%dx%d" % (h["cols"], h["rows"]))
    report(near(h["w"], 17 * h["cell"] + 16 * 4, 1) and near(h["h"], 7 * h["cell"] + 6 * 4, 1),
           "6 grid box follows cell and gap", "%sx%s" % (h["w"], h["h"]))
    box = m["heatBox"]
    report(box["w"] <= pageW and box["w"] >= 0.9 * pageW, "6 the grid uses at least 90%% of the page width", "%s of %s" % (box["w"], pageW))
    tiles = m["tiles"]
    bottom = max(t["y"] + t["h"] for t in tiles) if tiles else 0
    top = m["panelBox"]["y"]
    report(bottom - top <= m["panelBox"]["h"] - 24, "6 nothing is pushed past the panel's bottom padding", "bottom=%.0f" % (bottom - top))
    report(bottom - top >= 0.75 * m["panelBox"]["h"], "6 the page fills at least 75%% of the panel height", "bottom=%.0f of %s" % (bottom - top, m["panelBox"]["h"]))
    wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    import datetime
    want_wd = [wd[datetime.date.fromisoformat(days[r]["d"]).weekday()] for r in range(7)]
    report(m["heatLabels"]["weekdays"] == want_wd, "6 weekday labels follow the dates in each row", "%s" % m["heatLabels"]["weekdays"])
    mon, last, want_m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], -1, []
    for c in range(17):
        mo = datetime.date.fromisoformat(days[c * 7]["d"]).month
        if mo != last:
            want_m.append(mon[mo - 1])
            last = mo
    report(m["heatLabels"]["months"] == want_m, "6 month labels open at the right columns", "%s" % m["heatLabels"]["months"])
    # streak / best week, computed here from the fixture rather than read back from Ledger.js
    worked = [d["workedSec"] for d in days]
    best = run = 0
    for w in worked:
        run = run + 1 if w > 0 else 0
        best = max(best, run)
    end = len(worked) - 1 - (0 if worked[-1] > 0 else 1)
    cur = 0
    while end >= 0 and worked[end] > 0:
        cur, end = cur + 1, end - 1
    bw = max(sum(worked[max(0, i - 6):i + 1]) for i in range(len(worked)))
    byname = dict((t["label"], t) for t in tiles)
    report(byname.get("Streak", {}).get("value") == "%d days" % cur and byname["Streak"]["note"] == "longest %d" % best,
           "6 streak tile shows current and longest", "%s" % byname.get("Streak"))
    report(byname.get("Best week", {}).get("value") == hm_fmt(bw), "6 best-week tile shows the best 7 days", "%s want %s" % (byname.get("Best week", {}).get("value"), hm_fmt(bw)))
    report(byname.get("Total", {}).get("value") == hm_fmt(sum(worked)), "6 total tile", byname.get("Total", {}).get("value"))
    ramp_checks(m, im, "6")


def angle_lit(im, cx, cy, r, tol=70):
    """Largest clockwise angle from 12 o'clock over which the accent arc is continuously lit."""
    lit = []
    for a in range(360):
        t = math.radians(a)
        x, y = cx + r * math.sin(t), cy - r * math.cos(t)
        lit.append(dist(im.px(x, y), ACCENT) <= tol)
    end = 0
    while end < 360 and lit[end]:
        end += 1
    return end


def t7_focus(out):
    for tag, want in (("focus-90", 90.0), ("focus-200", 360 * 833 / 1500.0)):
        m, im = load(out, "panel", tag)
        r = m["ring"]
        radius = (r["d"] - r["stroke"]) / 2.0
        got = angle_lit(im, r["cx"], r["cy"], radius)
        report(abs(got - want) <= 2.0, "7 ring arc %s within 2 degrees" % tag, "want=%.1f got=%d prop=%.1f" % (want, got, r["angle"]))
        report(abs(r["angle"] - want) <= 0.5, "7 ring angle property matches elapsed/target (%s)" % tag)


def t8_v2(out):
    m, im = load(out, "pill", "v2")
    report(m["stale"] >= 1 and m["chips"]["staleChip"]["visible"], "8 v=2 degrades to a hollow ?")
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a == 0 and r == 0, "8 v=2 data is not drawn as amber or red", "amber=%d red=%d" % (a, r))
    with open(os.path.join(out, "pill-v2.log")) as f:
        lines = [l for l in f if "overview:" in l and "expected 1" in l]
    report(len(lines) == 1, "8 exactly one log line for the version mismatch", "lines=%d" % len(lines))


def t_live(out):
    b, _ = load(out, "pill", "live-before")
    a, im = load(out, "pill", "live-after")
    report(b["pill"]["w"] == 0, "live: starts nominal (zero width)")
    report(a["chips"]["waitingChip"]["visible"] and a["pill"]["w"] > 0,
           "live: an atomic os.replace of attention.json is picked up", "w=%s" % a["pill"]["w"])


def t_dim_card(out):
    m, im = load(out, "card", "stale")
    report(m["dim"] is True and m["stale"] >= 1, "dim: stale card shows ? and dims")
    report(im.count_tone("amber") == 0 and im.count_tone("red") == 0, "dim: stale card has no amber or red")


def t_full(out):
    m, im = load(out, "card", "full")
    report(m["rows"] <= 8, "full: card row count is bounded", "rows=%s" % m["rows"])
    report(m["card"]["h"] <= 520, "full: card is capped at 520", "h=%s" % m["card"]["h"])
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a > 0 and r > 0, "full: amber and red both present when both are true", "amber=%d red=%d" % (a, r))


def t_footer(out):
    """The footer row is pinned outside the scroller and a fade shows when content overflows."""
    m, im = load(out, "card", "full")
    f, c, s = m["foot"], m["card"], m["scroll"]
    report(f["visible"] and f["buttons"] == 2, "footer: Open panel and Start focus are present", "buttons=%s" % f["buttons"])
    report(f["y"] + f["h"] <= c["y"] + c["h"] + 0.5, "footer: bottom edge is inside the card", "foot bottom=%.1f card bottom=%.1f" % (f["y"] + f["h"], c["y"] + c["h"]))
    report(s["y"] + s["h"] <= f["y"] + 0.5, "footer: the scroller ends above the footer (nothing scrolls under it)", "scroll bottom=%.1f foot top=%.1f" % (s["y"] + s["h"], f["y"]))
    report(s["contentH"] > s["h"] and m["fadeVisible"], "footer: overflowing content shows the bottom fade", "content=%s view=%s" % (s["contentH"], s["h"]))
    # the fade ends opaque: every pixel along the scroller's last row is solid, which the bare
    # translucent card (alpha ~0.86) is not
    y = int(round(s["y"] + s["h"])) - 1
    alphas = [im.alpha(c["x"] + 16 + dx, y) for dx in range(0, int(c["w"]) - 32, 6)]
    report(min(alphas) >= 250, "footer: the fade reaches the card colour at the scroller's end", "min alpha=%s" % min(alphas))
    w, imw = load(out, "card", "stale")
    report(not w["fadeVisible"] and w["scroll"]["contentH"] <= w["scroll"]["h"], "footer: no fade when everything fits", "fade=%s" % w["fadeVisible"])
    report(w["foot"]["y"] + w["foot"]["h"] <= w["card"]["y"] + w["card"]["h"] + 0.5, "footer: bottom edge is inside a short card")


def t_pressed(out):
    m, _ = load(out, "card", "waiting")
    lk = m["look"]
    report(lk["aPressed"] > lk["aHover"], "button: pressed overlay is stronger than hover (Look.aPressed from Theme.alpha.pressed)",
           "pressed=%.2f hover=%.2f" % (lk["aPressed"], lk["aHover"]))


def t_lamp(out):
    m, im = load(out, "pill", "lamp")
    a, r = im.count_tone("amber"), im.count_tone("red")
    report(a >= 4 and r >= 4, "lamp: amber and red both present under the lamp test", "amber=%d red=%d" % (a, r))
    report(m["chips"]["focusChip"]["visible"], "lamp: the focus ring is forced visible")


CHECKS = {
    "nominal": t1_nominal, "waiting": t2_waiting, "failed": t3_failed, "stale": t4_stale,
    "card": t5_card, "heatmap": t6_heatmap, "compact": t6_compact, "footer": t_footer, "pressed": t_pressed, "focus": t7_focus, "v2": t8_v2,
    "live": t_live, "dimcard": t_dim_card, "full": t_full, "lamp": t_lamp,
}

if __name__ == "__main__":
    name, outdir = sys.argv[1], sys.argv[2]
    try:
        CHECKS[name](outdir)
    except Exception as e:      # a missing probe or png is a failure, not a crash
        report(False, name, "%s: %s" % (type(e).__name__, e))
    sys.exit(1 if failures else 0)
