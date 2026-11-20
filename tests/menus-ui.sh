#!/usr/bin/env bash
# menus-ui: tests for the window switcher, the wallpaper picker and the logo menu
# (modules/winswitch, modules/wallpaper, modules/logomenu). No compositor: each module's REAL
# panel is rendered from a fixture under Quickshell on Qt's offscreen platform with the real Theme,
# one PNG per board state, plus geometry and visibility probes.
#   1  unit tests     qmltestrunner on js/ (models, argv builders, state machine) and unittest on py/
#   2  qmllint        every .qml, resolved against a generated qs/ tree
#   3  static rules   no hex colours, no PUA, argv-only exec, no network, no loops, icons in the registry
#   4  scenes         winswitch, wallpaper, logomenu: probes + PNGs in $SHOTS_DIR
# Tools: quickshell and Qt6 qmltestrunner/qmllint, found on PATH or in the nix store, else built
# from nixpkgs. With none, the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/menx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }
MODS="winswitch wallpaper logomenu"

# ---- tools -------------------------------------------------------------------------------
works() { "$1" -help >/dev/null 2>&1 || "$1" --help >/dev/null 2>&1; }
nixbin() { nix build --no-link --print-out-paths "nixpkgs#$1" 2>/dev/null | head -1; }
QS="${QS:-$(command -v quickshell || true)}"
[ -n "$QS" ] || { p="$(nixbin quickshell)"; [ -n "$p" ] && QS="$p/bin/quickshell"; }
QTD=""
if command -v qmltestrunner >/dev/null && works qmltestrunner; then QTR="$(command -v qmltestrunner)"; QML_LINT="$(command -v qmllint)"
else
  QTD="${QTD_DIR:-$(ls -d /nix/store/*-qtdeclarative-6.*[0-9] 2>/dev/null | grep -v -- '-dev$' | tail -1)}"
  [ -x "${QTD:+$QTD/bin/qmltestrunner}" ] || QTD="$(nixbin qt6.qtdeclarative)"
  QTR="${QTD:+$QTD/bin/qmltestrunner}"; QML_LINT="${QTD:+$QTD/bin/qmllint}"
fi
if [ -z "$QS" ] || [ -z "${QTR:-}" ]; then
  echo "SKIP menus-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

# SCENES_ONLY=1 skips 1-3 (a quick render loop); ONLY=<module> limits the scenes to one module
# ---- 1. unit tests -----------------------------------------------------------------------
[ -n "${SCENES_ONLY:-}" ] || for m in $MODS; do
  res="$(timeout 120 "$QTR" -input "$mod/$m/tst" 2>&1)"
  echo "$res" | grep -E '^(FAIL|Totals)'
  echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: $m" || bad "1 qmltestrunner: $m"
  res="$(python3 -I -W ignore -m unittest discover -s "$mod/$m/tst" -p 'test_*.py' 2>&1 | tail -4)"
  if echo "$res" | grep -q '^OK'; then ok "1 unittest: $m"; else echo "$res"; bad "1 unittest: $m"; fi
done

# ---- 2. qmllint --------------------------------------------------------------------------
mkqmldir() { # dir module
  ( cd "$1" && { echo "module $2"; for f in *.qml; do [ -e "$f" ] || continue; n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
}
if [ -n "${SCENES_ONLY:-}" ]; then :
elif [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules/bar"
  for m in theme common barpop $MODS; do mkdir -p "$lint/modules/$m"; cp "$mod/$m/"*.qml "$lint/modules/$m/"; done
  for m in $MODS; do
    cp -r "$mod/$m/js" "$lint/modules/$m/js"; cp -r "$mod/$m/parts" "$lint/modules/$m/parts"
  done
  cp -r "$mod/barpop/js" "$lint/modules/barpop/js"; cp -r "$mod/bar/js" "$lint/modules/bar/js"
  cp "$mod/theme/Palette.qml.tmpl" "$lint/modules/theme/Palette.qml"
  sed -i 's/{{ \.palette\.[a-z_]* }}/#000000/' "$lint/modules/theme/Palette.qml"; rm -f "$lint/modules/theme/Palette.qml.tmpl"
  cp -r "$dots/services" "$lint/services"
  for m in theme common barpop $MODS; do mkqmldir "$lint/modules/$m" qs.modules.$m; done
  for m in $MODS; do mkqmldir "$lint/modules/$m/parts" qs.modules.$m.parts; done
  mkqmldir "$lint/services" qs.services
  qsq="$(dirname "$(dirname "$(readlink -f "$QS")")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # the window type and its grouped properties (margins, anchors) are what qmllint cannot resolve
  panels=(); pops=()
  for m in $MODS; do
    for f in "$lint/modules/$m/"*.qml "$lint/modules/$m/parts/"*.qml; do
      [ -e "$f" ] || continue
      case "$f" in */WinSwitcher.qml|*/WallpaperPicker.qml|*/LogoMenu.qml|*/Dispatcher.qml) pops+=("$f");; *) panels+=("$f");; esac
    done
  done
  lintout="$("$QML_LINT" "${lintimp[@]}" "${panels[@]}" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable --signal-handler-parameters disable "${pops[@]}" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
[ -n "${SCENES_ONLY:-}" ] || {
dirs=""; for m in $MODS; do dirs="$dirs $mod/$m"; done
srcs="$(find $dirs \( -name '*.qml' -o -name '*.js' \) ! -path '*/tst/*')"
qmls="$(find $dirs -name '*.qml' ! -path '*/tst/*')"
if grep -nE '#[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 hex colour in a source (use Theme.color.*)"; else ok "3 no hex colours"; fi
if grep -nE 'font\.family:\s*"|Nerd' $srcs; then bad "3 hard-coded font"; else ok "3 no hard-coded font"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' $dirs 2>/dev/null | grep .; then bad "3 private-use codepoint"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $srcs | grep -vE 'execDetached\(\['; then bad "3 execDetached not an argv array"; else ok "3 no exec but argv arrays"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|SplitParser' $srcs; then bad "3 a shell is used"; else ok "3 no shell"; fi
if grep -rnE 'shell=True|os\.system|shlex' $(find $dirs -name '*.py' ! -path '*/tst/*'); then bad "3 a python shell"; else ok "3 python runs argv only"; fi
# the only processes are the Dispatchers (one copy per module, byte-identical), running an argv a js/ builder made
procs="$(grep -lE 'Process *\{' $srcs | xargs -r -n1 basename | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
[ "$procs" = " 3 Dispatcher.qml;" ] && ok "3 Process only in Dispatcher" || bad "3 Process outside Dispatcher: $procs"
if [ "$(for m in $MODS; do md5sum "$mod/$m/Dispatcher.qml"; done | cut -d' ' -f1 | sort -u | wc -l)" -le 1 ]; then ok "3 the Dispatchers are one file"; else bad "3 Dispatcher copies differ"; fi
if grep -nEi 'sendmail|smtp|chat\.postMessage|api\.github|XMLHttpRequest|http://|https://' $srcs $(find $dirs -name '*.py' ! -path '*/tst/*') | grep -vE '^\S+:[0-9]+:\s*(//|#)'; then bad "3 a network or send path"; else ok "3 no network or send path"; fi
if grep -rInE 'green|#[0-9a-f]*00ff00' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 green appears"; else ok "3 no green"; fi
if grep -nE '\bIcon\s*\{' $qmls; then bad "3 Icon{} used (use Gly { box: N })"; else ok "3 icons sized by box (Gly)"; fi
if grep -nE 'Animation|SequentialAnimation|loops:\s*Animation.Infinite|dcPulse|sw-spin' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 an animation loop (nothing pulses or spins)"; else ok "3 nothing pulses"; fi
if grep -rIniE 'pnow|proficient|kaarbaaz|websleak|code42|contabo|hostinger' $dirs "$root/docs/shell/specs/menus.md" "$root/tests/menus-ui.sh" | grep -v 'grep -rIniE'; then bad "3 a company name (public repo)"; else ok "3 no company names"; fi
miss="$(python3 -I - "$mod/common/PhosphorIcons.qml" "$mod" $MODS <<'PY'
import os, re, sys
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(sys.argv[1]).read(), re.M))
used = set()
for m in sys.argv[3:]:
    for dp, dn, fn in os.walk(os.path.join(sys.argv[2], m)):
        dn[:] = [x for x in dn if x not in ("tst", "py")]
        for f in fn:
            src = open(os.path.join(dp, f)).read()
            if f.endswith(".qml"):
                for ln in src.splitlines():
                    if re.search(r'\b(?:Icon|Gly)\s*\{', ln):
                        used.update(re.findall(r'\bname:\s*"([a-z][a-z0-9_-]*)"', ln))
            elif f.endswith(".js"):
                for mm in re.finditer(r'\bicon:\s*"([a-z][a-z0-9-]*)"', src):
                    used.add(mm.group(1))
print(" ".join(sorted(used - names)))
PY
)"
[ -z "$miss" ] && ok "3 every icon name resolves in PhosphorIcons" || bad "3 icons missing from the registry (run python3 tools/gen-phosphor-qml.py): $miss"
}

# ---- 4. scenes ---------------------------------------------------------------------------
shellroot="$work/root"; mkdir -p "$shellroot/modules/theme" "$shellroot/modules/bar"
cp "$mod/theme/Theme.qml" "$mod/theme/Tokens.qml" "$mod/theme/qmldir" "$shellroot/modules/theme/"
python3 -I - "$root/home/.chezmoidata/palette.yaml" "$mod/theme/Palette.qml.tmpl" "$shellroot/modules/theme/Palette.qml" <<'PY'
import re, sys
vals = {}
top = False
for ln in open(sys.argv[1]):
    if re.match(r'^palette:\s*$', ln): top = True; continue
    m = re.match(r'^  ([a-z_]+):\s*"(#[0-9a-fA-F]{6})"', ln)
    if top and m: vals[m.group(1)] = m.group(2)
t = open(sys.argv[2]).read()
open(sys.argv[3], "w").write(re.sub(r'\{\{ \.palette\.([a-z_]+) \}\}', lambda m: vals[m.group(1)], t))
PY
cp -r "$mod/common" "$shellroot/modules/common"
python3 -I "$root/tools/gen-phosphor-qml.py" --stdout > "$shellroot/modules/common/PhosphorIcons.qml"
for m in barpop wsswitch $MODS; do ln -s "$mod/$m" "$shellroot/modules/$m"; done
ln -s "$mod/bar/js" "$shellroot/modules/bar/js"
ln -s "$dots/services" "$shellroot/services"
mkdir -p "$work/state" "$work/out"

# test wallpapers: plain gradient PNGs, written with the standard library
wall="$work/walls"; mkdir -p "$wall"
python3 -I - "$wall" <<'PY'
import struct, sys, zlib
def png(path, c1, c2, w=320, h=200):
    rows = b""
    for y in range(h):
        t = y / (h - 1)
        px = bytes(int(a + (b - a) * t) for a, b in zip(c1, c2)) * w
        rows += b"\0" + px
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
cols = [((20, 50, 70), (40, 90, 120)), ((60, 30, 90), (110, 60, 140)), ((15, 35, 55), (30, 70, 110)), ((90, 50, 30), (150, 90, 50)),
        ((100, 30, 50), (160, 60, 70)), ((25, 25, 70), (55, 55, 120)), ((110, 70, 30), (170, 110, 60)), ((180, 200, 210), (210, 225, 230)),
        ((80, 30, 100), (130, 60, 150)), ((15, 25, 40), (30, 60, 90)), ((110, 60, 40), (160, 80, 60)), ((30, 80, 110), (60, 120, 160)),
        ((120, 80, 40), (170, 120, 70)), ((50, 40, 100), (80, 70, 150)), ((15, 30, 60), (40, 70, 130)), ((110, 40, 40), (150, 70, 60))]
for i, (a, b) in enumerate(cols):
    png("%s/wallpaper-%02d.png" % (sys.argv[1], i + 1), a, b)
PY

run_scene() {  # MODULE FIXTURE [SCENE FILE, default Scene.qml]
  local m="$1" fixture="$2" file="${3:-Scene}" log="$work/out/$1${3:+-$3}.log"
  rm -f "$shellroot/shell.qml"
  cp "$mod/$m/tst/$file.qml" "$shellroot/shell.qml"
  # the real HOME stays (a wrapped quickshell keeps its GL cache there); the theme is pointed at a
  # file that does not exist, so the scene always renders the built-in default tokens
  env PATH="${FAKE_PATH:+$FAKE_PATH:}$PATH" OUT_DIR="$shots" FIXTURE="$fixture" WALL_DIR="$wall" WALLPAPER_DIR="$wall" XDG_RUNTIME_DIR="$xdg" \
      DOTS_THEME_TOKENS="$work/no-tokens.json" XDG_STATE_HOME="$work/state" \
      timeout 120 "$QS" -p "$shellroot" > "$log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$log"
  grep -a 'PROBE ' "$log" | sed 's/^.*PROBE //' > "$work/out/$m.probes"
}
probe_check() {  # MODULE
python3 -I - "$work/out/$1.probes" "$shots" "$1" <<'PY'
import json, os, sys
probes, shots, which = sys.argv[1], sys.argv[2], sys.argv[3]
fails = []
cases = {}
try:
    for ln in open(probes):
        tag, js = ln.strip().split(" ", 1)
        cases[tag] = json.loads(js)
except Exception as e:
    fails.append("no probes (%s)" % e)
def vis(m, name): return [e for e in m["names"].get(name, []) if e["visible"]]
def texts(m, name): return [e.get("text", "") for e in vis(m, name)]
def need(cond, msg):
    if not cond: fails.append(msg)
def pngs(tags):
    for t in tags:
        need(t in cases, "%s: state missing" % t)
        f = os.path.join(shots, "%s-%s.png" % (which, t))
        need(os.path.isfile(f) and os.path.getsize(f) > 2000, "%s: PNG missing or empty" % t)
# a strip is clipped by its body: parts of a card beyond the panel are scrolled out, not overflowing
INSIDE_CARDS = ("winCard", "winTitle", "profileTag", "ticketTag", "badgeTag", "suggestTag", "winRow", "gly")
def inside(t, m, skip=()):
    w, h = m["card"]["w"], m["card"]["h"]
    for name, es in m["names"].items():
        if name in skip: continue
        for e in es:
            if e["visible"] and e["w"] > 0 and e["h"] > 0:
                need(e["x"] >= -8 and e["x"] + e["w"] <= w + 8, "%s: %s overflows the card horizontally %s" % (t, name, e))
                need(e["y"] >= -16 and e["y"] + e["h"] <= h + 16, "%s: %s overflows the card vertically %s" % (t, name, e))
    for e in m["names"].get("gly", []):
        if e["visible"]:
            need(e["w"] == e["box"] and 0.9 * e["box"] <= e["px"] <= 1.1 * e["box"], "%s: glyph %s paints %spx" % (t, e["box"], e.get("px")))

if which == "winswitch":
    pngs("cycle cycle-wrap group-closed group-open filter nomatch single many locked unlock ai-thinking ai-done ai-fallback confirm undo msg list grid".split())
    for t, m in cases.items():
        if t != "locked": need(m["card"]["visible"], "%s: panel hidden" % t)
        inside(t, m, skip=INSIDE_CARDS)
    d = cases.get("cycle")
    if d:
        need(len(vis(d, "winCard")) == 10, "cycle: ten cards, got %d" % len(vis(d, "winCard")))
        need(d["card"]["w"] == 893, "cycle: panel %s wide, board says 893" % d["card"]["w"])
        c = vis(d, "winCard")
        need(c[1]["w"] == 200 and c[1]["h"] == 158, "cycle: card %sx%s, board says 200x158" % (c[1]["w"], c[1]["h"]))
        need(c[3]["x"] - c[2]["x"] == 212, "cycle: cards 212 apart")           # the selected one is scaled 1.06
        need(len(vis(d, "scopePill")) == 4 and not vis(d, "filterBox"), "cycle: four scope pills, no filter")
        need(len(vis(d, "hint")) == 4, "cycle: four key hints")
        need(len(texts(d, "capTitle")) == 1, "cycle: one caption title")
        need(len(vis(d, "ticketTag")) >= 3, "cycle: ticket chips on the task windows")
    g = cases.get("group-closed")
    if g:
        need(len(vis(g, "badgeTag")) == 1 and texts(g, "badgeTag") == ["3 tabs"], "group-closed: a 3 tabs badge")
    o = cases.get("group-open")
    if o:
        need(len(vis(o, "groupChip")) == 1 and not vis(o, "scopePill"), "group-open: group chip replaces the scope pills")
        need(len(vis(o, "winCard")) >= 3 and texts(o, "badgeTag")[:1] == ["tab 1/3"], "group-open: tab cards")
    f = cases.get("filter")
    if f:
        need(len(vis(f, "filterBox")) == 1 and not vis(f, "scopePill"), "filter: filter box replaces the scope pills")
        need(len(vis(f, "winCard")) == 1, "filter: one match")
        need(texts(f, "qCount") == ["1 of 10"], "filter: count %s" % texts(f, "qCount"))
    n = cases.get("nomatch")
    if n:
        need(len(vis(n, "noMatch")) == 1 and not vis(n, "winCard"), "nomatch: says so")
    s = cases.get("single")
    if s:
        need(len(vis(s, "winCard")) == 1, "single: one card")
        need(texts(s, "capTitle") == ["Nothing else open"], "single: caption %s" % texts(s, "capTitle"))
    mn = cases.get("many")
    if mn:
        need(len(vis(mn, "winCard")) == 24, "many: 24 cards in the strip")
        need(mn["card"]["w"] == 893, "many: strip panel stays 893 wide")
        need("+17 more" in "".join(texts(mn, "capCount")), "many: more count %s" % texts(mn, "capCount"))
    lk = cases.get("locked")
    if lk:
        need(not lk["card"]["visible"], "locked: the panel is not visible")
        for name in ("winCard", "winTitle", "capTitle", "ticketTag", "profileTag", "status", "hint", "scopePill"):
            need(not vis(lk, name), "locked: %s rendered while locked" % name)
        need(not lk["names"].get("winTitle"), "locked: no title item exists at all")
    u = cases.get("unlock")
    if u:
        need(not vis(u, "ticketTag"), "unlock: no ticket chips after unlock")
        titles = texts(u, "winTitle")
        need(all(t in ("Terminal", "Editor", "Browser", "Mail", "Chat", "Notes", "Media", "Files", "App", "Settings") for t in titles),
             "unlock: titles are app names only, got %s" % titles)
        need(texts(u, "capTitle") == ["Browser"], "unlock: caption is the app name, got %s" % texts(u, "capTitle"))
        need(len(vis(u, "status")) == 1 and "unlocked" in texts(u, "status")[0], "unlock: status says why")
    a1, a2, a3 = cases.get("ai-thinking"), cases.get("ai-done"), cases.get("ai-fallback")
    if a1: need(texts(a1, "qCount") == ["thinking"] and len(vis(a1, "winCard")) == 10, "ai-thinking: all cards, 'thinking'")
    if a2: need(texts(a2, "qCount") == ["3 ranked"] and len(vis(a2, "suggestTag")) == 1, "ai-done: three ranked, one suggested")
    if a3: need(len(vis(a3, "winCard")) == 2, "ai-fallback: fuzzy matches only")
    cf = cases.get("confirm")
    if cf: need(len(vis(cf, "status")) == 1 and "safe list" in texts(cf, "status")[0], "confirm: safe list status")
    un = cases.get("undo")
    if un: need(len(vis(un, "status")) == 1 and "Undo for 8 s" in texts(un, "status")[0] and len(vis(un, "winCard")) == 9, "undo: nine cards and an Undo status")
    ls = cases.get("list")
    if ls:
        need(ls["card"]["w"] == 780, "list: panel %s wide, board says 780" % ls["card"]["w"])
        need(len(vis(ls, "winRow")) == 8 and all(e["h"] == 44 for e in vis(ls, "winRow")), "list: eight 44 px rows")
    gd = cases.get("grid")
    if gd:
        need(len(vis(gd, "winCard")) == 8 and len(set(round(e["x"] / 212.0) for e in vis(gd, "winCard"))) == 4, "grid: a page of eight in four columns")

if which == "logomenu":
    pngs("healthy focus-note degraded degraded-hypr safe filter filter-none logout logout-2 salah selected".split())
    for t, m in cases.items():
        need(m["card"]["visible"] and m["card"]["w"] == 304, "%s: card %s wide, board says 304" % (t, m["card"]["w"]))
        inside(t, m)
        need(len(vis(m, "menuRow")) + len(vis(m, "sessionBtn")) <= 17, "%s: over the 17 row cap" % t)
        need(not any("task" in x.lower() or "ticket" in x.lower() for x in texts(m, "rowLabel")), "%s: a task name in a row" % t)
    h = cases.get("healthy")
    if h:
        need(texts(h, "headTitle") == ["Shell ok"] and texts(h, "headRight") == ["up 2d 4h"], "healthy: header %s %s" % (texts(h, "headTitle"), texts(h, "headRight")))
        need(len(vis(h, "menuRow")) == 6 + 4 + 1, "healthy: 6 GO rows, 4 fix rows and settings, got %d" % len(vis(h, "menuRow")))
        need(all(e["h"] == 32 for e in vis(h, "menuRow")), "healthy: rows 32 tall")
        need(len(vis(h, "modeChip")) == 6 and len(vis(h, "sessionBtn")) == 2, "healthy: six modes, lock and logout")
        need(all(e["h"] == 44 for e in vis(h, "sessionBtn")), "healthy: session buttons 44 tall")
        need(not vis(h, "noteText") and not vis(h, "countdown") and not vis(h, "filterRow"), "healthy: no note, countdown or filter")
        need(texts(h, "rowLabel")[0] == "Control centre", "healthy: first row is the control centre")
    d = cases.get("degraded")
    if d:
        need(texts(d, "headTitle") == ["Shell not responding"], "degraded: header %s" % texts(d, "headTitle"))
        need(len(vis(d, "askRow")) == 1 and not vis(d, "noteText"), "degraded: ask row, no hint yet")
        need("Reload shell" in texts(d, "rowLabel")[6:8], "degraded: the broken row is first under FIX")
    dh = cases.get("degraded-hypr")
    if dh:
        need(texts(dh, "headTitle") == ["Hyprland not responding"] and len(vis(dh, "noteText")) == 1, "degraded-hypr: header and the local hint")
        need(texts(dh, "rowLabel")[6] == "Reload Hyprland", "degraded-hypr: Reload Hyprland moved to the top of FIX")
    sf = cases.get("safe")
    if sf:
        need(texts(sf, "headTitle") == ["Safe mode"] and not vis(sf, "modeChip"), "safe: header, no modes")
        need(texts(sf, "rowLabel")[0] == "Back to full shell", "safe: one way back on top")
    f = cases.get("filter")
    if f:
        need(len(vis(f, "filterRow")) == 1 and not vis(f, "modeChip") and not vis(f, "sessionBtn"), "filter: filter row replaces the sections")
        need(len(vis(f, "menuRow")) >= 3, "filter: matches")
    fn = cases.get("filter-none")
    if fn: need(texts(fn, "emptyText") == ["Nothing here. Esc"] and not vis(fn, "menuRow"), "filter-none: says so")
    lo = cases.get("logout")
    if lo:
        need(len(vis(lo, "countdown")) == 1 and not vis(lo, "sessionBtn"), "logout: the session row turns into the countdown")
        need(texts(lo, "countdown") == ["3... 2... 1..."] and len(vis(lo, "cancelBtn")) == 1, "logout: 3... 2... 1... and Cancel")
    sa = cases.get("salah")
    if sa:
        need(texts(sa, "headTitle") == ["Salah active"] and texts(sa, "headRight") == ["then Asr 16:05"], "salah: header")
        need(len([e for e in vis(sa, "modeChip") if e["text"]]) == 6, "salah: chips still listed")
        need(len(vis(sa, "noteText")) == 1 and "ends 13:42" in texts(sa, "noteText")[0], "salah: note says when it ends")
    fo = cases.get("focus-note")
    if fo: need(len(vis(fo, "noteText")) == 1 and "Focus breaks through" in texts(fo, "noteText")[0], "focus-note: note")

if which == "wallpaper":
    pngs("default preview committed empty loading large tuned untuned missing shuffle paused monitors modepal salah ai keys".split())
    GRID_PARTS = ("tile", "tileName", "starBtn", "suggestBar", "gly", "scrollMark", "legend")
    for t, m in cases.items():
        need(m["card"]["visible"] and (m["card"]["w"], m["card"]["h"]) == (960, 640), "%s: card %sx%s, board says 960x640" % (t, m["card"]["w"], m["card"]["h"]))
        inside(t, m, skip=GRID_PARTS)
        if t not in ("empty",):
            need(len(vis(m, "swatch")) == 5, "%s: five swatches" % t)
            need(len(vis(m, "paletteSeg")) == 3, "%s: three palette sources" % t)
        need(len(vis(m, "targetBtn")) == 1 and len(vis(m, "shuffleBtn")) == 1 and len(vis(m, "lockSwitch")) == 1 and len(vis(m, "setBtn")) == 1, "%s: bottom bar controls" % t)
    d = cases.get("default")
    if d:
        tiles = vis(d, "tile")
        need(len(tiles) >= 12, "default: %d tiles in view" % len(tiles))
        need(all(e["w"] == 133 for e in tiles), "default: tiles 133 wide")
        need(len(set(e["x"] for e in tiles)) == 4, "default: four columns")
        need(texts(d, "previewTag") == ["Current"], "default: preview says Current, got %s" % texts(d, "previewTag"))
        need(texts(d, "contrastText") == ["14.1:1 passes AA"], "default: contrast %s" % texts(d, "contrastText"))
        need(not vis(d, "toast") and not vis(d, "notice") and not vis(d, "tunedTag"), "default: no toast, notice or tuned tag")
        need(len(vis(d, "midHint")) == 1, "default: key hint in the middle")
        need(vis(d, "preview")[0]["h"] == 130 and vis(d, "miniShell")[0]["h"] == 128, "default: preview 130 and mini shell 128 tall")
        pw = vis(d, "paletteSeg")[0]
        need(vis(d, "contrastRow")[0]["y"] + vis(d, "contrastRow")[0]["h"] <= pw["y"], "default: the contrast row clears the palette source")
    p = cases.get("preview")
    if p:
        need(texts(p, "previewTag") == ["Previewing"] and texts(p, "previewName") == ["wallpaper-06"], "preview: previewing wallpaper-06")
    c = cases.get("committed")
    if c:
        need(len(vis(c, "toast")) == 1 and texts(c, "toast") == ["Wallpaper set."], "committed: toast")
    e = cases.get("empty")
    if e:
        need(len(vis(e, "emptyState")) == 1 and len(vis(e, "emptyPane")) == 1 and not vis(e, "tile"), "empty: empty state, no tiles")
        need(not vis(e, "miniShell") and not vis(e, "swatch"), "empty: no preview")
    l = cases.get("loading")
    if l: need(len(vis(l, "tile")) >= 12 and all(not x for x in texts(l, "tileName") if x), "loading: skeleton tiles, no names")
    g = cases.get("large")
    if g:
        need(texts(g, "searchCount") == ["10 of 1,284"], "large: count %s" % texts(g, "searchCount"))
        need(len(vis(g, "tile")) == 10, "large: ten matches shown")
    t = cases.get("tuned")
    if t:
        need(len(vis(t, "tunedTag")) == 1 and len(vis(t, "untuneBtn")) == 1, "tuned: tuned tag and Show untuned")
        need(texts(t, "contrastText") == ["4.5:1 passes AA"], "tuned: %s" % texts(t, "contrastText"))
    u = cases.get("untuned")
    if u:
        need(texts(u, "contrastText") == ["2.6:1 fails AA"] and not vis(u, "tunedTag"), "untuned: fails AA, no tag")
    mi = cases.get("missing")
    if mi: need(len(vis(mi, "folderBtn")) == 1 and len([x for x in vis(mi, "tile")]) >= 12, "missing: tiles and the folder button")
    sh = cases.get("shuffle")
    if sh: need(len(vis(sh, "midNext")) == 1 and not vis(sh, "midHint"), "shuffle: next time in the middle")
    pa = cases.get("paused")
    if pa: need(len(vis(pa, "midPaused")) == 1 and len(vis(pa, "notice")) == 1, "paused: paused text and notice")
    mo = cases.get("monitors")
    if mo: need(len(vis(mo, "targetBtn")) == 1, "monitors: target button")
    mp = cases.get("modepal")
    if mp: need(len(vis(mp, "notice")) == 1 and "Mode palette" in texts(mp, "notice")[0], "modepal: notice")
    sa = cases.get("salah")
    if sa:
        need(len(vis(sa, "notice")) == 1 and "Salah mode" in texts(sa, "notice")[0], "salah: notice")
        need(vis(sa, "tagRow")[0]["y"] + vis(sa, "tagRow")[0]["h"] <= vis(sa, "paletteSeg")[0]["y"] - 18, "salah: the right pane fits under the notice")
    ai = cases.get("ai")
    if ai: need(len(vis(ai, "suggestBar")) == 1, "ai: suggestion on a tile")
    ky = cases.get("keys")
    if ky: need(len(vis(ky, "legend")) == 1, "keys: legend")

if fails:
    print("\n".join("  " + f for f in fails)); sys.exit(1)
PY
}

scene_errors() {  # MODULE [LOG SUFFIX]
  local errs; errs="$(grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|is not defined|Required property|module .* not installed' "$work/out/$1${2:+-$2}.log" | head -8)"
  if [ -n "$errs" ]; then echo "$errs"; bad "4 QML errors in the $1 ${2:-scene} log"; else ok "4 no QML errors in the $1 ${2:-scene} log"; fi
}
# a stand-in `pidof` decides whether "hyprlock is running", so the lock gate is tested both ways
fakebin="$work/fakebin"; mkdir -p "$fakebin/unlocked" "$fakebin/locked"
printf '#!/bin/sh\nexit 1\n' > "$fakebin/unlocked/pidof"; printf '#!/bin/sh\nexit 0\n' > "$fakebin/locked/pidof"
chmod +x "$fakebin"/*/pidof
smoke() {  # MODULE PATTERN [unlocked|locked]: the real controller loads, the log has the SMOKE line, and it ends cleanly
  local fake="${3:-unlocked}"
  FAKE_PATH="$fakebin/$fake" run_scene "$1" /dev/null Smoke
  local line; line="$(grep -a 'SMOKE ' "$work/out/$1-Smoke.log" | sed 's/^.*SMOKE //' | tr '\n' ';')"
  if echo "$line" | grep -qE "$2"; then ok "4 $1 wiring smoke ($fake): $line"; else echo "  got: $line"; bad "4 $1 wiring smoke ($fake)"; fi
  scene_errors "$1" Smoke
}

if [ -z "${ONLY:-}" ] || [ "$ONLY" = winswitch ]; then
  run_scene winswitch "$mod/winswitch/tst/fixtures/windows.json"
  probe_check winswitch && ok "4 winswitch probes: geometry and visibility on every state" || bad "4 winswitch probes"
  scene_errors winswitch
  smoke winswitch 'flip phase=idle;pressed phase=pending;held phase=shown probeDone=true locked=false shown=true open=winswitch mode=(strip|single);released phase=idle open=winswitch:;' unlocked
  smoke winswitch 'flip phase=idle;pressed phase=pending;held phase=idle probeDone=true locked=true shown=false open= mode=locked;released phase=idle' locked
fi

if [ -z "${ONLY:-}" ] || [ "$ONLY" = wallpaper ]; then
  run_scene wallpaper /dev/null
  probe_check wallpaper && ok "4 wallpaper probes: geometry and visibility on every state" || bad "4 wallpaper probes"
  scene_errors wallpaper
  smoke wallpaper 'wallpaper mode=grid tiles=1[0-9]+ folder=walls sel=true'
fi

if [ -z "${ONLY:-}" ] || [ "$ONLY" = logomenu ]; then
  run_scene logomenu /dev/null
  probe_check logomenu && ok "4 logomenu probes: geometry and visibility on every state" || bad "4 logomenu probes"
  scene_errors logomenu
  smoke logomenu 'logomenu head=Shell ok rows=1[0-9] mode=Heavy work sel=control'
fi

[ "$fails" -eq 0 ] && { echo "menus-ui ok ($shots)"; exit 0; }
echo "menus-ui: $fails failure(s)"; exit 1
