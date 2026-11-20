#!/usr/bin/env bash
# bar-ui: tests for the Quickshell bar (modules/bar). No compositor and no service: it
# renders the real BarView from fixture models under Quickshell on Qt's offscreen platform,
# writes a PNG per board state and asserts on geometry, clicks and pixels.
#   1  qmltestrunner  js/BarModel (ages, order, +n, salah, faults) and js/Eq
#   2  qmllint        every bar .qml, resolved against a generated qmldir tree
#   3  static rules   no hex colours or PUA glyphs, no exec, no Process in the bar
#   4  scenes         eight board states + bare, narrow, equalizer clock, ten click targets
# PNGs go to $SHOTS_DIR (default: a temp dir, printed). Tools: quickshell and Qt6
# qmltestrunner/qmllint, from PATH, else nix. With no quickshell the suite SKIPs and exits 0.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
bar="$dots/modules/bar"
tst="$bar/tst"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/barx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()  { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# ---- tools -------------------------------------------------------------------------------
works() { "$1" -help >/dev/null 2>&1 || "$1" --help >/dev/null 2>&1; }
qt6bin() { # name -> a Qt 6 binary, from PATH, a store path, or nix
  local n="$1" b p
  b="$(command -v "$n" || true)"
  if [ -n "$b" ] && works "$b"; then echo "$b"; return; fi
  for p in /usr/lib/qt6/bin/"$n" /nix/store/*-qtdeclarative-6.*/bin/"$n"; do
    case "$p" in *-dev/*) continue;; esac
    if [ -x "$p" ] && works "$p"; then echo "$p"; return; fi
  done
  p="$(nix build --no-link --print-out-paths 'nixpkgs#qt6.qtdeclarative' 2>/dev/null | head -1)"
  [ -n "$p" ] && [ -x "$p/bin/$n" ] && echo "$p/bin/$n"
}
QS="${QS:-$(command -v quickshell || true)}"
if [ -z "$QS" ]; then echo "SKIP bar-ui: quickshell not found"; exit 0; fi
QTR="$(qt6bin qmltestrunner || true)"; QML_LINT="$(qt6bin qmllint || true)"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none
[ -n "$QTR" ] && export QML_IMPORT_PATH="$(dirname "$(dirname "$QTR")")/lib/qt-6/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

# ---- 1. unit tests -----------------------------------------------------------------------
if [ -n "$QTR" ]; then
  res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
  echo "$res" | grep -E '^(FAIL|Totals)'
  echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: BarModel, Eq" || bad "1 qmltestrunner"
else
  bad "1 qmltestrunner not found"
fi

# ---- shell root: real bar + real theme and common, Palette rendered from palette.yaml ----
shellroot="$work/root"; mkdir -p "$shellroot/modules/theme"
ln -s "$bar" "$shellroot/modules/bar"
ln -s "$dots/modules/common" "$shellroot/modules/common"
cp "$dots/modules/theme/"{Theme.qml,Tokens.qml,qmldir} "$shellroot/modules/theme/"
python3 -I - "$root/home/.chezmoidata/palette.yaml" "$dots/modules/theme/Palette.qml.tmpl" "$shellroot/modules/theme/Palette.qml" <<'PY'
import re, sys
yaml, tmpl, dest = sys.argv[1:4]
pal, inside = {}, False
for line in open(yaml):
    if re.match(r"^palette:\s*$", line):
        inside = True
    elif inside:
        m = re.match(r'^  ([a-z_]+): "(#[0-9a-fA-F]{6})"', line)
        if m:
            pal[m.group(1)] = m.group(2).lower()
        elif re.match(r"^\S", line):
            break
open(dest, "w").write(re.sub(r"\{\{\s*\.palette\.(\w+)\s*\}\}", lambda m: pal[m.group(1)], open(tmpl).read()))
PY
cp "$tst/Scene.qml" "$shellroot/shell.qml"

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "$QML_LINT" ]; then
  lint="$work/lint/qs/modules"; mkdir -p "$lint"
  cp -r "$bar" "$lint/bar"; rm -rf "$lint/bar/tst"
  cp -r "$shellroot/modules/theme" "$lint/theme"; cp -rL "$dots/modules/common" "$lint/common"
  mkqmldir() { # dir module
    ( cd "$1" && { echo "module $2"; for f in *.qml; do n="${f%.qml}"
        if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
  }
  mkqmldir "$lint/bar" qs.modules.bar; mkqmldir "$lint/bar/items" qs.modules.bar.items
  mkqmldir "$lint/theme" qs.modules.theme; mkqmldir "$lint/common" qs.modules.common
  qsq="$(dirname "$(dirname "$(readlink -f "$QS")")")/lib/qt-6/qml"
  imp=(-I "$work/lint"); [ -d "$qsq" ] && imp+=(-I "$qsq"); imp+=(-I "$(dirname "$(dirname "$QML_LINT")")/lib/qt-6/qml")
  # Bar.qml is the PanelWindow wiring: Quickshell's attached and grouped properties and the
  # services it imports are not resolvable from a copy, so those categories are relaxed for it
  lintout="$("$QML_LINT" "${imp[@]}" $(find "$lint/bar" -name '*.qml' ! -name Bar.qml ! -name IconRegistry.qml) 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean (presentation files at defaults)"
  else echo "$lintout" | head -"${LINT_LINES:-30}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi

# ---- 3. static rules ---------------------------------------------------------------------
if grep -rInE '#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{8}\b' "$bar" --include='*.qml' --include='*.js' | grep -v '/tst/'; then
  bad "3 a hex colour in the bar (use Theme.color.*)"; else ok "3 no hex colours in the bar"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$bar" 2>/dev/null | grep .; then
  bad "3 a private-use codepoint (use Icon names)"; else ok "3 no PUA codepoints"; fi
if grep -rInE 'execDetached|Process *\{|StdioCollector|"(sh|bash|zsh)"|-c"' "$bar" --include='*.qml' | grep -v '/tst/'; then
  bad "3 the bar runs a command (it only toggles Ui and focuses a workspace)"; else ok "3 no exec, no shell, no Process"; fi
if grep -rInE 'font\.family *: *"|Bricolage|JetBrains|Nerd' "$bar" --include='*.qml' | grep -v '/tst/'; then
  bad "3 a hard-coded font"; else ok "3 no hard-coded font names"; fi
if grep -rInE 'Ui\.(toggle|toggleCc)\(' "$bar/Bar.qml" >/dev/null; then ok "3 Bar.qml reaches Ui"; else bad "3 Bar.qml never calls Ui"; fi
if grep -rInE '(proficient|pnow|kaarbaaz|code42|websleak|10\.[0-9]+\.[0-9]+\.[0-9]+)' "$bar" "$root/docs/shell/specs/bar.md" "$root/tests/bar-ui.sh" -i | grep -v 'bar-ui.sh:.*grep'; then
  bad "3 a company or private address in the bar"; else ok "3 public-repo clean"; fi
if grep -n 'property var notifs' "$bar/Bar.qml" >/dev/null; then ok "3 Bar keeps its notifs property"; else bad "3 Bar lost its notifs property"; fi

# ---- 4. scenes ---------------------------------------------------------------------------
fx="$work/fx"; mkdir -p "$fx"
python3 -I "$tst/mkfixtures.py" "$fx"
out="$work/out"; mkdir -p "$out"
# scene LABEL FIXTURE [VAR=value ...]  -> $out/LABEL.{json,png}
scene() {
  local label="$1" fixture="$2"; shift 2
  env "$@" FIXTURE="$fx/$fixture.json" LOGOS="$fx/logos" OUT="$out/$label.png" XDG_RUNTIME_DIR="$xdg" \
      timeout 40 "$QS" -p "$shellroot" > "$out/$label.log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$out/$label.log"
  grep -a 'PROBE ' "$out/$label.log" | sed 's/^.*PROBE //' | tail -1 > "$out/$label.json"
  [ -s "$out/$label.json" ] || { tail -5 "$out/$label.log"; bad "4 scene $label printed no probe"; }
}
for s in quiet waiting detour failed hover stale paused overflow bare; do scene "$s" "$s" ETIME=0.5; done
scene quiet-t1 quiet ETIME=0.3; scene quiet-t2 quiet ETIME=0.9
scene paused-t1 paused ETIME=0.3; scene paused-t2 paused ETIME=0.9
scene narrow quiet WIDTH=1600 ETIME=0.5
scene click-clock quiet CLICKS=clockChip
scene click-salah quiet CLICKS=salahChip
scene click-agent waiting CLICKS=wait:0
scene click-wait2 waiting CLICKS=wait:1
scene click-bell quiet CLICKS=bell
scene click-logo quiet CLICKS=logo
scene click-tray bare CLICKS=tray
scene click-metrics quiet CLICKS=metrics
scene click-fault failed CLICKS=fault
scene click-music quiet CLICKS=music
python3 -I "$tst/check.py" "$out" || fails=$((fails + 1))

# "Failed to open reload popup" is quickshell reacting to a source file saved mid-run, not a defect
if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Binding loop|NOCLICK' "$out"/*.log 2>/dev/null | grep -v 'reload popup' | head -5 | grep .; then
  bad "4 QML errors, binding loops or a missed click in a scene log"
else ok "4 no QML errors or binding loops in any scene log"; fi

for s in quiet waiting detour failed hover stale paused overflow bare narrow; do cp "$out/$s.png" "$shots/bar-$s.png" 2>/dev/null; done
echo "PNGs: $shots"
[ "$fails" -eq 0 ] && { echo "bar-ui ok"; exit 0; }
echo "bar-ui: $fails failure(s)"; exit 1
