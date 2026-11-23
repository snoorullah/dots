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
for c in dots-overview dots-jump xdg-open hyprctl; do
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
scene filter-mail extra SRC=Mail
scene filter-slack extra SRC=Slack
scene filter-alert extra SRC=Alert
scene queue-extra extra
scene agents-extra extra TAB=agents
scene work board TAB=work
scene work-board board TAB=work TASKVIEW=Board
scene work-all board TAB=work TASKVIEW=All
scene work-many tasks-many TAB=work
scene work-many-board tasks-many TAB=work TASKVIEW=Board
scene work-many-all tasks-many TAB=work TASKVIEW=All
scene work-wide tasks-many TAB=work WIN_W=1920 WIN_H=1080
scene work-short tasks-many TAB=work WIN_H=640
scene work-short-board tasks-many TAB=work TASKVIEW=Board WIN_H=640
scene work-short-all tasks-many TAB=work TASKVIEW=All WIN_H=640
scene time board TAB=time
scene time-wide board TAB=time WIN_W=1920 WIN_H=1080
scene time-short board TAB=time WIN_H=640
scene time-week board TAB=time TIMETAB=Week
scene time-heat board TAB=time TIMETAB=Heatmap
scene time-agent board TAB=time TIMEBY=Agent
scene time-days board TAB=time TIMETAB=Days
scene time-week-wide board TAB=time TIMETAB="Week" WIN_W=1920 WIN_H=1080
scene time-week-short board TAB=time TIMETAB="Week" WIN_H=640
scene time-days-wide board TAB=time TIMETAB="Days" WIN_W=1920 WIN_H=1080
scene time-days-short board TAB=time TIMETAB="Days" WIN_H=640
scene time-heat-wide board TAB=time TIMETAB="Heatmap" WIN_W=1920 WIN_H=1080
scene time-heat-short board TAB=time TIMETAB="Heatmap" WIN_H=640
scene time-focus board TAB=time TIMETAB="Focus zones"
scene time-focus-wide board TAB=time TIMETAB="Focus zones" WIN_W=1920 WIN_H=1080
scene time-focus-short board TAB=time TIMETAB="Focus zones" WIN_H=640
scene time-progress board TAB=time TIMETAB="Progress"
scene time-progress-wide board TAB=time TIMETAB="Progress" WIN_W=1920 WIN_H=1080
scene time-progress-short board TAB=time TIMETAB="Progress" WIN_H=640
scene time-report board TAB=time TIMETAB="Report"
scene time-report-wide board TAB=time TIMETAB="Report" WIN_W=1920 WIN_H=1080
scene time-report-short board TAB=time TIMETAB="Report" WIN_H=640
scene time-screen board TAB=time TIMETAB="Screen and health"
scene time-screen-wide board TAB=time TIMETAB="Screen and health" WIN_W=1920 WIN_H=1080
scene time-screen-short board TAB=time TIMETAB="Screen and health" WIN_H=640
scene time-reminders board TAB=time TIMETAB="Reminders"
scene time-reminders-wide board TAB=time TIMETAB="Reminders" WIN_W=1920 WIN_H=1080
scene time-reminders-short board TAB=time TIMETAB="Reminders" WIN_H=640
scene time-agents extra TAB=time TIMETAB="Agents"
scene time-agents-wide extra TAB=time TIMETAB="Agents" WIN_W=1920 WIN_H=1080
scene time-agents-short extra TAB=time TIMETAB="Agents" WIN_H=640
scene time-agents-partial extra TAB=time TIMETAB="Agents" AGENTM=agents-partial
scene time-agents-partial-wide extra TAB=time TIMETAB="Agents" AGENTM=agents-partial WIN_W=1920 WIN_H=1080
scene time-agents-nofile extra TAB=time TIMETAB="Agents" AGENTM=none
scene agents-metrics extra TAB=agents
scene agents-metrics-wide extra TAB=agents WIN_W=1920 WIN_H=1080
scene agents-metrics-none extra TAB=agents AGENTM=none
scene agents-metrics-partial extra TAB=agents AGENTM=agents-partial
scene time-nofile-week board TAB=time TIMETAB="Week" METRICS=none
scene time-empty-days metrics-empty TAB=time TIMETAB="Days"
scene time-partial-screen metrics-partial TAB=time TIMETAB="Screen and health"
scene time-partial-zones metrics-partial TAB=time TIMETAB="Focus zones"
scene time-partial-reminders metrics-partial TAB=time TIMETAB="Reminders"
scene time-days-detail metrics TAB=time TIMETAB="Days" STEPS=keys:Tab.j.Enter
scene time-heat-keys metrics TAB=time TIMETAB="Heatmap" STEPS=keys:Tab.k
scene time-report-save metrics TAB=time TIMETAB="Report" STEPS=keys:Tab.Enter
# ---- 4b. keyboard: key sequences through CcView.handle (no mouse) ---------------------------
scene keys-digits board STEPS=keys:2
scene keys-tab-agents board STEPS=keys:3
scene keys-tab-tasks board STEPS=keys:4
scene keys-tab-time board STEPS=keys:5
scene keys-move board STEPS=keys:j.j
scene keys-ne board STEPS=keys:n.n.e
scene keys-bottom board STEPS=keys:G
scene keys-gg board STEPS=keys:G.g.g
scene keys-g board STEPS=keys:g
scene keys-page board STEPS=keys:Ctrl+d
scene keys-detail board STEPS=keys:Enter
scene keys-tab-pane board STEPS=keys:Tab
scene keys-detail-back board STEPS=keys:Enter.h
scene keys-esc-detail board STEPS=keys:Enter.Esc
scene keys-esc-close board STEPS=keys:Esc
scene keys-ring board STEPS=keys:j
scene keys-snooze board STEPS=keys:j.Enter.s.3 VIEW=
scene keys-snooze-nav board STEPS=keys:Enter.s.j.j.Enter VIEW=
scene keys-snooze-open board STEPS=keys:Enter.s
scene keys-snooze-esc board STEPS=keys:Enter.s.Esc
scene keys-reply board STEPS=keys:j.j.Enter.r
scene keys-reply-submit board STEPS=keys:j.j.Enter.r.x.Ctrl+Enter
scene keys-reply-esc board STEPS=keys:j.j.Enter.r.Esc
scene keys-filter board STEPS=keys:/.m.a.i.l.Enter
scene keys-filter-typing board STEPS=keys:/.j.g
scene keys-filter-esc board STEPS=keys:/.m.a.i.l.Esc
scene keys-filter-clear board STEPS=keys:/.m.a.i.l.Esc.Esc
scene keys-filter-ctrlu board STEPS=keys:/.m.a.Ctrl+u
scene keys-help board STEPS=keys:'?'
scene keys-help-swallow board STEPS=keys:'?'.3.j
scene keys-help-esc board STEPS=keys:'?'.Esc
scene keys-chip board STEPS=keys:']'.']'
scene keys-chip-back board STEPS=keys:']'.']'.'['
scene keys-agent-open extra STEPS=keys:Enter.o
scene keys-stub board STEPS=keys:Enter.a
scene keys-agents-page extra TAB=agents STEPS=keys:j.j
scene keys-agents-open extra TAB=agents STEPS=keys:j.j.o
scene keys-agents-filter extra TAB=agents STEPS=keys:/.t.i.d.y.Enter
scene keys-tasks board TAB=work STEPS=keys:']'
scene keys-tasks-move board TAB=work STEPS=keys:']'.']'.j.j
scene keys-tasks-break board TAB=work STEPS=keys:b
scene keys-tasks-filter board TAB=work STEPS=keys:/.c.v.e.Enter
scene keys-time-sub board TAB=time STEPS=keys:']'
scene keys-time-strip board TAB=time STEPS=keys:l.l
scene keys-time-help board TAB=time STEPS=keys:'?'
scene keys-hint board STEPS=keys:j
scene keys-inbox board TAB=inbox STEPS=keys:Enter

# keyboard: every mouse-only control has a key; Time is driven from the keys alone
scene keys-undo board STEPS=pick:b1,key:q,keys:u
scene keys-undo-none board STEPS=keys:u
scene keys-view board STEPS=keys:'}'.'}'
scene keys-view-back board STEPS=keys:'}'.'{'
scene keys-group board STEPS=keys:=
scene keys-group-wrap board STEPS=keys:=.=.=
scene keys-grant board SELECT=b1 MODE=agent STEPS=keys:Ctrl+g
scene keys-grant-twice board SELECT=b1 MODE=agent STEPS=keys:Ctrl+g.Ctrl+g
scene keys-time-esc metrics TAB=time STEPS=keys:Tab.Esc
scene keys-time-esc-out metrics TAB=time STEPS=keys:Esc
scene keys-time-ring metrics TAB=time STEPS=keys:l
scene keys-time-body metrics TAB=time STEPS=keys:Tab
scene keys-time-today-by metrics TAB=time STEPS=keys:Tab.p
scene keys-time-today-by-back metrics TAB=time STEPS=keys:Tab.P
scene keys-time-focus metrics TAB=time STEPS=keys:Tab.s
scene keys-time-break metrics TAB=time STEPS=keys:Tab.b
scene keys-time-week metrics TAB=time TIMETAB=Week STEPS=keys:Tab.l.l.P
scene keys-time-week-rows metrics TAB=time TIMETAB=Week STEPS=keys:Tab.j.j
scene keys-time-days metrics TAB=time TIMETAB=Days STEPS=keys:Tab.j.j.Enter
scene keys-time-days-back metrics TAB=time TIMETAB=Days STEPS=keys:Tab.j.Enter.Esc
scene keys-time-heat metrics TAB=time TIMETAB=Heatmap STEPS=keys:Tab.Enter
scene keys-time-zones metrics TAB=time TIMETAB="Focus zones" STEPS=keys:Tab.j.p
scene keys-time-progress metrics TAB=time TIMETAB=Progress STEPS=keys:Tab.l.j.p
scene keys-time-report metrics TAB=time TIMETAB=Report STEPS=keys:Tab.p.c
scene keys-time-reminders metrics TAB=time TIMETAB=Reminders STEPS=keys:Tab.d
scene keys-time-reminders-snooze metrics TAB=time TIMETAB=Reminders STEPS=keys:Tab.j.s
scene keys-time-agents-period extra TAB=time TIMETAB=Agents STEPS=keys:Tab.p
scene keys-time-agents-today extra TAB=time TIMETAB=Agents STEPS=keys:Tab.P
scene keys-time-agents-rows extra TAB=time TIMETAB=Agents STEPS=keys:Tab.j.j
scene keys-time-agents-jump extra TAB=time TIMETAB=Agents STEPS=keys:Tab.Enter
scene keys-time-agents-nojump extra TAB=time TIMETAB=Agents STEPS=keys:Tab.G.Enter
scene keys-time-agents-o extra TAB=time TIMETAB=Agents STEPS=keys:Tab.o
scene keys-time-agents-help extra TAB=time TIMETAB=Agents STEPS=keys:Tab.'?'
scene keys-time-agents-sub extra TAB=time STEPS=keys:'['
scene keys-agents-time extra TAB=agents STEPS=keys:t
check extra; check queue; check groups; check inbox; check compose; check empty; check stale; check agents; check work; check work-layout; check time; check time-layout; check agents-time; check keys

# ---- 5. actions: argv only, stubs do nothing -----------------------------------------------
scene act-local board STEPS=pick:a1,act:"Open pane",pick:b1,"act:Open review","act:Break down & start"
check argv-local
scene act-agent-jump extra TAB=agents STEPS=jumprow:2
check agent-jump
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
