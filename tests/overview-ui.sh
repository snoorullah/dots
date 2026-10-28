#!/usr/bin/env bash
# overview-ui: tests for the Quickshell overview (modules/overview). Needs no compositor
# and none of T1's or T2's code: it renders the real components from fixture JSON under
# Quickshell on Qt's offscreen platform, with a stub Theme, and asserts on geometry
# probes and on the PNG of each scene.
#   1  qmltestrunner  js/Fmt, js/Ledger, js/Model maths
#   2  qmllint        every .qml, resolved against a generated qmldir tree
#   3  static rules   no PUA codepoints, argv-only exec, no shell strings, scope of the diff
#   4  scenes         the eight pixel assertions of the spec, plus live reload and lamp test
#   5  actions        Break down & start / Jump / focus exec the right argv (stub on PATH)
# Tools: quickshell and Qt6 qmltestrunner/qmllint. Found on PATH, else built from nixpkgs
# once (needs the network the first time). With neither, the suite SKIPs and exits 0.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
ov="$root/home/private_dot_config/quickshell/dots/modules/overview"
tst="$ov/tst"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work"' EXIT
out="$work/out"; mkdir -p "$out"
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
  echo "SKIP overview-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: Fmt, Ledger, Model" || bad "1 qmltestrunner"

# ---- shell root for the scenes: stub Theme + the real overview, linked -------------------
shellroot="$work/root"; mkdir -p "$shellroot/modules"
ln -s "$tst/stub/modules/theme" "$shellroot/modules/theme"
ln -s "$ov" "$shellroot/modules/overview"
cp "$tst/Scene.qml" "$shellroot/shell.qml"

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint"; mkdir -p "$lint/qs/modules/overview/parts" "$lint/qs/modules/overview/pages" "$lint/qs/modules/theme"
  for d in "" parts pages; do
    cp "$ov/${d:+$d/}"*.qml "$lint/qs/modules/overview/${d:+$d/}" 2>/dev/null
  done
  cp -r "$ov/js" "$lint/qs/modules/overview/js"
  cp "$tst/stub/modules/theme/Theme.qml" "$lint/qs/modules/theme/"
  mkqmldir() { # dir module
    ( cd "$1" && { echo "module $2"; for f in *.qml; do n="${f%.qml}"
        if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
  }
  mkqmldir "$lint/qs/modules/overview" qs.modules.overview
  mkqmldir "$lint/qs/modules/overview/parts" qs.modules.overview.parts
  mkqmldir "$lint/qs/modules/overview/pages" qs.modules.overview.pages
  mkqmldir "$lint/qs/modules/theme" qs.modules.theme
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # OverviewHost builds Quickshell windows (PanelWindow, margins { }, anchors { }) whose attached
  # and grouped properties qmllint cannot resolve from the plugin's type info; those three
  # categories are relaxed for that one file, everything else is linted at defaults.
  lintout="$("$QML_LINT" "${lintimp[@]}" $(find "$lint/qs/modules/overview" -name '*.qml' ! -name OverviewHost.qml) 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$lint/qs/modules/overview/OverviewHost.qml" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi

# ---- 2b. the stub Theme derives colours exactly like the real theme/Tokens.qml -----------
# Real theme dir: the repo's own once T2 is merged, or REAL_THEME_DIR (a checkout of it).
realtheme="${REAL_THEME_DIR:-$root/home/private_dot_config/quickshell/dots/modules/theme}"
if [ -f "$realtheme/Tokens.qml" ] && [ -f "$realtheme/Palette.qml.tmpl" ]; then
  agroot="$work/agree"; mkdir -p "$agroot/modules" "$agroot/real"
  ln -s "$tst/stub/modules/theme" "$agroot/modules/theme"
  cp "$realtheme/Tokens.qml" "$agroot/real/Tokens.qml"
  python3 "$tst/agree.py" render "$root/home/.chezmoidata/palette.yaml" "$realtheme/Palette.qml.tmpl" "$agroot/real/Palette.qml"
  printf 'singleton Palette 1.0 Palette.qml\nsingleton Tokens 1.0 Tokens.qml\n' > "$agroot/real/qmldir"
  cp "$tst/Agree.qml" "$agroot/shell.qml"
  XDG_RUNTIME_DIR="$(mktemp -d /tmp/ovx.XXXXXX)" timeout 40 "$QS" -p "$agroot" > "$work/agree.log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$work/agree.log"
  if grep -aq 'AGREE ' "$work/agree.log"; then
    python3 "$tst/agree.py" check "$root/home/.chezmoidata/palette.yaml" "$work/agree.log" || fails=$((fails + 1))
  else head -8 "$work/agree.log"; bad "2b the Agree scene printed nothing"; fi
else
  echo "SKIP 2b stub-vs-real Theme: no theme/Tokens.qml at $realtheme (set REAL_THEME_DIR)"
fi

[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$ov" 2>/dev/null | grep .; then bad "3 a file carries a private-use codepoint (reference icons by ligature name)"; else ok "3 no PUA codepoints"; fi
if grep -rInE 'execDetached\(' "$ov" --include='*.qml' | grep -v '/tst/' | grep -vE 'Actions.qml:.*execDetached\(\['; then bad "3 execDetached outside Actions.qml, or not an argv array"; else ok "3 every exec is an argv array in Actions.qml"; fi
if grep -rInE '"(sh|bash|zsh)"|-c"|Process *\{|SplitParser|StdioCollector' "$ov" --include='*.qml' | grep -v '/tst/'; then bad "3 a shell or Process is used (overview execs argv only)"; else ok "3 no shell, no Process"; fi
for f in Fmt Ledger Model; do
  grep -q 'SPDX-License-Identifier: MIT' "$ov/js/$f.js" && grep -q 'Copyright (c) 2026 Shaik Noorullah Shareef' "$ov/js/$f.js" && ok "3 js/$f.js carries the MIT header" || bad "3 js/$f.js lacks the MIT header"
done
if grep -rIn 'Theme\.' "$ov" --include='*.qml' | grep -v -e '/tst/' -e 'Look.qml'; then bad "3 Theme.* used outside Look.qml"; else ok "3 Theme.* only in Look.qml"; fi
if grep -rInE 'palette\.yaml|matugen' "$ov" --include='*.qml' --include='*.js' | grep -v '/tst/' | grep -v '^\S*: *//' | grep -v '// '; then bad "3 the overview reads palette.yaml or calls matugen"; else ok "3 no palette.yaml or matugen"; fi
# Branch-scope guard for the feature branch only. On an integration branch the diff against main
# legitimately spans everything, so it runs when OVERVIEW_SCOPE_CHECK=1 is set.
base=""; [ -n "${OVERVIEW_SCOPE_CHECK:-}" ] && base="$(git -C "$root" merge-base HEAD main 2>/dev/null || true)"
if [ -n "$base" ] && [ "$(git -C "$root" rev-parse HEAD)" != "$base" ]; then
  stray="$(git -C "$root" diff --name-only "$base" HEAD | grep -vE '^(home/private_dot_config/quickshell/dots/modules/overview/|tests/overview-ui\.sh$|docs/overview-ui\.md$)')"
  [ -z "$stray" ] && ok "3 the diff stays inside modules/overview, tests/overview-ui.sh, docs/overview-ui.md" || { echo "$stray"; bad "3 the diff touches files outside the overview"; }
fi

# ---- 4. scenes ---------------------------------------------------------------------------
xdg="$(mktemp -d /tmp/ovx.XXXXXX)"; chmod 700 "$xdg"; trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
mkdir -p "$work/bin"
for c in dots-overview dots-jump; do
  printf '#!/bin/sh\n{ printf "%%s" "%s"; for a in "$@"; do printf "\\t%%s" "$a"; done; printf "\\n"; } >> "$STUB_LOG"\n' "$c" > "$work/bin/$c"
  chmod +x "$work/bin/$c"
done

# scene LABEL SCENARIO FIXTURE [VAR=value ...]  -> $out/SCENARIO-LABEL.{json,png}, $out/SCENARIO-LABEL.log
scene() {
  local label="$1" scenario="$2" fixture="$3"; shift 3
  local state="$work/state-$scenario-$label" log="$out/$scenario-$label.log"
  rm -rf "$state"; cp -r "$tst/fixtures/$fixture" "$state"
  : > "$work/stub.log"
  env "$@" SCENARIO="$scenario" OUT_DIR="$out" DOTS_OVERVIEW_STATE_DIR="$state" DOTS_OVERVIEW_NOW="$NOW" \
      XDG_RUNTIME_DIR="$xdg" HOME="$work/home" STUB_LOG="$work/stub.log" PWN="$work/pwned" PATH="$work/bin:$PATH" \
      timeout 40 "$QS" -p "$shellroot" >"$log" 2>&1 &
  local pid=$!
  if [ -n "${LIVE_SWAP:-}" ]; then
    sleep 1.6; cp "$tst/fixtures/$LIVE_SWAP/attention.json" "$state/attention.json.tmp" && mv "$state/attention.json.tmp" "$state/attention.json"
  fi
  wait "$pid"
  sed 's/\x1b\[[0-9;]*m//g' "$log" > "$log.clean"
  # PROBE <tag> {json} -> SCENARIO-<label or label-tag>.json ; PNG written by the scene as SCENARIO-<tag>.png
  while read -r _ tag json; do
    local dest="$label"; [ "$tag" != main ] && dest="$label-$tag"
    printf '%s\n' "$json" > "$out/$scenario-$dest.json"
    [ "$tag" != "$dest" ] && [ -f "$out/$scenario-$tag.png" ] && mv "$out/$scenario-$tag.png" "$out/$scenario-$dest.png"
  done < <(grep -a '^.*PROBE ' "$log.clean" | sed 's/^.*PROBE /PROBE /')
}
mkdir -p "$work/home"
check() { python3 "$tst/check.py" "$@" || fails=$((fails + 1)); }

scene nominal pill nominal;           scene waiting pill waiting;  scene failed pill failed
scene stale pill stale;               scene v2 pill v2;            scene lamp pill nominal LAMP=1
check nominal "$out"; check waiting "$out"; check failed "$out"; check stale "$out"; check v2 "$out"; check lamp "$out"

scene waiting card waiting;            scene stale card stale;      scene full card full
check card "$out" ; check dimcard "$out"; check full "$out"; check footer "$out"; check pressed "$out"
scene heatmap panel full PAGE=heatmap
check heatmap "$out"
scene main heatcompact full
check compact "$out"
# the remaining pages are rendered for errors and for the eye (KEEP=1 keeps the PNGs)
for pg in today week attention; do scene "page-$pg" panel full PAGE=$pg; done
scene page-item panel full PAGE=item SELECT=a1
scene focus-90 panel focus-90 PAGE=focus; scene focus-200 panel focus-200 PAGE=focus
check focus "$out"

LIVE_SWAP=live-next scene live pill nominal LIVE=1
check live "$out"

# ---- 5. actions: argv only --------------------------------------------------------------
shellref='HD-7; touch "$PWN" `id` $(id) #'
scene clickcard card waiting CLICK_NAMES=breakdownButton,focusToggle; sleep 0.3
got="$(sort "$work/stub.log")"
want="$(printf 'dots-overview\tbreakdown\t%s\t--start\ndots-overview\tfocus\tstart\n' "$shellref" | sort)"
[ "$got" = "$want" ] && ok "5 Break down & start and Start focus exec the exact argv" || { echo "got:"; echo "$got"; echo "want:"; echo "$want"; bad "5 card actions argv"; }
[ ! -e "$work/pwned" ] && ok "5 a ref full of shell metacharacters stayed one inert argument" || bad "5 the shell ran something"

scene clickitem panel waiting PAGE=item SELECT=a1 CLICK_NAMES=itemJump,itemBreakdown; sleep 0.3
got="$(sort "$work/stub.log")"
want="$(printf 'dots-jump\tgh:acme/widgets#12\ndots-overview\tbreakdown\tgh:acme/widgets#12\t--start\n' | sort)"
[ "$got" = "$want" ] && ok "5 Item page Jump and Break down exec the exact argv" || { echo "got:"; echo "$got"; echo "want:"; echo "$want"; bad "5 item actions argv"; }

# a missing state dir is "no data", not a crash and not a ?
rm -rf "$work/state-empty"; mkdir -p "$work/state-empty"
env SCENARIO=pill OUT_DIR="$out" DOTS_OVERVIEW_STATE_DIR="$work/state-empty" DOTS_OVERVIEW_NOW="$NOW" XDG_RUNTIME_DIR="$xdg" HOME="$work/home" \
    timeout 40 "$QS" -p "$shellroot" > "$out/empty.log" 2>&1
sed 's/\x1b\[[0-9;]*m//g' "$out/empty.log" | grep -a 'PROBE ' | sed 's/^.*PROBE main //' > "$out/empty.json"
python3 - "$out/empty.json" <<'EOF' && ok "5 with no files at all the pill is zero width and shows no ?" || bad "5 empty state dir"
import json, sys
m = json.load(open(sys.argv[1]))
sys.exit(0 if m["pill"]["w"] == 0 and m["stale"] == 0 else 1)
EOF

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError' "$out"/*.log.clean 2>/dev/null | head -5 | grep .; then bad "4 QML errors in a scene log"; else ok "4 no QML errors in any scene log"; fi

[ "$fails" -eq 0 ] && { echo "overview-ui ok"; exit 0; }
echo "overview-ui: $fails failure(s)"; exit 1
