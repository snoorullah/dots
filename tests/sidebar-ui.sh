#!/usr/bin/env bash
# sidebar-ui: tests for the Quickshell sidebar (modules/sidebar). No compositor needed: it renders
# the real SidebarBody from fixture JSON under Quickshell on Qt's offscreen platform and asserts
# on geometry probes and on the PNG of each scene.
#   1  qmltestrunner  js/SideModel
#   2  qmllint        every sidebar .qml, resolved against a generated qmldir tree
#   3  static rules   no hex colours, no PUA glyphs, no shell/Process, no company names
#   4  scenes         board states: queue, four tabs, selected, empty, stale, system slot
#   5  actions        Expand emits the tab; double click execs `dots-jump <id>`; disabled buttons do nothing
# PNGs go to ${SHOTS_DIR:-$(mktemp -d)}. SKIPs (exit 0) only when quickshell is missing.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
export ROOT="$root"
qsd="$root/home/private_dot_config/quickshell/dots"
sb="$qsd/modules/sidebar"
tst="$sb/tst"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/sbx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()  { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
NOW=1761600000

# ---- tools -------------------------------------------------------------------------------
works() { "$1" -help >/dev/null 2>&1 || "$1" --help >/dev/null 2>&1; }
nixbin() { nix build --no-link --print-out-paths "nixpkgs#$1" 2>/dev/null | head -1; }
QS="${QS:-$(command -v quickshell || true)}"
[ -n "$QS" ] || { p="$(nixbin quickshell)"; [ -n "$p" ] && QS="$p/bin/quickshell"; }
QTD=""
if command -v qmltestrunner >/dev/null && works qmltestrunner; then QTR="$(command -v qmltestrunner)"; QML_LINT="$(command -v qmllint)"
else
  QTD="$(nixbin qt6.qtdeclarative)"
  QTR="${QTD:+$QTD/bin/qmltestrunner}"; QML_LINT="${QTD:+$QTD/bin/qmllint}"
fi
if [ -z "$QS" ] || [ -z "${QTR:-}" ]; then
  echo "SKIP sidebar-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: SideModel" || bad "1 qmltestrunner"

# ---- shared trees ------------------------------------------------------------------------
# PhosphorIcons for the scenes: the generator output, which already lists the names this module uses
# (the committed registry is regenerated at integration)
python3 "$root/tools/gen-phosphor-qml.py" --stdout > "$work/PhosphorIcons.qml"
mkcommon() { # dest
  mkdir -p "$1"; cp "$qsd/modules/common/"*.qml "$qsd/modules/common/qmldir" "$1/"; cp "$work/PhosphorIcons.qml" "$1/PhosphorIcons.qml"
}
mkroot() { # dest [with-system]
  local r="$1"; mkdir -p "$r/modules"
  ln -s "$qsd/modules/overview/tst/stub/modules/theme" "$r/modules/theme"
  ln -s "$qsd/modules/overview" "$r/modules/overview"
  ln -s "$sb" "$r/modules/sidebar"
  mkcommon "$r/modules/common"
  [ -n "${2:-}" ] && ln -s "$tst/stub/modules/system" "$r/modules/system"
  cp "$tst/Scene.qml" "$r/shell.qml"
}
mkroot "$work/root"; mkroot "$work/root-sys" 1

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint"; q="$lint/qs"
  mkdir -p "$q/modules/sidebar/parts" "$q/modules/overview" "$q/modules/theme" "$q/services"
  cp "$sb/"*.qml "$q/modules/sidebar/"; cp "$sb/parts/"*.qml "$q/modules/sidebar/parts/"; cp -r "$sb/js" "$q/modules/sidebar/js"
  cp "$qsd/modules/overview/Feed.qml" "$qsd/modules/overview/Actions.qml" "$q/modules/overview/"; cp -r "$qsd/modules/overview/js" "$q/modules/overview/js"
  cp "$qsd/modules/overview/tst/stub/modules/theme/Theme.qml" "$q/modules/theme/"
  cp "$qsd/services/Ui.qml" "$q/services/"
  mkcommon "$q/modules/common"
  mkqmldir() { ( cd "$1" && { echo "module $2"; for f in *.qml; do n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir ); }
  mkqmldir "$q/modules/sidebar" qs.modules.sidebar; mkqmldir "$q/modules/sidebar/parts" qs.modules.sidebar.parts
  mkqmldir "$q/modules/overview" qs.modules.overview; mkqmldir "$q/modules/theme" qs.modules.theme
  mkqmldir "$q/modules/common" qs.modules.common; mkqmldir "$q/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # Sidebar.qml builds a Quickshell PanelWindow (attached and grouped properties qmllint cannot
  # resolve from the plugin's type info): three categories relaxed for that file only.
  lintout="$("$QML_LINT" "${lintimp[@]}" "$q/modules/sidebar/SidebarBody.qml" "$q"/modules/sidebar/parts/*.qml 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$q/modules/sidebar/Sidebar.qml" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
if grep -rInE '#[0-9a-fA-F]{3,8}\b' "$sb" --include='*.qml' | grep -v '/tst/'; then bad "3 a hard-coded hex colour (use Theme tokens)"; else ok "3 no hex colours"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$sb" 2>/dev/null | grep .; then bad "3 a private-use codepoint (reference icons by name)"; else ok "3 no PUA codepoints"; fi
if grep -rInE 'execDetached|"(sh|bash|zsh)"|-c"|Process *\{|SplitParser|StdioCollector' "$sb" --include='*.qml' | grep -v '/tst/'; then bad "3 the sidebar execs or spawns something itself (it uses overview Actions only)"; else ok "3 no exec, no shell, no Process"; fi
if grep -rInE 'font\.family *: *"|Qt\.rgba?\(|Nerd' "$sb" --include='*.qml' | grep -v '/tst/'; then bad "3 a hard-coded font or colour constructor"; else ok "3 fonts and colours come from Theme"; fi
if grep -rIniE 'pnow|proficient|websleak|kaarbaaz|code42|contabo' "$sb" "$root/docs/shell/specs/sidebar.md" | grep .; then bad "3 a company name in a public file"; else ok "3 no company names"; fi
if grep -rInE '(^|[^0-9.])(10\.[0-9]{1,3}|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}' "$sb" | grep .; then bad "3 a private IP"; else ok "3 no private IPs"; fi
for f in SideModel; do
  grep -q 'SPDX-License-Identifier: MIT' "$sb/js/$f.js" && ok "3 js/$f.js carries the MIT header" || bad "3 js/$f.js lacks the MIT header"
done
spec_lines="$(wc -l < "$root/docs/shell/specs/sidebar.md")"
[ "$spec_lines" -le 60 ] && ok "3 spec is $spec_lines lines (<= 60)" || bad "3 spec is $spec_lines lines, over 60"

# ---- 4. scenes ---------------------------------------------------------------------------
mkdir -p "$work/bin" "$work/home"
printf '#!/bin/sh\n{ printf "%%s" "dots-jump"; for a in "$@"; do printf "\\t%%s" "$a"; done; printf "\\n"; } >> "$STUB_LOG"\n' > "$work/bin/dots-jump"
chmod +x "$work/bin/dots-jump"
# scene TAG FIXTURE [VAR=value ...]  -> $shots/TAG.{png,json}, $shots/TAG.log
scene() {
  local tag="$1" fixture="$2"; shift 2
  local state="$work/state-$tag" log="$shots/$tag.log" r="$work/root"
  [ "${SCENE_ROOT:-}" = sys ] && r="$work/root-sys"
  rm -rf "$state"; cp -r "$tst/fixtures/$fixture" "$state"; : > "$work/stub.log"
  env "$@" TAG="$tag" OUT_DIR="$shots" DOTS_OVERVIEW_STATE_DIR="$state" DOTS_OVERVIEW_NOW="$NOW" \
      XDG_RUNTIME_DIR="$xdg" HOME="$work/home" STUB_LOG="$work/stub.log" PATH="$work/bin:$PATH" \
      timeout "${SCENE_TIMEOUT:-90}" "$QS" -p "$r" >"$log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$log"
  grep -a 'PROBE ' "$log" | sed 's/^.*PROBE //' > "$shots/$tag.json"
  [ -s "$shots/$tag.json" ] || { tail -8 "$log"; bad "4 scene $tag printed no probe"; }
}
check() { python3 -I "$tst/check.py" "$@" || fails=$((fails + 1)); }
# python -I drops the script dir from the path but check.py inserts tests/ itself

scene board board;                   check board "$shots"
scene inbox board TAB=inbox;         check inbox "$shots"
scene agents board TAB=agents;       check agents "$shots"
scene work board TAB=work;           check work "$shots"
scene time board TAB=time;           check time "$shots"
scene select board SELECT=w2;        check select "$shots"
scene empty empty;                   check empty "$shots"
scene stale stale;                   check stale "$shots"
SCENE_ROOT=sys scene system board SYSTEM=1
scene system-missing board SYSTEM=1
check system "$shots"

# ---- 5. actions --------------------------------------------------------------------------
scene click-expand board TAB=work CLICK_NAMES=actExpand,actReply,actAgent,actQueue,actSnooze
grep -aq 'EXPAND work' "$shots/click-expand.log" && [ "$(grep -ac 'EXPAND ' "$shots/click-expand.log")" -eq 1 ] \
  && ok "5 Expand emits the current tab once; disabled buttons emit nothing" || bad "5 Expand / disabled buttons"
scene click-jump board CLICK_NAMES=dbl:sideRow; sleep 0.2
got="$(cat "$work/stub.log")"; want="$(printf 'dots-jump\tf1')"
[ "$got" = "$want" ] && ok "5 double click on a row execs the exact argv dots-jump <id>" || { echo "got: $got"; bad "5 jump argv"; }

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Cannot assign|binding loop' "$shots"/*.log 2>/dev/null | grep -v 'system-missing' | head -5 | grep .; then bad "4 QML errors in a scene log"; else ok "4 no QML errors in the scene logs"; fi

[ "$fails" -eq 0 ] && { echo "sidebar-ui ok"; exit 0; }
echo "sidebar-ui: $fails failure(s)"; exit 1
