#!/usr/bin/env bash
# session-ui: tests for the Quickshell session module (modules/session): the away picker,
# the session menu and the polkit password card. No compositor needed: it renders the real
# components from fixtures under Quickshell on Qt's offscreen platform, writes a PNG per
# state and asserts on geometry probes.
#   1  unittest       py/session.py (choices, declare-then-lock, blocker) with fake binaries
#   1b qmltestrunner  js/Session.js (model, argv builders, text)
#   2  qmllint        every .qml in modules/session
#   3  static rules   no hex colour or font name, argv-only exec, no shell, no sends, MIT headers
#   4  scenes         picker, session card, password card, return rows, empty state
# PNGs go to ${SHOTS_DIR:-$(mktemp -d)}. Without quickshell the scene part SKIPs.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules/session"
tst="$mod/tst"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work"' EXIT
SHOTS="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$SHOTS"
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }

# ---- 1. python ---------------------------------------------------------------------------
if out="$(python3 -W error -I "$tst/test_session.py" 2>&1)"; then ok "1 unittest: session.py ($(echo "$out" | grep -E '^Ran')"; else echo "$out" | tail -25; bad "1 unittest"; fi

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

# ---- 3. static rules (need no Qt) --------------------------------------------------------
qmls=$(ls "$mod"/*.qml "$tst"/Scene.qml)
shipped=$(ls "$mod"/*.qml)
if grep -nE '#[0-9a-fA-F]{3,8}\b' $shipped | grep -v '^\S*: *//' | grep .; then bad "3 a hex colour in QML (use Theme.color.*)"; else ok "3 no hex colours in QML"; fi
if grep -nE 'font\.family *: *"|"(JetBrains|Bricolage|dots Icons)' $shipped | grep .; then bad "3 a hard-coded font family"; else ok "3 no hard-coded font names"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$mod" 2>/dev/null | grep .; then bad "3 a file carries a private-use codepoint (use Icon names)"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $shipped | grep -vE 'execDetached\((S\.helperArgv|act\.argv)' | grep .; then bad "3 execDetached with something other than an argv array"; else ok "3 every exec is an argv array"; fi
if grep -nE '"(sh|bash|zsh)"|"-c"|shell *= *True|os\.system|os\.popen|Popen\(.*shell' $shipped "$mod"/js/*.js "$mod"/py/*.py | grep .; then bad "3 a shell in the module"; else ok "3 no shell strings"; fi
if grep -nEi 'slack|gmail|smtp|sendmail|curl|wget|XMLHttpRequest|urllib|requests\.|socket|pnow-erp|gh (pr|issue)' $shipped "$mod"/js/*.js "$mod"/py/*.py | grep .; then bad "3 a remote send path"; else ok "3 no send or remote-write path"; fi
if grep -nE 'Nerd|nerd-font' $shipped | grep .; then bad "3 a Nerd Font reference"; else ok "3 no Nerd Font"; fi
if grep -nEi 'green|#0f0|lime' $shipped | grep .; then bad "3 green in the module"; else ok "3 no green"; fi
for f in "$mod"/js/*.js "$mod"/py/*.py "$tst"/test_session.py; do
  grep -q 'SPDX-License-Identifier: MIT' "$f" && ok "3 $(basename "$f") carries the MIT header" || bad "3 $(basename "$f") lacks the MIT header"
done

if [ -z "$QS" ] || [ -z "${QTR:-}" ]; then
  echo "SKIP session-ui scenes: quickshell and Qt6 qmltestrunner not found and could not be built"
  [ "$fails" -eq 0 ] && exit 0 || exit 1
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1b. qml unit tests ------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1b qmltestrunner: Session.js" || bad "1b qmltestrunner"

# ---- scene root --------------------------------------------------------------------------
shellroot="$work/root"; mkdir -p "$shellroot/modules"
cp -r "$dots/modules/theme" "$shellroot/modules/theme"
python3 -I - "$root/home/.chezmoidata/palette.yaml" "$dots/modules/theme/Palette.qml.tmpl" "$shellroot/modules/theme/Palette.qml" <<'PY'
import re, sys
yaml, tmpl, dest = sys.argv[1:4]
pal, inside = {}, False
for line in open(yaml):
    if re.match(r"^palette:\s*$", line): inside = True; continue
    if inside:
        m = re.match(r'^  ([a-z_]+): "(#[0-9a-fA-F]{6})"', line)
        if m: pal[m.group(1)] = m.group(2).lower()
        elif re.match(r"^\S", line): break
open(dest, "w").write(re.sub(r"\{\{\s*\.palette\.(\w+)\s*\}\}", lambda m: pal[m.group(1)], open(tmpl).read()))
PY
rm -f "$shellroot/modules/theme/Palette.qml.tmpl"
cp -r "$dots/modules/common" "$shellroot/modules/common"
# the icon table the scene reads is generated from the registry, so it carries this module's names
python3 -I "$root/tools/gen-phosphor-qml.py" --stdout > "$shellroot/modules/common/PhosphorIcons.qml"
cp -r "$mod" "$shellroot/modules/session"
rm -rf "$shellroot/modules/session/tst"
cp "$tst/Scene.qml" "$shellroot/shell.qml"
ln -s "$dots/services" "$shellroot/services"

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  qsq="$(dirname "$(dirname "$(readlink -f "$QS")")")/lib/qt-6/qml"
  lintimp=(-I "$shellroot"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # the three files that hold Quickshell windows, processes and the polkit agent use attached and
  # grouped properties qmllint cannot resolve from plugin type info; those categories are relaxed
  # for them, everything else is linted at defaults.
  special="AwayPicker.qml SessionMenu.qml PolkitPrompt.qml"
  main=$(ls "$shellroot/modules/session"/*.qml | grep -v -e AwayPicker.qml -e SessionMenu.qml -e PolkitPrompt.qml)
  sp=""; for f in $special; do sp="$sp $shellroot/modules/session/$f"; done
  lintout="$("$QML_LINT" "${lintimp[@]}" $main 2>&1 | grep -v '^$')"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable \
      --missing-property disable --incompatible-type disable $sp 2>&1 | grep -v '^$')"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi

# ---- 4. scenes ---------------------------------------------------------------------------
for f in AwayPicker SessionMenu PolkitPrompt; do
  sed -i "/^$f /d" "$shellroot/modules/session/qmldir"; rm -f "$shellroot/modules/session/$f.qml"
done
xdg="$(mktemp -d /tmp/sesx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
env OUT_DIR="$SHOTS" FIXTURE="$tst/fixtures/session.json" XDG_RUNTIME_DIR="$xdg" \
    timeout 60 "$QS" -p "$shellroot" > "$work/scene.log" 2>&1
sed 's/\x1b\[[0-9;]*m//g' "$work/scene.log" > "$work/scene.log.clean"
grep -a 'PROBE ' "$work/scene.log.clean" | sed 's/^.*PROBE //' > "$work/probes.txt"

n=$(wc -l < "$work/probes.txt")
[ "$n" -ge 14 ] && ok "4 scene rendered $n states" || { head -12 "$work/scene.log.clean"; bad "4 scene rendered only $n of 14 states"; }
missing=0
for t in board-session away-near away-far away-select session-idle session-blocked session-pending polkit-idle polkit-error polkit-agent return-declared return-detected return-full empty; do
  [ -s "$SHOTS/$t.png" ] || { echo "missing PNG $t"; missing=$((missing + 1)); }
done
[ "$missing" -eq 0 ] && ok "4 a PNG for every state in $SHOTS" || bad "4 $missing PNG(s) missing"

python3 -I - "$work/probes.txt" <<'PY' || fails=$((fails + 1))
import json, sys
P = {}
for ln in open(sys.argv[1]):
    tag, js = ln.split(" ", 1)
    P[tag] = json.loads(js)
bad = []
def need(c, msg):
    if not c: bad.append(msg)

# board: session card 360 wide at (440, 500), six buttons in two columns, note, password card
b = P["board-session"]
need(len(b["sess"]) == 6 and len({s["x"] for s in b["sess"]}) == 2 and all(s["h"] >= 58 for s in b["sess"]), "board: six buttons, 2 columns, >=58 high")
need(b["sessIds"] == "lock logout suspend reboot poweroff backup".split(), "board: button order %s" % b["sessIds"])
need(len(b["note"]) == 1, "board: blocked note shown")
need(len(b["pwField"]) == 1 and b["pwField"][0]["h"] == 36 and b["pwField"][0]["w"] == 440 - 32, "board: password field 36 high, full width")
need(len(b["pwAllow"]) == 1 and b["pwAllow"][0]["h"] == 28 and len(b["pwDeny"]) == 1 and b["pwDeny"][0]["h"] == 28, "board: Allow and Deny 28 high")
need(b["pwAllow"][0]["x"] < b["pwDeny"][0]["x"], "board: Allow left of Deny")
need(all(s["x"] >= 440 + 16 for s in b["sess"]), "board: buttons inside the 360 card")

# picker: six rows, 44 high, equal width, stacked
for t in ("away-near", "away-far", "away-select"):
    a = P[t]
    need(len(a["away"]) == 6, "%s: six rows, got %d" % (t, len(a["away"])))
    need(all(r["h"] == 44 for r in a["away"]), t + ": row height 44")
    need(len({r["w"] for r in a["away"]}) == 1 and a["away"][0]["w"] == 420 - 32, t + ": rows fill the 420 card")
    ys = [r["y"] for r in a["away"]]
    need(ys == sorted(ys) and len(set(ys)) == 6, t + ": rows stack top to bottom")
    need(a["card"] and a["card"]["w"] == 420, t + ": card 420 wide")
need(P["away-near"]["awayIds"] == "salah washroom walk meal meeting logout".split(), "near a prayer salah leads: %s" % P["away-near"]["awayIds"])
need(P["away-far"]["awayIds"][-1] == "salah" and P["away-far"]["awayIds"][0] == "washroom", "far from a prayer salah is last")
need(P["away-near"]["sel"] == 0 and P["away-near"]["hints"][0] == "Enter" and P["away-near"]["hints"][1] == "2", "first row is the Enter target, others show their number")
need(P["away-select"]["sel"] == 3 and P["away-select"]["hints"][3] == "Enter", "selection moves the Enter hint")

# session card states
i, k = P["session-idle"], P["session-blocked"]
need(i["sessLive"] == [True, True, True, True, True, False], "idle: all live except backup, got %s" % i["sessLive"])
need(len(i["note"]) == 0, "idle: no blocked note")
need(k["sessLive"] == [True, False, True, False, False, False], "blocked: log out, reboot, shut down, backup grey, got %s" % k["sessLive"])
need(len(k["note"]) == 1, "blocked: note shown")
d = P["session-pending"]
need(d["sessLive"] == [True, False, True, False, False, False], "pending: log out, reboot, shut down, backup grey, got %s" % d["sessLive"])

# password card states
need(len(P["polkit-idle"]["pwError"]) == 0 and len(P["polkit-idle"]["pwAgent"]) == 0, "polkit idle: no error, no agent line")
need(len(P["polkit-error"]["pwError"]) == 1, "polkit error: error line shown")
need(len(P["polkit-agent"]["pwAgent"]) == 1 and P["polkit-agent"]["denyFocus"] is True, "polkit agent: line shown and Deny holds focus")
need(P["polkit-idle"]["denyFocus"] is False, "polkit idle: field, not Deny, holds focus")
for t in ("polkit-idle", "polkit-error", "polkit-agent"):
    need(P[t]["pwField"][0]["h"] == 36, t + ": field 36 high")

# return rows
need(P["return-declared"]["retIds"] == ["gap"], "return declared: one row")
need(P["return-detected"]["retIds"] == ["gap"], "return detected: one row")
need(P["return-full"]["retIds"] == ["gap", "agent", "mail"], "return full: gap, agent, mail")
for t in ("return-declared", "return-detected", "return-full"):
    need(all(r["h"] == 40 for r in P[t]["ret"]), t + ": row height 40")

# empty
need(len(P["empty"]["away"]) == 0, "empty: no rows drawn")

if bad:
    print("\n".join("FAIL 4 " + x for x in bad)); sys.exit(1)
print("PASS 4 geometry probes: board layout, picker, session card, password card, return rows, empty")
PY

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|SCENE TIMEOUT|FIXTURE ERROR|Cannot read property' "$work/scene.log.clean" 2>/dev/null | head -5 | grep .; then bad "4 QML errors in the scene log"; else ok "4 no QML errors in the scene log"; fi

[ "$fails" -eq 0 ] && { echo "session-ui ok"; exit 0; }
echo "session-ui: $fails failure(s)"; exit 1
