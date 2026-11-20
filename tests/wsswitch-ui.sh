#!/usr/bin/env bash
# wsswitch-ui: tests for the profile and workspace switcher (modules/wsswitch). No compositor:
# it renders the REAL WsPanel from a fixture under Quickshell on Qt's offscreen platform with the
# real Theme, writes one PNG per board frame and state, and asserts geometry and visibility probes.
#   1  qmltestrunner  js/Model (profiles, needs, filter, keyboard) and js/Dispatch (argv, ok)
#   2  qmllint        every .qml, resolved against a generated qs/ tree
#   3  static rules   no hex colours, no PUA, argv-only exec, no network, icons in the registry
#   4  scenes         pop, hover, move, empty, needs, salah, error, locked, full, grid, map: probes + PNGs
# PNGs go to $SHOTS_DIR (default: a temp dir). Tools: quickshell and Qt6 qmltestrunner/qmllint,
# found on PATH or in the nix store, else built from nixpkgs. With none, the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
ws="$mod/wsswitch"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/wsx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }

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
  echo "SKIP wsswitch-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$ws/tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: wsswitch" || bad "1 qmltestrunner: wsswitch"

# ---- 2. qmllint --------------------------------------------------------------------------
mkqmldir() { # dir module
  ( cd "$1" && { echo "module $2"; for f in *.qml; do [ -e "$f" ] || continue; n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
}
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules/bar"
  for m in theme common barpop wsswitch; do mkdir -p "$lint/modules/$m"; cp "$mod/$m/"*.qml "$lint/modules/$m/"; done
  cp -r "$ws/js" "$lint/modules/wsswitch/js"; cp -r "$ws/parts" "$lint/modules/wsswitch/parts"; rm -f "$lint/modules/wsswitch/tst"
  cp -r "$mod/barpop/js" "$lint/modules/barpop/js"; cp -r "$mod/bar/js" "$lint/modules/bar/js"
  cp "$mod/theme/Palette.qml.tmpl" "$lint/modules/theme/Palette.qml"
  sed -i 's/{{ \.palette\.[a-z_]* }}/#000000/' "$lint/modules/theme/Palette.qml"; rm -f "$lint/modules/theme/Palette.qml.tmpl"
  cp -r "$mod/overview" "$lint/modules/overview"; rm -rf "$lint/modules/overview/tst"
  cp -r "$dots/services" "$lint/services"
  for m in theme common barpop wsswitch overview; do mkqmldir "$lint/modules/$m" qs.modules.$m; done
  for d in parts pages; do [ -d "$lint/modules/overview/$d" ] && mkqmldir "$lint/modules/overview/$d" qs.modules.overview.$d; done
  mkqmldir "$lint/modules/wsswitch/parts" qs.modules.wsswitch.parts
  mkqmldir "$lint/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # the window type and its grouped properties (margins, anchors) are what qmllint cannot resolve
  files=("$lint"/modules/wsswitch/*.qml "$lint"/modules/wsswitch/parts/*.qml)
  panels=(); pops=()
  for f in "${files[@]}"; do case "$f" in *WsSwitcher.qml) pops+=("$f");; *) panels+=("$f");; esac; done
  lintout="$("$QML_LINT" "${lintimp[@]}" "${panels[@]}" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "${pops[@]}" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
srcs="$(find "$ws" -name '*.qml' ! -path '*/tst/*') $(find "$ws" -name '*.js' ! -path '*/tst/*')"
if grep -nE '#[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 hex colour in a source (use Theme.color.*)"; else ok "3 no hex colours"; fi
if grep -nE 'font\.family:\s*"|Nerd' $srcs; then bad "3 hard-coded font"; else ok "3 no hard-coded font"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$ws" 2>/dev/null | grep .; then bad "3 private-use codepoint"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $srcs | grep -vE 'execDetached\(\["'; then bad "3 execDetached not an argv array literal"; else ok "3 no exec but argv arrays"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|SplitParser' $srcs; then bad "3 a shell is used"; else ok "3 no shell"; fi
# the only process is the Dispatcher, and it runs an argv built by js/Dispatch.js
procs="$(grep -lE 'Process *\{' $srcs | xargs -r -n1 basename | tr '\n' ' ')"
[ "$procs" = "Dispatcher.qml " ] && ok "3 Process only in Dispatcher" || bad "3 Process outside Dispatcher: $procs"
if grep -nEi 'sendmail|smtp|chat\.postMessage|api\.github|XMLHttpRequest|http://|https://' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 a network or send path"; else ok "3 no network or send path"; fi
if grep -rInE 'green|#[0-9a-f]*00ff00' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 green appears"; else ok "3 no green"; fi
if grep -nE '\bIcon\s*\{' $(find "$ws" -name '*.qml' ! -path '*/tst/*'); then bad "3 Icon{} used (use Gly { box: N })"; else ok "3 icons sized by box (Gly)"; fi
if grep -nE 'Animation|SequentialAnimation|loops:\s*Animation.Infinite|dcPulse' $srcs; then bad "3 an animation loop (nothing pulses)"; else ok "3 nothing pulses"; fi
miss="$(python3 -I - "$mod/common/PhosphorIcons.qml" "$ws" <<'PY'
import os, re, sys
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(sys.argv[1]).read(), re.M))
used = set()
for dp, dn, fn in os.walk(sys.argv[2]):
    dn[:] = [x for x in dn if x != "tst"]
    for f in fn:
        src = open(os.path.join(dp, f)).read()
        if f.endswith(".qml"):
            for ln in src.splitlines():
                if re.search(r'\b(?:Icon|Gly)\s*\{', ln):
                    used.update(re.findall(r'\bname:\s*"([a-z][a-z0-9_-]*)"', ln))
        elif f.endswith(".js"):
            for m in re.finditer(r'\bicon:\s*"([a-z][a-z0-9-]*)"', src):
                used.add(m.group(1))
# the profile icons come from the bar's Profiles.js
for m in re.finditer(r'\bicon:\s*"([a-z][a-z0-9-]*)"', open(os.path.join(sys.argv[2], "..", "bar", "js", "Profiles.js")).read()):
    used.add(m.group(1))
print(" ".join(sorted(used - names)))
PY
)"
[ -z "$miss" ] && ok "3 every icon name resolves in PhosphorIcons" || bad "3 icons missing from the registry (run python3 tools/gen-phosphor-qml.py): $miss"

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
for m in common barpop wsswitch; do ln -s "$mod/$m" "$shellroot/modules/$m"; done
ln -s "$mod/bar/js" "$shellroot/modules/bar/js"
cp "$ws/tst/Scene.qml" "$shellroot/shell.qml"
mkdir -p "$work/home" "$work/out"
env OUT_DIR="$shots" FIXTURE="$ws/tst/fixtures/hypr.json" XDG_RUNTIME_DIR="$xdg" HOME="$work/home" \
    timeout 90 "$QS" -p "$shellroot" > "$work/out/scene.log" 2>&1
sed -i 's/\x1b\[[0-9;]*m//g' "$work/out/scene.log"
grep -a 'PROBE ' "$work/out/scene.log" | sed 's/^.*PROBE //' > "$work/out/scene.probes"

python3 -I - "$work/out/scene.probes" "$shots" <<'PY' && ok "4 probes: geometry and visibility on every frame and state" || bad "4 probes"
import json, os, sys
probes, shots = sys.argv[1], sys.argv[2]
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

tags = """pop-default pop-hover pop-move pop-empty pop-needs pop-salah pop-error pop-locked full-default full-filter
full-nomatch grid-default grid-move grid-needs grid-filter grid-salah map-default map-needs map-empty map-comms map-filter""".split()
for t in tags:
    need(t in cases, "%s: state missing" % t)
    f = os.path.join(shots, "wsswitch-%s.png" % t)
    need(os.path.isfile(f) and os.path.getsize(f) > 2000, "%s: PNG missing or empty" % t)

SIZE = {"pop": (300, 380), "full": (880, 880), "grid": (880, 880), "map": (880, 880)}
for t, m in cases.items():
    w, h = m["card"]["w"], m["card"]["h"]
    kind = t.split("-")[0]
    if t == "pop-hover": need(w == 300, "pop-hover: card is %s wide" % w)
    elif t == "pop-locked": need(w == 380, "pop-locked: card width %s" % w)
    elif kind == "pop": need(w == 360, "%s: popover is %s wide, board says 360" % (t, w))
    else: need((w, h) == (880, 560), "%s: card %sx%s, board says 880x560" % (t, w, h))
    if kind == "pop" and t != "pop-locked": need(h <= 720, "%s: popover %s tall, cap 720" % (t, h))
    # every visible named item sits inside its card
    for name, es in m["names"].items():
        for e in es:
            if e["visible"] and e["w"] > 0 and e["h"] > 0:
                need(e["x"] >= -1 and e["x"] + e["w"] <= w + 1, "%s: %s overflows the card horizontally %s" % (t, name, e))
                if name not in ("wsGroup", "treeBody"):
                    need(e["y"] >= -1 and e["y"] <= h + 1, "%s: %s starts outside the card %s" % (t, name, e))
    # icons paint at their box
    for e in m["names"].get("gly", []):
        if e["visible"]:
            need(e["w"] == e["box"] and 0.9 * e["box"] <= e["px"] <= 1.1 * e["box"], "%s: glyph %s paints %spx" % (t, e["box"], e.get("px")))

d = cases.get("pop-default")
if d:
    need(texts(d, "profName") == ["Dev"], "pop-default: header %s" % texts(d, "profName"))
    need(texts(d, "profTotal") == ["4 windows"], "pop-default: total %s" % texts(d, "profTotal"))
    need(len(vis(d, "stripBtn")) == 7, "pop-default: seven profiles in the strip")
    need(len(vis(d, "winRow")) == 4 and len(vis(d, "wsGroup")) == 1, "pop-default: Dev has one workspace of four windows")
    need(len(vis(d, "moveTarget")) == 7, "pop-default: the selected row offers seven targets")
    need(len(vis(d, "activeTag")) == 1, "pop-default: one ACTIVE tag")
    need(not vis(d, "needsPill") and not vis(d, "salahPill") and not vis(d, "errRow") and not vis(d, "popToast"), "pop-default: no pill, error or toast")
    need(len(vis(d, "stateDot")) == 4, "pop-default: one state dot per window")
    ys = [e["y"] for e in vis(d, "winRow")]
    need(ys == sorted(ys), "pop-default: rows out of order")
    need(len(vis(d, "hint")) >= 4, "pop-default: footer hints %d" % len(vis(d, "hint")))
v = cases.get("pop-hover")
if v:
    need(len(vis(v, "preview")) == 1 and not vis(v, "winRow") and not vis(v, "treeHead"), "pop-hover: preview replaces the tree")
    need(texts(v, "pvName") == ["Web"], "pop-hover: names Web")
    need(len(vis(v, "pvRow")) == 1, "pop-hover: Web has one workspace")
mv = cases.get("pop-move")
if mv:
    need(len(vis(mv, "popToast")) == 1, "pop-move: toast shown inline")
    need(len(vis(mv, "winRow")) == 5, "pop-move: Dev now has five windows")
    need(texts(mv, "profTotal") == ["5 windows"], "pop-move: total %s" % texts(mv, "profTotal"))
e = cases.get("pop-empty")
if e:
    need(len(vis(e, "emptyState")) == 1 and not vis(e, "winRow"), "pop-empty: Nothing open, no rows")
    need(len(vis(e, "openWs")) == 1, "pop-empty: Go to workspace button")
n = cases.get("pop-needs")
if n:
    need(texts(n, "needsPill") == ["2 need you"], "pop-needs: pill %s" % texts(n, "needsPill"))
    need(len(vis(n, "winRow")) == 4, "pop-needs: four agent windows")
    need(len([e for e in vis(n, "stateDot")]) == 4, "pop-needs: dots")
s = cases.get("pop-salah")
if s:
    need(len(vis(s, "salahPill")) == 1, "pop-salah: Salah pill")
    strip = vis(s, "stripBtn")
    need(len(strip) == 7, "pop-salah: strip stays")
x = cases.get("pop-error")
if x:
    need(len(vis(x, "errRow")) == 1, "pop-error: error row")
    need(len(vis(x, "moveTarget")) == 7, "pop-error: row stays selected")
lk = cases.get("pop-locked")
if lk:
    need(len(vis(lk, "lockCard")) == 1, "pop-locked: lock card")
    for name in ("winRow", "treeHead", "profName", "stripBtn", "railBtn", "card", "winTitle", "preview"):
        need(not vis(lk, name), "pop-locked: %s rendered while locked" % name)
f = cases.get("full-default")
if f:
    need(len(vis(f, "railBtn")) == 7 and len(vis(f, "filterBox")) == 1, "full-default: rail and filter bar")
    need(len(vis(f, "winRow")) == 4, "full-default: tree beside the rail")
    need(vis(f, "railBtn")[0]["w"] == 56, "full-default: rail buttons 56 wide")
fl = cases.get("full-filter")
if fl:
    need(len(vis(fl, "resGroup")) >= 4 and len(vis(fl, "resRow")) >= 9, "full-filter: grouped results %d rows" % len(vis(fl, "resRow")))
    need(len(texts(fl, "resultCount")) == 1 and texts(fl, "resultCount")[0].endswith("results"), "full-filter: result count %s" % texts(fl, "resultCount"))
    need(not vis(fl, "winRow"), "full-filter: tree hidden")
nm = cases.get("full-nomatch")
if nm:
    need(len(vis(nm, "noMatch")) == 1 and not vis(nm, "resRow"), "full-nomatch: says so")
g = cases.get("grid-default")
if g:
    need(len(vis(g, "card")) == 7, "grid-default: seven cards")
    need(len(vis(g, "hintCard")) == 1, "grid-default: eighth slot is the filter hint")
    xs = sorted(set(e["x"] for e in vis(g, "card")))
    need(len(xs) == 4, "grid-default: four columns, got %s" % xs)
    need(all(e["h"] == 214 for e in vis(g, "card")), "grid-default: cards 214 tall")
    need(len(vis(g, "emptyCard")) == 1, "grid-default: Notes is the empty card")
    need(texts(g, "cardName")[0] == "Agents", "grid-default: needs-you profile first, got %s" % texts(g, "cardName"))
    need(len(vis(g, "needsBadge")) == 2, "grid-default: two badges (Agents, Comms), got %d" % len(vis(g, "needsBadge")))
    need(len(vis(g, "moveHere")) == 6, "grid-default: Move here on six cards, got %d" % len(vis(g, "moveHere")))
gm = cases.get("grid-move")
if gm: need(len(vis(gm, "fullToast")) == 1 and not vis(gm, "popToast"), "grid-move: toast floats above the footer")
gs = cases.get("grid-salah")
if gs: need(len(vis(gs, "salahPill")) == 1, "grid-salah: Salah pill")
gf = cases.get("grid-filter")
if gf: need(len(vis(gf, "card")) >= 4, "grid-filter: only profiles with matches")
mp = cases.get("map-default")
if mp:
    need(len(vis(mp, "railBtn")) == 7 and vis(mp, "railBtn")[0]["w"] == 200, "map-default: wide rail, 200 px buttons")
    need(len(vis(mp, "mapTile")) == 4, "map-default: one tile per window")
    t = vis(mp, "mapTile")
    need(t[0]["h"] > t[1]["h"] and t[0]["x"] < t[1]["x"], "map-default: main tile left and taller")
    need(len(vis(mp, "mapMove")) == 1, "map-default: move bar for the selected window")
    need(len(vis(mp, "wsTab")) == 1, "map-default: one workspace tab for Dev")
mc = cases.get("map-comms")
if mc:
    need(len(vis(mc, "wsTab")) == 2 and len(vis(mc, "mapTile")) == 1, "map-comms: two tabs, second has one window")
me = cases.get("map-empty")
if me: need(len(vis(me, "emptyMap")) == 1 and not vis(me, "mapTile"), "map-empty: Nothing open")
if fails:
    print("\n".join("  " + f for f in fails)); sys.exit(1)
PY

errs="$(grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|is not defined|Required property|module .* not installed' "$work/out/scene.log" | head -8)"
if [ -n "$errs" ]; then echo "$errs"; bad "4 QML errors in the scene log"; else ok "4 no QML errors in the scene log"; fi

[ "$fails" -eq 0 ] && { echo "wsswitch-ui ok ($shots)"; exit 0; }
echo "wsswitch-ui: $fails failure(s)"; exit 1
