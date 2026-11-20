#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Wallpaper picker backend. One JSON object on stdout per call, always exit 0 (the picker
shows the object, it never parses a traceback). Local only: argv-only subprocesses, no shell,
no network.

  wp.py scan [DIR]                         images under the folder, recursive
  wp.py palette PATH                       matugen dry-run, contrast of text on surface, AA fit
  wp.py apply PATH [--output O] [--palette wallpaper|current|mode]
  wp.py preview PATH | restore | revert    desktop only, no cache, no theme
  wp.py fav PATH | folder DIR              favourites, saved folder
  wp.py state [KEY VALUE]                  shuffle on|off, lock on|off, target NAME, palette NAME
  wp.py shuffle-tick [--hold salah|focus]  one scheduled step
  wp.py next [--hold salah|focus]          the same step on demand (shuffle need not be on)
"""
import colorsys
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

EXT = {".jpg", ".jpeg", ".png", ".webp"}
AA = 4.5


def home():
    return Path(os.environ.get("HOME", "~")).expanduser()


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or str(home() / ".local/state")
    return Path(base) / "dots-wallpaper"


def cache_file():
    return home() / ".cache" / "current-wallpaper"


def lock_link():
    return home() / ".cache" / "dots-lock-wallpaper"


def write_atomic(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def load_state():
    try:
        s = json.loads((state_dir() / "state.json").read_text())
        return s if isinstance(s, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(s):
    write_atomic(state_dir() / "state.json", json.dumps(s, indent=1))


def folder_path():
    env = os.environ.get("WALLPAPER_DIR")
    if env:
        return Path(env).expanduser()
    f = load_state().get("folder")
    return Path(f) if f else home() / "walls"


def is_image(path):
    """Extension and magic bytes: a half-written or renamed file is 'skipped'."""
    try:
        with open(path, "rb") as f:
            head = f.read(12)
    except OSError:
        return False
    if head.startswith(b"\x89PNG\r\n\x1a\n") or head.startswith(b"\xff\xd8\xff"):
        return True
    return head[:4] == b"RIFF" and head[8:12] == b"WEBP"


# ── scan ───────────────────────────────────────────────────────────────
def scan(arg=None):
    root = Path(arg).expanduser() if arg else folder_path()
    favs = set(load_state().get("favs", []))
    out = {"folder": str(root), "name": root.name or str(root), "exists": root.is_dir(),
           "items": [], "count": 0, "skipped": 0, "cur": current()}
    if not root.is_dir():
        return out
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if not d.startswith("."))
        for f in sorted(fn):
            p = Path(dp) / f
            if p.suffix.lower() not in EXT:
                continue
            ok = is_image(p)
            try:
                st = p.stat()
                mt, sz = int(st.st_mtime), st.st_size
            except OSError:
                mt, sz, ok = 0, 0, False
            out["items"].append({"name": p.stem, "path": str(p), "rel": str(p.relative_to(root)),
                                 "mtime": mt, "size": sz, "ok": ok, "fav": str(p) in favs})
    out["items"].sort(key=lambda i: i["rel"])
    out["count"] = len(out["items"])
    out["skipped"] = sum(1 for i in out["items"] if not i["ok"])
    return out


# ── palette ────────────────────────────────────────────────────────────
def lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexrgb(r, g, b):
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def fit_text(surface, text):
    """Lift (or lower) the text lightness until it reads at AA on the surface."""
    h = text.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    up = lum(surface) < 0.4
    for _ in range(100):
        cand = hexrgb(*colorsys.hls_to_rgb(hh, ll, ss))
        if ratio(surface, cand) >= AA:
            return cand
        ll = min(1.0, ll + 0.02) if up else max(0.0, ll - 0.02)
    return "#ffffff" if up else "#000000"


def pick(v):
    if isinstance(v, dict):
        v = v.get("dark") or v.get("default")
        if isinstance(v, dict):
            v = v.get("color")
    return v


def tags_for(surface, primary):
    r, g, b = (int(surface.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    ll = colorsys.rgb_to_hls(r, g, b)[1]
    out = ["dark" if ll < 0.5 else "light"]
    if primary:
        pr, pg, pb = (int(primary.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
        hh, _, ss = colorsys.rgb_to_hls(pr, pg, pb)
        out.append("calm" if ss < 0.6 else "vivid")
        deg = hh * 360
        out.append("cool" if 150 <= deg <= 280 else "warm")
    return out


def palette(path):
    p = Path(path).expanduser()
    if not p.is_file():
        return {"error": "no such file"}
    cache = state_dir() / "palette-cache.json"
    try:
        cached = json.loads(cache.read_text())
    except (OSError, ValueError):
        cached = {}
    key = "%s:%d" % (p, int(p.stat().st_mtime))
    if key in cached:
        return cached[key]
    exe = shutil.which("matugen")
    if not exe:
        return {"error": "matugen is not installed"}
    try:
        r = subprocess.run([exe, "image", str(p), "--json", "hex", "--dry-run", "--mode", "dark",
                            "--type", "scheme-tonal-spot", "--prefer", "saturation", "--quiet"],
                           capture_output=True, text=True, timeout=60)
        cols = json.loads(r.stdout)["colors"]
        if isinstance(cols.get("dark"), dict):
            cols = cols["dark"]
        surface, text, primary = pick(cols["surface"]), pick(cols["on_surface"]), pick(cols.get("primary"))
        if r.returncode != 0 or not re.fullmatch(r"#[0-9a-fA-F]{6}", surface or ""):
            return {"error": "matugen failed"}
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError, AttributeError):
        return {"error": "matugen failed"}
    rt = ratio(surface, text)
    out = {"surface": surface.lower(), "text": text.lower(), "ratio": round(rt, 2),
           "tuned": rt < AA, "tunedText": fit_text(surface, text) if rt < AA else text.lower(),
           "tags": tags_for(surface, primary)}
    cached[key] = out
    try:
        write_atomic(cache, json.dumps(cached))
    except OSError:
        pass
    return out


# ── apply ──────────────────────────────────────────────────────────────
def run(argv, timeout=20):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def detach(argv):
    try:
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def swww_img(path, output=None, duration="1"):
    if not run(["swww", "query"]):
        detach(["swww-daemon"])
        time.sleep(float(os.environ.get("DOTS_WP_WAIT", "1")))
    base = ["swww", "img", str(path)]
    if output:
        base += ["-o", output]
    return (run(base + ["--transition-type", "fade", "--transition-duration", duration])
            or run(base))


def check_file(path):
    p = Path(path).expanduser()
    if not p.is_file():
        return None, "no such file"
    if not is_image(p):
        return None, "not an image"
    return p, ""


def set_lock_link(path):
    link = lock_link()
    try:
        if link.is_symlink() or link.exists():
            link.unlink()
        if load_state().get("lock", True):
            link.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(str(path), link)
    except OSError:
        pass


def current():
    try:
        v = cache_file().read_text().strip()
        return v if v and Path(v).is_file() else ""
    except OSError:
        return ""


def apply(path, output=None, pal="wallpaper", remember=True):
    p, why = check_file(path)
    if p is None:
        return {"ok": False, "error": why}
    if not swww_img(p, output):
        return {"ok": False, "error": "swww failed"}
    if output:
        return {"ok": True, "path": str(p), "output": output}
    prev = current()
    write_atomic(cache_file(), str(p))
    if remember and prev and prev != str(p):
        s = load_state()
        s["previous"] = prev
        save_state(s)
    set_lock_link(p)
    if pal == "wallpaper":
        detach(["dots-theme", "wallpaper", str(p)])
    return {"ok": True, "path": str(p), "palette": pal}


def preview(path):
    p, why = check_file(path)
    if p is None:
        return {"ok": False, "error": why}
    return {"ok": swww_img(p, None, "0.3"), "path": str(p)}


def restore():
    cur = current()
    if not cur:
        return {"ok": False, "error": "nothing to restore"}
    return {"ok": swww_img(cur, None, "0.3"), "path": cur}


def revert():
    prev = load_state().get("previous")
    if not prev:
        return {"ok": False, "error": "no previous wallpaper"}
    return apply(prev, None, "wallpaper", remember=False)


# ── favourites, folder, state ──────────────────────────────────────────
def fav(path):
    s = load_state()
    favs = s.get("favs", [])
    p = str(Path(path).expanduser())
    on = p not in favs
    favs = favs + [p] if on else [f for f in favs if f != p]
    s["favs"] = favs
    save_state(s)
    return {"ok": True, "fav": on, "path": p}


def set_folder(d):
    p = Path(d).expanduser()
    if not p.is_dir():
        return {"ok": False, "error": "not a folder"}
    s = load_state()
    s["folder"] = str(p)
    save_state(s)
    return {"ok": True, "folder": str(p)}


KEYS = {"shuffle": ("on", "off"), "lock": ("on", "off")}


def state(args):
    s = load_state()
    if len(args) == 2:
        k, v = args
        if k in KEYS and v in KEYS[k]:
            s[k] = v == "on"
        elif k in ("target", "palette") and re.fullmatch(r"[A-Za-z0-9_.:-]{1,40}", v):
            s[k] = v
        else:
            return {"ok": False, "error": "unknown key or value"}
        save_state(s)
    return {"ok": True, "shuffle": bool(s.get("shuffle", False)), "lock": bool(s.get("lock", True)),
            "target": s.get("target", "all"), "palette": s.get("palette", "wallpaper"),
            "folder": str(folder_path()), "previous": s.get("previous", "")}


def shuffle_tick(args, force=False):
    s = load_state()
    if not force and not s.get("shuffle", False):
        return {"ok": True, "action": "off"}
    if "--hold" in args:
        i = args.index("--hold")
        why = args[i + 1] if i + 1 < len(args) else "hold"
        return {"ok": True, "action": "held", "why": why}
    items = [i for i in scan()["items"] if i["ok"]]
    cur = current()
    pool = [i for i in items if i["fav"]] or items
    pool = [i for i in pool if i["path"] != cur] or pool
    if not pool:
        return {"ok": True, "action": "off"}
    pick_ = random.choice(pool)["path"]
    r = apply(pick_)
    r["action"] = "applied" if r.get("ok") else "failed"
    return r


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("scan", [])
    if cmd == "scan":
        out = scan(rest[0] if rest else None)
    elif cmd == "palette" and rest:
        out = palette(rest[0])
    elif cmd == "apply" and rest:
        o = rest[rest.index("--output") + 1] if "--output" in rest and rest.index("--output") + 1 < len(rest) else None
        pl = rest[rest.index("--palette") + 1] if "--palette" in rest and rest.index("--palette") + 1 < len(rest) else "wallpaper"
        if o is not None and not re.fullmatch(r"[A-Za-z0-9_.:-]{1,40}", o):
            out = {"ok": False, "error": "bad output name"}
        else:
            out = apply(rest[0], o, pl if pl in ("wallpaper", "current", "mode") else "wallpaper")
    elif cmd == "preview" and rest:
        out = preview(rest[0])
    elif cmd == "restore":
        out = restore()
    elif cmd == "revert":
        out = revert()
    elif cmd == "fav" and rest:
        out = fav(rest[0])
    elif cmd == "folder" and rest:
        out = set_folder(rest[0])
    elif cmd == "state":
        out = state(rest)
    elif cmd == "shuffle-tick":
        out = shuffle_tick(rest)
    elif cmd == "next":                 # N and R in the picker: one step now, shuffle on or not
        out = shuffle_tick(rest, force=True)
    else:
        out = {"ok": False, "error": "usage: scan|palette|apply|preview|restore|revert|fav|folder|state|shuffle-tick"}
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
