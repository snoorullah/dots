#!/usr/bin/env python3
"""Board states of the bar as JSON models, for tests/bar-ui.sh.

  mkfixtures.py <out dir>      writes <state>.json, plus logos/*.png (flat colour squares)

Sample text only (Sam R. style names are not used here at all). Icon names are Phosphor
names from the registry; app logos are generated squares, referenced as @LOGOS@/<name>.png.
"""
import json
import os
import struct
import sys
import zlib

PROFILES = [("Agents", "sparkle"), ("Dev", "terminal-window"), ("Web", "globe"), ("Comms", "chat-circle"),
            ("Review", "git-pull-request"), ("Notes", "notebook"), ("Other", "stack")]


def png(path, rgb, size=36):
    row = b"\x00" + bytes(rgb + (255,)) * size
    raw = row * size
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


LOGOS = {"herdr": (88, 130, 200), "ghostty": (120, 120, 140), "code": (60, 140, 220), "zen": (200, 120, 90),
         "obsidian": (140, 100, 200), "slack": (170, 80, 150), "mail": (230, 150, 60)}


def logo(k):
    return {"cls": k, "icon": "@LOGOS@/%s.png" % k}


def ws(i, name, active, apps, more=0):
    return {"id": i, "name": name, "active": active, "apps": [logo(a) for a in apps], "more": more}


def wait(i, kind, icon, tone, name, age, popout="waiting"):
    return {"id": "w%d" % i, "kind": kind, "icon": icon, "tone": tone, "name": name, "age": age, "popout": popout}


W = {
    "agent": ("agent", "sparkle", "waiting", "Agent waits on you", "12m", "agent"),
    "vip": ("vip", "star", "waiting", "VIP message", "9m", "waiting"),
    "alert": ("alert", "warning", "failed", "New alert", "2m", "waiting"),
    "review": ("review", "git-pull-request", "waiting", "Review requested", "3m", "waiting"),
    "mail": ("mail", "envelope", "waiting", "VIP mail", "1m", "waiting"),
    "ticket": ("ticket", "ticket", "waiting", "Ticket due today", "now", "waiting"),
}


def waits(keys, more=0):
    out = []
    for n, k in enumerate(keys):
        kind, icon, tone, name, age, pop = W[k]
        out.append(wait(n, kind, icon, tone, name, age, pop))
    return {"shown": out, "more": more}


def base():
    return {
        "profiles": [{"name": n, "icon": i} for n, i in PROFILES], "activeProfile": "Agents",
        "workspaces": [ws(1, "infra", True, ["herdr", "ghostty", "code"]), ws(2, "erp", False, ["herdr"]),
                       ws(3, "web", False, ["zen", "obsidian"])],
        "task": "HD 4412 Rotate deploy keys", "detour": "",
        "clock": "22:28", "date": "Fri 30 Oct", "salah": "Isha 24m",
        "waits": {"shown": [], "more": 0}, "fault": {"kind": "none", "text": ""},
        "music": {"present": True, "playing": True, "title": "Slow Orbit", "artist": "Marta Voss · Night Drives", "art": ""},
        "metrics": [
            {"key": "prs", "icon": "git-pull-request", "text": "3", "title": "PRs merged today", "accent": False},
            {"key": "tasks", "icon": "check-circle", "text": "2", "title": "Tickets closed today", "accent": False},
            {"key": "xp", "icon": "", "text": "+154", "title": "XP today", "accent": True}],
        "logout": "03:12", "bell": {"dot": True, "quiet": False},
    }


def states():
    s = {}
    s["quiet"] = base()
    a = base(); a["waits"] = waits(["agent", "vip", "alert"]); s["waiting"] = a
    d = base(); d["detour"] = "12m"; d["waits"] = waits(["review"]); d["activeProfile"] = "Comms"
    d["workspaces"] = [ws(1, "chat", True, ["slack"]), ws(2, "2", False, ["mail"])]; s["detour"] = d
    f = base(); f["fault"] = {"kind": "failed", "text": "backup failed"}; f["salah"] = "Isha 9m"; s["failed"] = f
    h = base(); h["hoverWs"] = 2; s["hover"] = h
    u = base(); u["fault"] = {"kind": "unknown", "text": "data stale"}; s["stale"] = u
    p = base(); p["music"]["playing"] = False; s["paused"] = p
    o = base(); o["waits"] = waits(["agent", "vip", "alert"], more=2); s["overflow"] = o
    n = base(); n["music"] = {"present": False}; n["metrics"] = []; n["logout"] = ""; n["salah"] = ""
    n["trayCount"] = 3; s["bare"] = n
    return s


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(os.path.join(out, "logos"), exist_ok=True)
    for k, rgb in LOGOS.items():
        png(os.path.join(out, "logos", k + ".png"), rgb)
    for k, v in states().items():
        with open(os.path.join(out, k + ".json"), "w") as f:
            json.dump(v, f, indent=1)
