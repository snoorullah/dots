#!/usr/bin/env bash
# Every Hyprland keybind must appear on the Super+? cheatsheet.
#
# The cheatsheet (keybind-help.sh) is hand-written for good descriptions, so it drifts:
# on 2026-11-20 it listed 53 rows against 70 binds and missed every Quickshell key. This
# fails as soon as a bind in hyprland.lua has no row. Binds made in a `for` loop
# (focus/move/workspace keys) and binds inside a submap are covered by one summary row
# each, so they are skipped here; the submap's entry key is still checked.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
python3 -I - "$root/home/private_dot_config/hypr/hyprland.lua.tmpl" \
  "$root/home/private_dot_local/private_bin/executable_keybind-help.sh" <<'PY'
import re, sys

lua_path, sheet_path = sys.argv[1], sys.argv[2]
lua = open(lua_path).read().splitlines()
sheet = open(sheet_path).read()
rows = sheet.split("<<'EOF'", 1)[1].split("\nEOF", 1)[0]

# key names in hyprland.lua -> the words the cheatsheet uses
ALIAS = {"SLASH": "/", "COMMA": ",", "SEMICOLON": ";", "ESCAPE": "ESCAPE", "SPACE": "SPACE",
         "RETURN": "RETURN", "MOUSE_DOWN": "SCROLL", "MOUSE_UP": "SCROLL",
         "MOUSE:272": "LMB", "MOUSE:273": "RMB",
         "XF86AUDIORAISEVOLUME": "VOL", "XF86AUDIOLOWERVOLUME": "VOL", "XF86AUDIOMUTE": "VOL",
         "XF86AUDIOMICMUTE": "MIC", "XF86AUDIOPLAY": "PLAY", "XF86AUDIONEXT": "NEXT",
         "XF86AUDIOPREV": "PREV", "XF86MONBRIGHTNESSUP": "BRIGHTNESS",
         "XF86MONBRIGHTNESSDOWN": "BRIGHTNESS", "CAPS_LOCK": "CAPS"}


def keys_of(expr):
    expr = expr.replace('mod .. "', '"SUPER').replace('"', "")
    return [ALIAS.get(k.strip().upper(), k.strip().upper()) for k in expr.split("+")]


# Cheatsheet rows -> normalised key lists ("Super + H / J / K / L" covers each of H J K L)
covered = []
for r in rows.splitlines():
    m = re.match(r"\s{2}(\S.*?)\s{2,}\S", r)
    if not m:
        continue
    parts = [p.strip().upper() for p in m.group(1).split("+")]
    # "/" alone is the key itself; anywhere else it separates alternatives (H / J / K / L)
    alts = [["/"] if p == "/" else p.replace(" ", "").split("/") for p in parts]
    covered.append(alts)


def on_sheet(keys):
    for alts in covered:
        if len(alts) != len(keys):
            continue
        if all(k in a or any(k in x.split() or k == x for x in a) or
               any(k in x for x in a if len(k) > 2) for k, a in zip(keys, alts)):
            return True
    return False


missing, in_loop, in_submap = [], False, False
for n, line in enumerate(lua, 1):
    s = line.strip()
    if s.startswith("for ") and s.endswith("do"):
        in_loop = True
    elif in_loop and s == "end":
        in_loop = False
    if s.startswith("hl.define_submap("):
        in_submap = True
    elif in_submap and s == "end)":
        in_submap = False
    m = re.match(r"hl\.bind\((.+?),\s*(hl\.dsp|function)", s)
    if not m or in_loop or in_submap or ".. key" in m.group(1):
        continue
    keys = keys_of(m.group(1))
    if not on_sheet(keys):
        missing.append(f"  line {n}: {' + '.join(keys)}")

if missing:
    print("keybinds: bind(s) in hyprland.lua with no row on the Super+? cheatsheet")
    print("\n".join(missing))
    print("  add a row to home/private_dot_local/private_bin/executable_keybind-help.sh")
    sys.exit(1)
print("keybinds ok: every bind has a cheatsheet row")
PY
