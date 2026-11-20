#!/usr/bin/env bash
# system-ui: tests for the Quickshell system panel (modules/system). No compositor needed:
# it renders the real components from a fixture state under Quickshell on Qt's offscreen
# platform, writes a PNG per board state and asserts on geometry probes.
#   1  qmltestrunner  js/Parse and js/Menus (parsers, model, argv builders)
#   2  qmllint        every .qml in modules/system
#   3  static rules   no hard-coded colour or font, argv-only exec, no shell, no sends
#   4  scenes         board layouts, popout views, all twelve menus, empty state
# PNGs go to ${SHOTS_DIR:-$(mktemp -d)}. Tools: quickshell and Qt6 qmltestrunner/qmllint,
# found on PATH or built from nixpkgs once. Without quickshell the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
sys="$dots/modules/system"
tst="$sys/tst"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work"' EXIT
SHOTS="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$SHOTS"
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
  QTD="$(nixbin qt6.qtdeclarative)"
  QTR="${QTD:+$QTD/bin/qmltestrunner}"; QML_LINT="${QTD:+$QTD/bin/qmllint}"
fi
if [ -z "$QS" ] || [ -z "${QTR:-}" ]; then
  echo "SKIP system-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none

# ---- 1. unit tests -----------------------------------------------------------------------
res="$(timeout 120 "$QTR" -input "$tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: Parse, Menus" || bad "1 qmltestrunner"

# ---- 3. static rules ---------------------------------------------------------------------
qmls=$(ls "$sys"/*.qml)
if grep -nE '#[0-9a-fA-F]{3,8}\b' $qmls | grep -v '^\S*: *//' | grep .; then bad "3 a hex colour in QML (use Theme.color.*)"; else ok "3 no hex colours in QML"; fi
if grep -nE 'font\.family *: *"|"(JetBrains|Bricolage|dots Icons)' $qmls | grep .; then bad "3 a hard-coded font family"; else ok "3 no hard-coded font names"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$sys" 2>/dev/null | grep .; then bad "3 a file carries a private-use codepoint (use Icon names)"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $qmls | grep -vE 'execDetached\((\[|act\.argv)' | grep .; then bad "3 execDetached with something other than an argv array"; else ok "3 every exec is an argv array"; fi
if grep -nE '"(sh|bash|zsh)"|"-c"' $qmls "$sys"/js/*.js | grep .; then bad "3 a shell in the panel"; else ok "3 no shell strings"; fi
if grep -nEi 'slack|gmail|smtp|sendmail|curl|wget|XMLHttpRequest|pnow-erp|gh (pr|issue)' $qmls "$sys"/js/*.js | grep .; then bad "3 a remote send path"; else ok "3 no send or remote-write path"; fi
for f in "$sys"/js/*.js; do
  grep -q 'SPDX-License-Identifier: MIT' "$f" && ok "3 $(basename "$f") carries the MIT header" || bad "3 $(basename "$f") lacks the MIT header"
done

# ---- 4. scenes ---------------------------------------------------------------------------
# shell root: the real theme (Palette rendered from palette.yaml), the real common/, an icon
# table generated from the registry so it includes this module's names, and a copy of the module
# without SystemPanel (that one needs the live services; it is linted, not rendered here).
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
python3 -I "$root/tools/gen-phosphor-qml.py" --stdout > "$shellroot/modules/common/PhosphorIcons.qml"
cp -r "$sys" "$shellroot/modules/system"
rm -rf "$shellroot/modules/system/tst"
cp "$tst/Scene.qml" "$shellroot/shell.qml"
ln -s "$dots/services" "$shellroot/services"
lsys="$shellroot/modules/system"

# ---- 2. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  qsq="$(dirname "$(dirname "$(readlink -f "$QS")")")/lib/qt-6/qml"
  lintimp=(-I "$shellroot"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # SystemPanel and SysState use Quickshell types (Popout is a PanelWindow, Process, Bluetooth
  # devices) whose attached and grouped properties qmllint cannot resolve from plugin type info;
  # those categories are relaxed for those two files, everything else is linted at defaults.
  main=$(ls "$lsys"/*.qml | grep -v -e SystemPanel.qml -e SysState.qml)
  lintout="$("$QML_LINT" "${lintimp[@]}" $main 2>&1 | grep -v '^$')"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable \
      --missing-property disable --incompatible-type disable "$lsys/SystemPanel.qml" "$lsys/SysState.qml" 2>&1 | grep -v '^$')"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi

sed -i '/^SystemPanel /d' "$lsys/qmldir"
xdg="$(mktemp -d /tmp/sysx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
run_scene() {  # LABEL FIXTURE
  local label="$1" fixture="$2" log="$work/scene-$1.log"
  env OUT_DIR="$SHOTS" FIXTURE="$fixture" XDG_RUNTIME_DIR="$xdg" \
      timeout 60 "$QS" -p "$shellroot" > "$log" 2>&1
  sed 's/\x1b\[[0-9;]*m//g' "$log" > "$log.clean"
  grep -a 'PROBE ' "$log.clean" | sed 's/^.*PROBE //' > "$work/probes-$label.txt"
}
run_scene full "$tst/fixtures/system.json"

n=$(wc -l < "$work/probes-full.txt")
[ "$n" -ge 18 ] && ok "4 scene rendered $n states" || { head -12 "$work/scene-full.log.clean"; bad "4 scene rendered only $n of 18 states"; }
missing=0
for t in board-system board-menus popout-quick popout-session popout-wifi empty menu-wifi menu-bt menu-quiet menu-vpn menu-ts menu-mic menu-night menu-awake menu-perf menu-theme menu-sound menu-display; do
  [ -s "$SHOTS/$t.png" ] || { echo "missing PNG $t"; missing=$((missing + 1)); }
done
[ "$missing" -eq 0 ] && ok "4 a PNG for every state in $SHOTS" || bad "4 $missing PNG(s) missing"

python3 -I - "$work/probes-full.txt" <<'PY' || fails=$((fails + 1))
import json, sys
P = {}
for ln in open(sys.argv[1]):
    tag, js = ln.split(" ", 1)
    P[tag] = json.loads(js)
bad = []
def need(c, msg):
    if not c: bad.append(msg)

# board: tiles 2-col, 48 high, equal width; three meters 30 high, full width
b = P["board-system"]
need(len(b["tiles"]) == 10, "board-system: ten tiles, got %d" % len(b["tiles"]))
need(b["tileIds"] == "wifi bt quiet vpn ts mic night awake perf theme".split(), "tile order")
need(all(t["h"] == 48 for t in b["tiles"]), "tile height 48")
need(len({t["w"] for t in b["tiles"]}) == 1 and 178 <= b["tiles"][0]["w"] <= 186, "tile width ~181, got %s" % b["tiles"][0]["w"])
need(len({t["x"] for t in b["tiles"]}) == 2, "two tile columns")
need(len({t["y"] for t in b["tiles"]}) == 5, "five tile rows")
need(len(b["meters"]) == 3 and all(m["h"] == 30 and m["w"] == b["panel"]["w"] - 32 for m in b["meters"]), "three 30 px meters")
need(len(b["media"]) == 1 and b["media"][0]["h"] == 60, "media row 60 high")
need(len(b["log"]) == 1, "notification log shown")
need(len(b["sess"]) == 6, "board-system: six session buttons, got %d" % len(b["sess"]))
need(len({s["x"] for s in b["sess"]}) == 2 and all(s["h"] >= 58 for s in b["sess"]), "session grid 2 col, at least 58 high")
need(len(b["ctx"]) == 7 + 5, "board-system: window (7) + desktop (5) right-click rows, got %d" % len(b["ctx"]))
need(all(c["h"] == 28 for c in b["ctx"]), "ctx row height 28")
need(len(b["power"]) == 1, "power button visible")

m = P["board-menus"]
need(m["card"] and m["card"]["w"] == 420 and m["card"]["x"] == 440, "board-menus: menu card 420 wide at x=440")
need(m["rows"][0] == "toggle" and m["rows"].count("head") == 3 and m["rows"][-1] == "actions", "wifi rows: toggle, 3 heads, actions last")
need(m["rows"].count("item") == 5, "wifi: 4 networks + wired, got %d items" % m["rows"].count("item"))
need(m["back"] and m["back"][0]["w"] == 28, "menu back button 28 px")

for t, want in [("popout-quick", None), ("popout-wifi", None)]:
    p = P[t]
    need(p["panel"]["w"] == 400, t + ": card 400 wide")
need(len(P["popout-quick"]["tiles"]) == 10, "popout-quick tiles")
need(len(P["popout-wifi"]["tiles"]) == 0 and len(P["popout-wifi"]["rows"]) > 0, "popout-wifi swaps the tiles for rows")
need(len(P["popout-session"]["sess"]) == 6 and len(P["popout-session"]["tiles"]) == 0, "popout-session swaps to the session card")

e = P["empty"]
need(len(e["tiles"]) == 10, "empty state still lists ten tiles")
need(len(e["media"]) == 0 and len(e["log"]) == 0, "empty state: no media row, no log")

exp = {"wifi": ["toggle", "head", "item", "head", "item", "item", "item", "head", "item", "actions"],
       "bt": ["toggle", "head", "item", "item", "head", "item", "actions"],
       "quiet": ["choice", "choice", "head", "toggle", "toggle", "toggle", "toggle", "head", "item", "actions"],
       "mic": ["toggle", "head", "item", "item", "slider", "toggle", "head", "item", "choice", "actions"],
       "night": ["toggle", "slider", "choice", "head", "toggle", "toggle", "actions"],
       "theme": ["choice", "toggle", "head", "swatches", "actions"],
       "sound": ["slider", "head", "item", "actions"],
       "display": ["slider", "head", "monitors", "choice", "toggle", "actions"]}
for k, v in exp.items():
    need(P["menu-" + k]["rows"] == v, "menu-%s rows %s" % (k, P["menu-" + k]["rows"]))
for k in "wifi bt quiet vpn ts mic night awake perf theme sound display".split():
    c = P["menu-" + k]["card"]
    need(c and c["w"] == 420, "menu-%s card 420 wide" % k)
    need(c and c["h"] < 860, "menu-%s card under the 860 cap" % k)
if bad:
    print("\n".join("FAIL 4 " + x for x in bad)); sys.exit(1)
print("PASS 4 geometry probes: board layouts, popout swap, empty state, twelve menus")
PY

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|SCENE TIMEOUT|FIXTURE ERROR|Cannot read property' "$work"/scene-*.log.clean 2>/dev/null | head -5 | grep .; then bad "4 QML errors in the scene log"; else ok "4 no QML errors in the scene log"; fi

# ---- 5. wiring smoke: the real SystemPanel against the real services (Popout stubbed) ------
smoke="$work/smoke"; mkdir -p "$smoke/modules"
cp -r "$shellroot/modules/theme" "$smoke/modules/theme"
cp -r "$shellroot/modules/common" "$smoke/modules/common"
cp "$tst/Popout.stub.qml" "$smoke/modules/common/Popout.qml"
cp -r "$sys" "$smoke/modules/system"; rm -rf "$smoke/modules/system/tst"
ln -s "$dots/services" "$smoke/services"
cp "$tst/Smoke.qml" "$smoke/shell.qml"
env XDG_RUNTIME_DIR="$xdg" timeout 40 "$QS" -p "$smoke" < /dev/null > "$work/smoke.log" 2>&1
sed 's/\x1b\[[0-9;]*m//g' "$work/smoke.log" > "$work/smoke.log.clean"
python3 -I - "$work/smoke.log.clean" <<'PY' && ok "5 SystemPanel builds its state from the real services, opens on Ui.open, and runs acts" || bad "5 wiring smoke"
import json, sys
line = next((l for l in open(sys.argv[1]) if "SMOKE {" in l), None)
if not line: print("no SMOKE line"); sys.exit(1)
o = json.loads(line.split("SMOKE ", 1)[1])
want = "awake bright bt host media mic night notifs perf quiet screens session theme ts uptime vol vpn wifi".split()
ok = o.get("keys") == sorted(want) and o.get("wantedAfterOpen") is True and o.get("view") == "perf" \
     and o.get("viewAfterClose") == "" and o.get("vpnIsArray") is True
if not ok: print(o)
sys.exit(0 if ok else 1)
PY
if grep -aE 'ERROR|TypeError|ReferenceError|is not a type|SMOKE TIMEOUT' "$work/smoke.log.clean" | grep -v pipewire | head -5 | grep .; then bad "5 errors in the smoke log"; else ok "5 no QML errors in the smoke log"; fi

[ "$fails" -eq 0 ] && { echo "system-ui ok"; exit 0; }
echo "system-ui: $fails failure(s)"; exit 1
