#!/usr/bin/env python3
"""Geometry and pixel assertions for tests/moments-ui.sh (stdlib only).

usage: check.py <name> <outdir>
Reads <outdir>/<scenario>-<name>.json (the PROBE line) and prints one PASS|FAIL line per
assertion. Exits non-zero on any FAIL.
"""
import json, os, struct, sys, zlib

name, out = sys.argv[1], sys.argv[2]
fails = 0

def report(ok, what):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ": " + what)
    if not ok:
        fails += 1

def load(scenario):
    p = os.path.join(out, scenario + "-" + name + ".json")
    try:
        return json.load(open(p))
    except Exception as e:
        report(False, "probe %s unreadable (%s)" % (p, e))
        sys.exit(1)

def png_rgb(path):
    """Decode an 8-bit RGB/RGBA PNG into (w, h, rows of bytes, bytes per pixel)."""
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n"
    i, idat, w, h, ct = 8, b"", 0, 0, 0
    while i < len(d):
        n, t = struct.unpack(">I4s", d[i:i + 8])
        body = d[i + 8:i + 8 + n]
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", body[:10])
        elif t == b"IDAT":
            idat += body
        i += 12 + n
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat)
    rows, prev, p = [], bytearray(w * bpp), 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + w * bpp]); p += 1 + w * bpp
        for x in range(len(line)):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line); prev = line
    return w, h, rows, bpp

def px(img, x, y):
    w, h, rows, bpp = img
    r = rows[int(y)]; i = int(x) * bpp
    return (r[i], r[i + 1], r[i + 2])

def near(c, hexs, tol=6):
    t = tuple(int(hexs[i:i + 2], 16) for i in (1, 3, 5))
    return all(abs(a - b) <= tol for a, b in zip(c, t))

def vis(b):
    return bool(b and b.get("visible"))

# palette.yaml values the stub Theme derives from (ground, panel, raised, accent, waiting)
GROUND, PANEL, RAISED, ACCENT = "#0e1316", "#151b1f", "#1c2429", "#8ccff1"

if name in ("default", "after"):
    m = load("board")
    png = os.path.join(out, "board-%s.png" % name)
    img = png_rgb(png)
    report(img[0] == 1200 and img[1] == 860, "PNG is the board size 1200x860 (%dx%d)" % (img[0], img[1]))
    P = {k: m[k] for k in ("capturePanel", "renudgePanel", "returnPanel", "handedPanel")}
    report(all(vis(v) and v["w"] == 560 and v["h"] == 386 for v in P.values()), "four cards, each 560x386")
    report(P["capturePanel"]["x"] == 32 and P["capturePanel"]["y"] == 32, "grid starts at 32,32")
    report(P["renudgePanel"]["x"] - (P["capturePanel"]["x"] + 560) == 24
           and P["returnPanel"]["y"] - (P["capturePanel"]["y"] + 386) == 24, "24 px gap between cards")
    ci = m["captureInput"]
    report(vis(ci) and ci["h"] == 48 and ci["w"] == 520, "capture input 520x48")
    pe = m["pressEnter"]
    report(vis(pe) and pe["h"] == 30 and pe["x"] == ci["x"] and pe["y"] > ci["y"] + 48, "Press Enter 30 high, under the input, left aligned")
    rf = m["returnFace"]
    report(vis(rf) and rf["h"] == 32 and 200 < rf["w"] < 420, "return chip 32 high (w=%s)" % (rf and rf["w"]))
    report(m["detour"]["active"] and m["detour"]["text"] == "Detour 4m · back to HD 4412", "chip text from now.json: %s" % m["detour"]["text"])
    st = m["handedSteps"]
    report(len(st) == 4 and len({s["x"] for s in st}) == 1 and all(st[i]["y"] < st[i + 1]["y"] for i in range(3)), "four timeline steps, aligned, in order")
    report(m["handedSentEnabled"] is False, "See what was sent is disabled (read-only)")
    report(vis(m["handedFooter"]) and m["handedFooter"]["y"] + m["handedFooter"]["h"] <= 32 + 386 + 24 + 386, "permission footer inside the card")
    # pixels: the card fills are tokens, the chip is the amber wash, the button is accent
    report(near(px(img, 40, 400), GROUND, 3), "card fill is the ground token")
    report(near(px(img, pe["x"] + 4, pe["y"] + 15), ACCENT, 8), "Press Enter button is the accent")
    report(px(img, rf["x"] + 4, rf["y"] + 16)[0] > px(img, rf["x"] + 4, rf["y"] + 16)[2] + 20, "chip wash is amber (r well above b)")
    if name == "default":
        report(not vis(m["capturedNote"]) and vis(m["nudgeCard"]) and not vis(m["nudgeNote"]) and not vis(m["returnNote"]),
               "default state: no capture note, toast up, no return note")
        nc = m["nudgeCard"]
        report(nc["w"] == 520 and 96 <= nc["h"] <= 112, "toast face 520 wide, ~106 high (%s)" % nc["h"])
        report(m["handedFooter"]["y"] > st[-1]["y"] + 18, "footer note sits below the timeline")
        report(near(px(img, nc["x"] + 8, nc["y"] + 40), RAISED, 4), "toast fill is the raised token")
    else:
        cn = m["capturedNote"]
        report(vis(cn) and cn["h"] > 60, "captured note shows with the enrichment lines (h=%s)" % cn["h"])
        report(near(px(img, cn["x"] + 6, cn["y"] + 6), PANEL, 4), "captured note fill is the panel token")
        report(vis(m["nudgeNote"]) and not vis(m["nudgeCard"]), "dismissed: note replaces the toast")
        report(vis(m["returnNote"]), "returned: the return note shows")
elif name == "bar":
    m = load("chip")
    c = m["chip"]
    report(vis(c) and c["h"] == 32 and c["w"] > 200, "chip placed in a bar: 32 high, content wide (%s)" % c["w"])
    report(m["right"]["x"] - (m["left"]["x"] + m["left"]["w"]) == 12 + c["w"], "neighbours sit one chip apart (spacing 6 + 6)")
    report(os.path.getsize(os.path.join(out, "chip-bar.png")) > 500, "PNG written")
elif name in ("none", "stale"):
    m = load("chipnone")
    c = m["chip"]
    report(c["w"] == 0 and not c["visible"] and m["chip"]["implicitWidth"] == 0, "no detour: chip is zero width and hidden")
    report(m["right"]["x"] - (m["left"]["x"] + m["left"]["w"]) == 6, "no gap is left where the chip would be")
    report(not m["detour"]["active"], "detour inactive (%s)" % ("stale now.json" if name == "stale" else "clock is in"))

elif name == "focusoff":
    m = load("chip")
    c = m["chip"]
    report(m["detour"]["active"] and m["detour"]["text"] == "Detour 5m · back to HD 4412",
           "clock in, focus off the task 5 min: chip says %s" % m["detour"]["text"])
    report(vis(c) and c["h"] == 32 and c["w"] > 200, "the chip shows (w=%s)" % c["w"])
elif name == "focusshort":
    m = load("chip")
    report(not m["detour"]["active"] and m["chip"]["w"] == 0, "focus off for 1 min: not a detour yet, no chip")
elif name in ("focusterm", "focuspopup"):
    m = load("chipnone")
    report(not m["detour"]["active"] and m["chip"]["w"] == 0 and not m["chip"]["visible"],
           "%s: no detour, chip hidden" % ("focus on the terminal" if name == "focusterm" else "a shell popup is not leaving"))

sys.exit(1 if fails else 0)
