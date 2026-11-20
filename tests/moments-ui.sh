#!/usr/bin/env bash
# moments-ui: tests for the Quickshell moments surfaces (modules/moments, notif/Toast.qml):
# quick capture, re-nudge, return chip, handed-to-an-agent card. No compositor needed: it
# renders the real components from fixture JSON under Quickshell on Qt's offscreen platform.
#   1  qmltestrunner  js/Moments.js (capture argv, re-nudge schedule, detour, handed model)
#   2  qmllint        every .qml, resolved against a generated qmldir tree
#   3  static rules   argv-only exec, no shell, no hex colours or font names, no looping motion,
#                     nothing that sends, no private-use glyphs, no company words
#   4  scenes         board default, board after (captured, toast gone, returned), chip placed
#                     in a bar, chip absent (no detour, stale detour), geometry probes + PNGs
#   5  actions        Enter writes `task add`, empty writes nothing, the chip runs dots-jump
# PNGs go to ${SHOTS_DIR:-a temp dir}. With no quickshell or Qt6 tools the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules/moments"
tst="$mod/tst"
work="$(mktemp -d)"
out="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$out"
xdg="$(mktemp -d /tmp/mom.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }
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
  echo "SKIP moments-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: Moments.js" || bad "1 qmltestrunner"

# ---- shell root for the scenes: stub Theme (the real one needs a rendered Palette) ----------
stub="$dots/modules/overview/tst/stub/modules/theme"
shellroot="$work/root"; mkdir -p "$shellroot/modules"
ln -s "$stub" "$shellroot/modules/theme"
ln -s "$dots/modules/common" "$shellroot/modules/common"
ln -s "$mod" "$shellroot/modules/moments"
ln -s "$dots/modules/bar" "$shellroot/modules/bar"      # MomentState reads bar/js/Profiles.js
cp "$tst/Scene.qml" "$shellroot/shell.qml"

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs/modules"; mkdir -p "$lint/moments" "$lint/notif" "$lint/theme" "$lint/common"
  cp "$mod"/*.qml "$mod/qmldir" "$lint/moments/"; cp -r "$mod/js" "$lint/moments/js"
  mkdir -p "$lint/bar"; cp -r "$dots/modules/bar/js" "$lint/bar/js"
  cp "$dots"/modules/notif/*.qml "$lint/notif/"
  cp "$stub/Theme.qml" "$lint/theme/"; cp "$dots"/modules/common/*.qml "$lint/common/"
  mkqmldir() { # dir module
    ( cd "$1" && { echo "module $2"; for f in *.qml; do n="${f%.qml}"
        if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
  }
  mkqmldir "$lint/moments" qs.modules.moments; mkqmldir "$lint/theme" qs.modules.theme
  mkqmldir "$lint/common" qs.modules.common;   mkqmldir "$lint/notif" qs.modules.notif
  qsq="$(dirname "$(dirname "$(readlink -f "$QS")")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # QuickCapture builds a Quickshell PanelWindow and Toast/ToastStack use layer-shell attached
  # properties that qmllint cannot resolve from the plugin type info; those categories are
  # relaxed for those files only, everything else is linted at defaults.
  relaxed="QuickCapture.qml"
  lintout="$("$QML_LINT" "${lintimp[@]}" $(cd "$lint/moments" && ls *.qml | grep -vx "$relaxed" | sed "s|^|$lint/moments/|") 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$lint/moments/QuickCapture.qml" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$lint/notif/Toast.qml" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi

# ---- 3. static rules ---------------------------------------------------------------------
files=("$mod"/*.qml "$mod"/js/*.js "$dots/modules/notif/Toast.qml")
if grep -IlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "${files[@]}" 2>/dev/null | grep .; then bad "3 a file carries a private-use codepoint"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' "${files[@]}" | grep -vE 'execDetached\((\[|[A-Za-z_.]*[Aa]rgv)'; then bad "3 an exec that is not an argv"; else ok "3 every exec is an argv"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|Process *\{|SplitParser|StdioCollector' "${files[@]}" | grep -v 'Moments.js'; then bad "3 a shell or Process is used"; else ok "3 no shell, no Process"; fi
if grep -nE '#[0-9a-fA-F]{3,8}\b|Bricolage|JetBrains|Nerd' "$mod"/*.qml "$dots/modules/notif/Toast.qml"; then bad "3 a hard-coded colour or font name"; else ok "3 colours and fonts come from Theme only"; fi
if grep -nE 'Animation\.Infinite|loops:|SequentialAnimation|ParallelAnimation|SpringAnimation|green' "$mod"/*.qml "$dots/modules/notif/Toast.qml"; then bad "3 looping motion or green"; else ok "3 no looping motion, no green"; fi
if grep -nE 'slack|sendmail|curl|"gh"|mcp|smtp|"git"' "${files[@]}"; then bad "3 something that could send or write remotely"; else ok "3 nothing sends"; fi
if grep -rniE 'pnow|proficient|ovh|kaarbaaz|websleak|contabo|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168' "$mod" "$root/docs/shell/specs/moments.md" "$root/tests/moments-ui.sh" | grep -v 'moments-ui.sh:.*grep -rniE'; then bad "3 a company, host or private address"; else ok "3 public-repo clean"; fi
grep -q 'SPDX-License-Identifier: MIT' "$mod/js/Moments.js" && ok "3 js/Moments.js carries the MIT header" || bad "3 js/Moments.js lacks the MIT header"
# key handling cannot be driven offscreen, so the handlers are pinned by source
grep -q 'Keys.onReturnPressed: card.submit()' "$mod/CaptureCard.qml" && grep -q 'Keys.onEscapePressed: card.cancelled()' "$mod/CaptureCard.qml" \
  && grep -q 'Keys.onTabPressed' "$mod/CaptureCard.qml" && grep -q 'Key_R' "$mod/CaptureCard.qml" \
  && ok "3 Enter, Esc, Tab (stub) and Ctrl+R (stub) are handled" || bad "3 CaptureCard key handlers"
grep -q 'renudgeDelayMs' "$dots/modules/notif/Toast.qml" && grep -q 'renudgeDue' "$dots/modules/notif/Toast.qml" \
  && ok "3 Toast.qml re-nudges through Moments.js" || bad "3 Toast.qml does not use the re-nudge rules"

# ---- 4. scenes ---------------------------------------------------------------------------
mkdir -p "$work/bin"
for c in task dots-jump hyprctl; do
  printf '#!/bin/sh\n{ printf "%%s" "%s"; for a in "$@"; do printf "\\t%%s" "$a"; done; printf "\\n"; } >> "$STUB_LOG"\n' "$c" > "$work/bin/$c"
  chmod +x "$work/bin/$c"
done

# scene LABEL SCENARIO FIXTURE [VAR=value ...]  -> $out/SCENARIO-LABEL.{json,png}
scene() {
  local label="$1" scenario="$2" fixture="$3"; shift 3
  local log="$work/$scenario-$label.log"
  : > "$work/stub.log"
  env "$@" SCENARIO="$scenario" OUT_DIR="$work" HANDED="$tst/fixtures/handed.json" QML_XHR_ALLOW_FILE_READ=1 \
      DOTS_OVERVIEW_STATE_DIR="$tst/fixtures/$fixture" DOTS_OVERVIEW_NOW="$NOW" \
      XDG_RUNTIME_DIR="$xdg" STUB_LOG="$work/stub.log" PATH="$work/bin:$PATH" \
      timeout 40 "$QS" -p "$shellroot" > "$log" 2>&1
  sed 's/\x1b\[[0-9;]*m//g' "$log" > "$log.clean"
  grep -a 'PROBE ' "$log.clean" | sed 's/^.*PROBE [a-z]* //' | head -1 > "$out/$scenario-$label.json"
  [ -f "$work/$scenario-main.png" ] && mv "$work/$scenario-main.png" "$out/$scenario-$label.png"
  [ -f "$work/$scenario-action.png" ] && mv "$work/$scenario-action.png" "$out/$scenario-$label.png"
  return 0
}
check() { python3 "$tst/check.py" "$@" "$out" || fails=$((fails + 1)); }

scene default board away
scene after board away CAPTURED=1 TOAST=off BACK=1 TEXT="ask sam about ballooning on db-03"
scene typed capture in TEXT="ask sam about ballooning on db-03"
scene bar chip away
scene none chipnone in
scene stale chipnone stale
check default; check after; check bar; check none; check stale
# detour from focus: the clock is "in", Hyprland's focus has been off the task (a Comms workspace)
FOCUS_OFF='{"cls":"Slack","ws":4,"agoSec":300,"homeWs":1}'
scene focusoff chip in DOTS_MOMENTS_FOCUS="$FOCUS_OFF"
scene focusshort chip in DOTS_MOMENTS_FOCUS='{"cls":"Slack","ws":4,"agoSec":60}'
scene focusterm chipnone in DOTS_MOMENTS_FOCUS='{"cls":"com.mitchellh.ghostty","ws":1,"agoSec":900}'
scene focuspopup chipnone in DOTS_MOMENTS_FOCUS='{"cls":"dots.otter","ws":4,"agoSec":900}'
check focusoff; check focusshort; check focusterm; check focuspopup

# ---- 5. actions: argv only ---------------------------------------------------------------
text='ask sam; $(id) `id` "q" -x'
scene submit action away ACTION=submit TEXT="$text"
got="$(cat "$work/stub.log")"
want="$(printf 'task\tadd\t+capture\t--\t%s' "$text")"
[ "$got" = "$want" ] && ok "5 Enter execs the exact task add argv, text inert" || { echo "got:  $got"; echo "want: $want"; bad "5 capture argv"; }
grep -aq 'DID submit true captured=true' "$work/action-submit.log.clean" && ok "5 a saved thought flips the card to captured" || bad "5 captured state after Enter"
scene empty action away ACTION=submit TEXT="   "
[ ! -s "$work/stub.log" ] && ok "5 an empty thought writes nothing" || bad "5 an empty thought exec'd something"
grep -aq 'DID submit false captured=false' "$work/action-empty.log.clean" && ok "5 an empty thought stays open (captured=false)" || bad "5 empty capture state"
scene back chip away ACTION=chip
[ "$(cat "$work/stub.log")" = "$(printf 'dots-jump\tHD 4412')" ] && ok "5 the chip execs dots-jump with the ticket ref" || { cat "$work/stub.log"; bad "5 chip argv"; }
scene backnone chip in ACTION=chip
[ ! -s "$work/stub.log" ] && ok "5 no detour, no chip, no exec" || bad "5 chip exec'd without a detour"
scene backfocus chip in ACTION=chip DOTS_MOMENTS_FOCUS="$FOCUS_OFF"
want="$(printf 'hyprctl\tdispatch\thl.dsp.focus({ workspace = "1" })\ndots-jump\tHD 4412')"
[ "$(cat "$work/stub.log")" = "$want" ] && ok "5 back from a focus detour: terminal workspace, then the task pane" || { cat "$work/stub.log"; bad "5 focus detour back argvs"; }

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Cannot assign|binding loop' "$work"/*.log.clean 2>/dev/null | head -5 | grep .; then bad "4 QML errors in a scene log"; else ok "4 no QML errors in any scene log"; fi

echo "shots: $out"
[ "$fails" -eq 0 ] && { echo "moments-ui ok"; exit 0; }
echo "moments-ui: $fails failure(s)"; exit 1
