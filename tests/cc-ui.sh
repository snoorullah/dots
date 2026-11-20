#!/usr/bin/env bash
# cc-ui: tests for the Quickshell control centre (modules/cc). Needs no compositor: it
# renders the real CcView from fixture JSON under Quickshell on Qt's offscreen platform,
# with a stub Theme, writes a PNG per board state and asserts geometry, text and pixels.
#   1  qmltestrunner  js/Queue.js (sections, grouping, filters, actions, tables)
#   2  qmllint        every .qml in modules/cc, against a generated qmldir tree
#   3  static rules   no PUA glyphs, no hex colours or font names, argv-only exec, nothing sent
#   4  scenes         queue, inbox, groups, compose panels, agents, tasks, time (PNG each)
#   5  actions        local actions exec the exact argv; stubs exec nothing; metacharacters stay inert
# Output: PNGs and probe JSON go to ${SHOTS_DIR:-$(mktemp -d)}.
# Tools: quickshell and Qt6 qmltestrunner/qmllint, from PATH or built from nixpkgs once.
# With no quickshell the suite SKIPs and exits 0.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
cc="$dots/modules/cc"
tst="$cc/tst"
work="$(mktemp -d)"
xdg="$(mktemp -d /tmp/ccx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
out="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$out"
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
if [ -z "$QS" ]; then echo "SKIP cc-ui: quickshell not found and could not be built"; exit 0; fi
if [ -z "${QTR:-}" ]; then echo "SKIP cc-ui: Qt6 qmltestrunner not found and could not be built"; exit 0; fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: Queue.js" || bad "1 qmltestrunner"

# ---- shell root for the scenes -------------------------------------------------------------
shellroot="$work/root"; mkdir -p "$shellroot/modules"
ln -s "$tst/stub/modules/theme" "$shellroot/modules/theme"
ln -s "$cc" "$shellroot/modules/cc"
ln -s "$dots/modules/overview" "$shellroot/modules/overview"
ln -s "$dots/modules/common" "$shellroot/modules/common"
ln -s "$dots/services" "$shellroot/services"
cp "$tst/Scene.qml" "$shellroot/shell.qml"

# ---- 2. qmllint ----------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint"; q="$lint/qs/modules"
  mkdir -p "$q/theme" "$q/common" "$lint/qs/services"
  cp -r "$cc" "$q/cc"; rm -rf "$q/cc/tst"
  cp -r "$dots/modules/overview" "$q/overview"; rm -rf "$q/overview/tst"
  cp "$tst/stub/modules/theme/Theme.qml" "$q/theme/"
  cp "$dots/modules/common/"*.qml "$q/common/"
  cp "$dots/services/Ui.qml" "$lint/qs/services/"
  mkqmldir() { # dir module
    ( cd "$1" && { echo "module $2"; for f in *.qml; do n="${f%.qml}"
        if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
  }
  mkqmldir "$q/theme" qs.modules.theme; mkqmldir "$q/common" qs.modules.common
  mkqmldir "$q/overview" qs.modules.overview; mkqmldir "$q/overview/parts" qs.modules.overview.parts
  mkqmldir "$q/cc" qs.modules.cc; mkqmldir "$q/cc/parts" qs.modules.cc.parts; mkqmldir "$q/cc/pages" qs.modules.cc.pages
  mkqmldir "$lint/qs/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # ControlCentre builds a Quickshell PanelWindow (anchors { }, WlrLayershell.*): attached and
  # grouped properties qmllint cannot resolve from the plugin's type info. Relaxed for that
  # one file; everything else is linted at defaults.
  lintout="$("$QML_LINT" "${lintimp[@]}" $(find "$q/cc" -name '*.qml' ! -name ControlCentre.qml) 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$q/cc/ControlCentre.qml" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules -----------------------------------------------------------------------
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$cc" 2>/dev/null | grep .; then bad "3 a file carries a private-use codepoint (icons go by Phosphor name)"; else ok "3 no PUA codepoints"; fi
if grep -rInE '#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b' "$cc" --include='*.qml' --include='*.js' | grep -v '/tst/'; then bad "3 a hard-coded hex colour (use Theme.color.*)"; else ok "3 no hex colours"; fi
if grep -rInE 'Bricolage|JetBrains|Nerd|font\.family: *"' "$cc" --include='*.qml' | grep -v '/tst/'; then bad "3 a hard-coded font name (use Theme.font.*)"; else ok "3 no font names"; fi
if grep -rInE 'execDetached\(' "$cc" --include='*.qml' | grep -v '/tst/' | grep -vE 'parts/CcState.qml:.*execDetached\(\['; then bad "3 execDetached outside CcState.qml, or not an argv array"; else ok "3 every exec is an argv array in CcState.qml"; fi
if grep -rInE '"(sh|bash|zsh)"|-c"|Process *\{|SplitParser|StdioCollector|XMLHttpRequest|WebSocket' "$cc" --include='*.qml' | grep -v '/tst/'; then bad "3 a shell, Process or network call (nothing is ever sent)"; else ok "3 no shell, Process or network"; fi
if grep -rInE 'Quickshell\.exec\(|Qt\.openUrlExternally' "$cc" --include='*.qml' | grep -v '/tst/'; then bad "3 a non-argv launch"; else ok "3 no string launches"; fi
if grep -rInEi 'pnow|proficient|kaarbaaz|websleak|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$cc" "$root/docs/shell/specs/cc.md" "$root/tests/cc-ui.sh" | grep -v 'example.invalid'; then bad "3 a company name or address in a public file"; else ok "3 no company names or addresses"; fi
# every icon named in js/Queue.js is listed in parts/CcIcons.qml (that is what feeds the icon registry)
if python3 -I - "$cc" <<'PY'
import re, sys
cc = sys.argv[1]
js = open(cc + "/js/Queue.js").read()
names = set(re.findall(r'A\("[^"]+", "[^"]", "([a-z-]+)"', js)) | set(re.findall(r'(?:: |, )"([a-z]+(?:-[a-z]+)*)"', re.search(r"var SRC_ICON = \{(.*?)\}", js, re.S).group(1)))
listed = set(re.findall(r'"([a-z]+(?:-[a-z]+)*)"', open(cc + "/parts/CcIcons.qml").read()))
missing = sorted(names - listed)
print("missing from CcIcons.qml: " + ", ".join(missing)) if missing else None
sys.exit(1 if missing or not names else 0)
PY
then ok "3 every Queue.js icon name is registered in CcIcons.qml"; else bad "3 Queue.js names an icon that CcIcons.qml does not list"; fi
for f in Queue; do
  grep -q 'SPDX-License-Identifier: MIT' "$cc/js/$f.js" && grep -q 'Copyright (c) 2026 Shaik Noorullah Shareef' "$cc/js/$f.js" && ok "3 js/$f.js carries the MIT header" || bad "3 js/$f.js lacks the MIT header"
done
spec_lines="$(wc -l < "$root/docs/shell/specs/cc.md")"
[ "$spec_lines" -le 60 ] && ok "3 specs/cc.md is $spec_lines lines (max 60)" || bad "3 specs/cc.md is $spec_lines lines"

# ---- 4. scenes -----------------------------------------------------------------------------
mkdir -p "$work/bin" "$work/home"
for c in dots-overview dots-jump xdg-open; do
  printf '#!/bin/sh\n{ printf "%%s" "%s"; for a in "$@"; do printf "\\t%%s" "$a"; done; printf "\\n"; } >> "$STUB_LOG"\n' "$c" > "$work/bin/$c"
  chmod +x "$work/bin/$c"
done

# scene TAG FIXTURE [VAR=value ...]  -> $out/TAG.{png,json,log}
scene() {
  local tag="$1" fixture="$2"; shift 2
  local state="$work/state-$tag" log="$out/$tag.log"
  rm -rf "$state"; cp -r "$tst/fixtures/$fixture" "$state"
  : > "$work/stub.log"
  env "$@" TAG="$tag" OUT_DIR="$out" DOTS_OVERVIEW_STATE_DIR="$state" DOTS_OVERVIEW_NOW="$NOW" \
      XDG_RUNTIME_DIR="$xdg" HOME="$work/home" STUB_LOG="$work/stub.log" PWN="$work/pwned" PATH="$work/bin:$PATH" \
      timeout 60 "$QS" -p "$shellroot" >"$log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$log"
  grep -a 'PROBE ' "$log" | sed 's/^.*PROBE //' > "$out/$tag.json"
  cp "$work/stub.log" "$out/$tag.exec"
}
check() { python3 "$tst/check.py" "$@" "$out" || fails=$((fails + 1)); }

scene queue board
scene queue-source board GROUP=Source
scene queue-person board GROUP=Person SELECT=b1
scene queue-reply board SELECT=a2 MODE=reply
scene queue-agent board SELECT=b1 MODE=agent
scene queue-snooze board SELECT=a3 MODE=snooze
scene queue-slack board SRC=Slack
scene inbox board TAB=inbox
scene queue-empty empty
scene queue-stale stale
scene agents board TAB=agents
scene work board TAB=work
scene work-board board TAB=work TASKVIEW=Board
scene work-all board TAB=work TASKVIEW=All
scene time board TAB=time
scene time-week board TAB=time TIMETAB=Week
scene time-heat board TAB=time TIMETAB=Heatmap
scene time-agent board TAB=time TIMEBY=Agent
scene time-days board TAB=time TIMETAB=Days
check queue; check groups; check inbox; check compose; check empty; check stale; check agents; check work; check time

# ---- 5. actions: argv only, stubs do nothing -----------------------------------------------
scene act-local board STEPS=pick:a1,act:"Open pane",pick:b1,"act:Open review","act:Break down & start"
check argv-local
scene act-stub board STEPS=pick:a1,"act:Allow once",act:Deny,pick:a2,act:Reply,click:sendBtn,pick:d1,"act:Make a task"
check argv-stub
scene act-hide board STEPS=pick:b1,key:q,step:0
check hide
scene act-undo board STEPS=pick:b1,key:q,undo
check undo
scene act-snooze board STEPS=pick:a3,key:s,snooze:Tonight VIEW=
check snooze
scene act-meta meta STEPS=pick:b1,"act:Break down & start",act:Jump
check argv-meta
[ ! -e "$work/pwned" ] && ok "5 a ref full of shell metacharacters stayed one inert argument" || bad "5 the shell ran something"
scene act-back board STEPS=back
check back

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Cannot read|binding loop|Unable to assign' "$out"/*.log 2>/dev/null | head -8 | grep .; then bad "4 QML errors in a scene log"; else ok "4 no QML errors in any scene log"; fi

[ "$fails" -eq 0 ] && { echo "cc-ui ok (shots in $out)"; exit 0; }
echo "cc-ui: $fails failure(s) (shots in $out)"; exit 1
