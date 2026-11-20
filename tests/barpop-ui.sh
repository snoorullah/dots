#!/usr/bin/env bash
# barpop-ui: tests for the five bar popups (modules/barpop, modules/calendar). No compositor:
# it renders the REAL panel bodies from fixtures under Quickshell on Qt's offscreen platform
# with the real Theme, writes one PNG per state and asserts geometry and visibility probes.
#   1  qmltestrunner  js/Salah, Waiting, Agents, Tray, Cal
#   2  qmllint        every .qml, resolved against a generated qs/ tree
#   3  static rules   no hex colours, no PUA, argv-only exec, no shell, icons in the registry
#   4  scenes         salah, waiting, agent, tray, calendar states: probes plus PNGs
# PNGs go to $SHOTS_DIR (default: a temp dir). Tools: quickshell and Qt6 qmltestrunner/qmllint,
# found on PATH or in the nix store, else built from nixpkgs. With none, the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
bp="$mod/barpop"; cal="$mod/calendar"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/bpx.XXXXXX)"; chmod 700 "$xdg"
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
  QTD="$(nixbin qt6.qtdeclarative)"
  QTR="${QTD:+$QTD/bin/qmltestrunner}"; QML_LINT="${QTD:+$QTD/bin/qmllint}"
fi
if [ -z "$QS" ] || [ -z "${QTR:-}" ]; then
  echo "SKIP barpop-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

# ---- 1. unit tests -----------------------------------------------------------------------
for d in "$bp" "$cal"; do
  res="$(timeout 120 "$QTR" -input "$d/tst" 2>&1)"
  echo "$res" | grep -E '^(FAIL|Totals)'
  echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: $(basename "$d")" || bad "1 qmltestrunner: $(basename "$d")"
done

# ---- 2. qmllint --------------------------------------------------------------------------
mkqmldir() { # dir module
  ( cd "$1" && { echo "module $2"; for f in *.qml; do [ -e "$f" ] || continue; n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
}
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules"
  for m in theme common barpop calendar; do mkdir -p "$lint/modules/$m"; cp "$mod/$m/"*.qml "$lint/modules/$m/"; done
  cp -r "$bp/js" "$lint/modules/barpop/js"; cp -r "$cal/js" "$lint/modules/calendar/js"
  cp "$mod/theme/Palette.qml.tmpl" "$lint/modules/theme/Palette.qml"
  sed -i 's/{{ \.palette\.[a-z_]* }}/#000000/' "$lint/modules/theme/Palette.qml"; rm -f "$lint/modules/theme/Palette.qml.tmpl"
  cp -r "$mod/overview" "$lint/modules/overview"; rm -rf "$lint/modules/overview/tst"
  cp -r "$dots/services" "$lint/services"
  for m in theme common barpop calendar overview; do mkqmldir "$lint/modules/$m" qs.modules.$m; done
  for d in parts pages; do [ -d "$lint/modules/overview/$d" ] && mkqmldir "$lint/modules/overview/$d" qs.modules.overview.$d; done
  mkqmldir "$lint/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # Popout children never touch the window; the Quickshell window types and grouped properties
  # (margins, anchors) are what qmllint cannot resolve, so the three categories are relaxed for
  # the five Popout files only.
  files=("$lint"/modules/barpop/*.qml "$lint"/modules/calendar/*.qml)
  panels=(); pops=()
  for f in "${files[@]}"; do case "$f" in *Popout.qml) pops+=("$f");; *) panels+=("$f");; esac; done
  lintout="$("$QML_LINT" "${lintimp[@]}" "${panels[@]}" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "${pops[@]}" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
own=("$bp" "$cal")
srcs="$(find "${own[@]}" -name '*.qml' ! -path '*/tst/*') $(find "${own[@]}" -name '*.js' ! -path '*/tst/*')"
if grep -nE '#[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 hex colour in a source (use Theme.color.*)"; else ok "3 no hex colours"; fi
if grep -nE 'font\.family:\s*"|Nerd' $srcs; then bad "3 hard-coded font"; else ok "3 no hard-coded font"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "${own[@]}" 2>/dev/null | grep .; then bad "3 private-use codepoint"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $srcs | grep -vE 'execDetached\(\["'; then bad "3 execDetached not an argv array literal"; else ok "3 every exec is an argv array"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|Process *\{|StdioCollector|SplitParser' $srcs; then bad "3 a shell or Process is used"; else ok "3 no shell, no Process"; fi
if grep -nEi 'sendmail|smtp|slack|chat\.postMessage|api\.github|XMLHttpRequest' $srcs | grep -v '^\S*:[0-9]*:\s*//'; then bad "3 a network or send path"; else ok "3 no network or send path"; fi
if grep -rInE 'green|#[0-9a-f]*00ff00' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 green appears"; else ok "3 no green"; fi
# panels size icons by box through Gly, never by font size through Icon
if grep -nE '\bIcon\s*\{' $(find "$bp" "$cal" -name '*.qml' ! -path '*/tst/*' ! -name Gly.qml); then bad "3 Icon{} used in a panel (use Gly { box: N })"; else ok "3 icons sized by box (Gly)"; fi
# icon names resolve in the generated registry (run tools/gen-phosphor-qml.py to add new ones)
miss="$(python3 -I - "$mod/common/PhosphorIcons.qml" "$bp" "$cal" <<'PY'
import os, re, sys
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(sys.argv[1]).read(), re.M))
used = set()
for d in sys.argv[2:]:
    for dp, dn, fn in os.walk(d):
        dn[:] = [x for x in dn if x != "tst"]
        for f in fn:
            src = open(os.path.join(dp, f)).read()
            if f.endswith(".qml"):
                for ln in src.splitlines():
                    if re.search(r'\b(?:Icon|Gly)\s*\{', ln):
                        used.update(re.findall(r'\bname:\s*"([a-z][a-z0-9_-]*)"', ln))
                for m in re.finditer(r'\busedIcons:\s*\(\{([^}]*)\}\)', src):
                    used.update(re.findall(r'"([a-z][a-z0-9_-]*)"', m.group(1)))
            elif f.endswith(".js"):
                for m in re.finditer(r'\bicon:\s*(?:\w+\s*\?\s*)?"([a-z-]+)"(?:\s*:\s*"([a-z-]+)")?', src):
                    used.update(g for g in m.groups() if g)
                for m in re.finditer(r'\bICON\s*=\s*\{([^}]*)\}', src):
                    used.update(re.findall(r'"([a-z][a-z0-9-]*)"', m.group(1)))
print(" ".join(sorted(used - names)))
PY
)"
[ -z "$miss" ] && ok "3 every icon name resolves in PhosphorIcons" || bad "3 icons missing from the registry (run python3 tools/gen-phosphor-qml.py): $miss"

# ---- 4. scenes ---------------------------------------------------------------------------
shellroot="$work/root"; mkdir -p "$shellroot/modules/theme"
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
for m in common barpop calendar; do ln -s "$mod/$m" "$shellroot/modules/$m"; done
cp "$bp/tst/Scene.qml" "$shellroot/shell.qml"
mkdir -p "$work/home" "$work/out"

run_panel() { # panel
  local p="$1"
  env PANEL="$p" OUT_DIR="$shots" FIXDIR="$bp/tst/fixtures" CALFIX="$cal/tst/fixtures/calendar.json" \
      XDG_RUNTIME_DIR="$xdg" HOME="$work/home" timeout 60 "$QS" -p "$shellroot" > "$work/out/$p.log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$work/out/$p.log"
  grep -a 'PROBE ' "$work/out/$p.log" | sed 's/^.*PROBE //' > "$work/out/$p.probes"
}
for p in salah waiting agent tray calendar; do run_panel "$p"; done

python3 -I - "$work/out" "$shots" <<'PY' && ok "4 probes: geometry and visibility on every state" || bad "4 probes"
import json, os, sys
out, shots = sys.argv[1], sys.argv[2]
fails = []
def load(p):
    cases = {}
    for ln in open(os.path.join(out, p + ".probes")):
        tag, js = ln.strip().split(" ", 1)
        cases[tag] = json.loads(js)
    return cases
def vis(m, name): return [e for e in m["names"].get(name, []) if e["visible"]]
def texts(m, name): return [e.get("text", "") for e in vis(m, name)]
def need(cond, msg):
    if not cond: fails.append(msg)

expect = {
    "salah": ["normal", "soon", "now", "friday", "stale", "nofile"],
    "waiting": ["default", "problem", "empty", "stale", "chat", "overflow"],
    "agent": ["needs", "second", "quiet", "empty"],
    "tray": ["list", "filtered", "drill", "empty"],
    "calendar": ["default", "soon", "meeting", "prayer", "stale", "freeday", "month", "unverified"],
}
data = {}
for p, tags in expect.items():
    try: data[p] = load(p)
    except Exception as e: fails.append(p + ": no probes (" + str(e) + ")"); continue
    for t in tags:
        need(t in data[p], "%s/%s: state missing" % (p, t))
        f = os.path.join(shots, "%s-%s.png" % (p, t))
        need(os.path.isfile(f) and os.path.getsize(f) > 2000, "%s/%s: PNG missing or empty" % (p, t))

# every visible named item sits inside its card (a clipped control is a layout bug)
for p, cs in data.items():
    for t, m in cs.items():
        cw, ch = m["card"]["w"], m["card"]["h"]
        need(cw > 100 and ch > 60, "%s/%s: card has no size" % (p, t))
        for name, es in m["names"].items():
            if name in ("stubTip", "timeline"): continue
            for e in es:
                if e["visible"] and e["w"] > 0 and e["h"] > 0:
                    need(e["x"] >= 20 - 1 and e["x"] + e["w"] <= 20 + cw + 1, "%s/%s: %s overflows the card horizontally (%s)" % (p, t, name, e))
                    need(e["y"] + e["h"] <= 20 + ch + 1 or name in ("gly", "tlRow", "prRow", "evRow", "heldRow", "nowRow", "evDetail", "emptyRow"), "%s/%s: %s overflows the card vertically (%s)" % (p, t, name, e))

# icons paint at their box: Gly's art is ~0.6 em, so a 16 px box must come out near 16 px, not 10
nglyph = 0
for p, cs in data.items():
    for t, m in cs.items():
        for e in m["names"].get("gly", []):
            if not e["visible"]: continue
            nglyph += 1
            need(e["w"] == e["box"] and e["h"] == e["box"], "%s/%s: glyph box %sx%s != %s" % (p, t, e["w"], e["h"], e["box"]))
            need(0.9 * e["box"] <= e["px"] <= 1.1 * e["box"], "%s/%s: glyph paints %spx in a %spx box" % (p, t, e["px"], e["box"]))
need(nglyph >= 20, "only %d glyphs probed" % nglyph)

s = data.get("salah", {})
if s:
    m = s["normal"]
    need(texts(m, "heroName") == ["Asr 15:42"], "salah/normal: hero is %s" % texts(m, "heroName"))
    need(texts(m, "prayerTime") == ["05:12", "12:28", "15:42", "18:21", "19:48"], "salah/normal: times %s" % texts(m, "prayerTime"))
    need(len(vis(m, "prayerRow")) == 5, "salah/normal: five rows")
    need(texts(m, "sunrise") == ["SUNRISE 06:31"], "salah/normal: sunrise %s" % texts(m, "sunrise"))
    need(not vis(m, "cachedBadge"), "salah/normal: cached badge shown")
    need(len(vis(m, "hero")) == 1 and 60 <= vis(m, "hero")[0]["h"] <= 120, "salah/normal: hero box height")
    need(texts(s["now"], "heroName") == ["Now: Asr"], "salah/now: hero")
    need(texts(s["friday"], "heroName") == ["Jumuah 12:28"], "salah/friday: hero %s" % texts(s["friday"], "heroName"))
    need(len(vis(s["stale"], "cachedBadge")) == 1, "salah/stale: cached badge")
    need(not vis(s["nofile"], "prayerRow") and len(vis(s["nofile"], "noTimes")) == 1, "salah/nofile: says nothing rather than guess")
    # the bar of the hero grows with the progress: soon is further along than normal
    need(vis(s["soon"], "heroBar")[0]["w"] > vis(s["normal"], "heroBar")[0]["w"], "salah: hero bar does not advance")
    ys = [e["y"] for e in vis(m, "prayerRow")]
    need(ys == sorted(ys) and len(set(ys)) == 5, "salah/normal: rows are not stacked top to bottom")

w = data.get("waiting", {})
if w:
    m = w["default"]
    need(len(vis(m, "waitRow")) == 6, "waiting/default: six rows max, got %d" % len(vis(m, "waitRow")))
    need(len(vis(m, "chip")) == 5, "waiting/default: five kind chips")
    need(len(vis(m, "actOpen")) == 1 and len(vis(m, "actDone")) == 1, "waiting/default: only the focused row has actions")
    need(len(vis(m, "prayerHint")) == 1 and texts(m, "prayerHint") == ["prayer in 12m"], "waiting/default: prayer hint")
    need(not vis(m, "banner"), "waiting/default: banner without a problem")
    need(len(vis(m, "footer")) == 1, "waiting/default: footer")
    subj = texts(m, "subj")
    need(subj[0] == "Re: Quarterly report draft", "waiting/default: red mail first, got %s" % subj[:2])
    need(len(vis(w["problem"], "banner")) == 1, "waiting/problem: red banner")
    need(texts(w["problem"], "subj")[0] == "Local backup failed twice", "waiting/problem: the problem is first")
    need(len(vis(w["empty"], "emptyState")) == 1 and not vis(w["empty"], "waitRow") and not vis(w["empty"], "footer"), "waiting/empty")
    need(len(vis(w["stale"], "banner")) == 1, "waiting/stale: unknown banner")
    need(len(vis(w["chat"], "waitRow")) == 1 and texts(w["chat"], "title") == ["Chat"], "waiting/chat: filtered to one row")
    need(len(vis(w["overflow"], "waitRow")) == 6, "waiting/overflow: capped at six")
    ys = [e["y"] for e in vis(m, "waitRow")]
    need(ys == sorted(ys), "waiting/default: rows out of order")

a = data.get("agent", {})
if a:
    need(len(vis(a["needs"], "agentCard")) == 2 and texts(a["needs"], "agentPill") == ["Needs you 2"], "agent/needs: two cards and a count")
    need(len(vis(a["needs"], "actApprove")) == 1 and len(vis(a["needs"], "actDeny")) == 1, "agent/needs: focused card has approve and deny")
    need(len(vis(a["needs"], "runRow")) == 2 and texts(a["needs"], "budget") == ["$0.38 / $1"], "agent/needs: running rows and budget")
    need(len(vis(a["quiet"], "quiet")) == 1 and not vis(a["quiet"], "agentCard"), "agent/quiet: nothing needs you")
    need(texts(a["quiet"], "agentPill") == ["All clear"], "agent/quiet: pill")
    need(len(vis(a["empty"], "quiet")) == 1 and not vis(a["empty"], "runRow"), "agent/empty: no agents.json")
    h = [e["y"] for e in vis(a["needs"], "agentCard")]
    need(h == sorted(h), "agent/needs: cards out of order")

t = data.get("tray", {})
if t:
    need(len(vis(t["list"], "trayRow")) == 5, "tray/list: five rows")
    need(len(vis(t["list"], "actOpen")) == 1, "tray/list: the selected row shows Open")
    need(len(vis(t["filtered"], "trayRow")) == 2, "tray/filtered: two matches, got %d" % len(vis(t["filtered"], "trayRow")))
    need(len(vis(t["drill"], "menuItem")) == 7 and len(vis(t["drill"], "drillBack")) == 1 and not vis(t["drill"], "trayRow"), "tray/drill: menu replaces the list")
    need(len(vis(t["empty"], "emptyState")) == 1 and not vis(t["empty"], "trayRow") and not vis(t["empty"], "filterBox"), "tray/empty")
    need(texts(t["list"], "appName")[0] == "Team chat", "tray/list: needs-attention app first")

c = data.get("calendar", {})
if c:
    need(texts(c["default"], "clock") == ["09:18"] and texts(c["default"], "dateLine") == ["Tue 3 Nov"], "calendar/default: header")
    need(texts(c["default"], "stripTitle") == ["Standup in 12m"], "calendar/default: strip %s" % texts(c["default"], "stripTitle"))
    need(len(vis(c["default"], "evDetail")) == 1, "calendar/default: opened event shows its details")
    need(len(vis(c["default"], "weekDay")) == 7 and len(vis(c["default"], "todayChip")) == 1, "calendar/default: week strip and Today chip")
    need(len(vis(c["default"], "openCal")) == 1 and len(vis(c["default"], "addEvent")) == 1, "calendar/default: footer stubs")
    need(texts(c["soon"], "stripTitle") == ["Standup in 6m"], "calendar/soon: strip")
    need(len(vis(c["soon"], "stripBtn")) == 1, "calendar/soon: Join stub")
    need(texts(c["meeting"], "stripTitle") == ["In meeting, 18m left"], "calendar/meeting: strip")
    need(texts(c["prayer"], "stripTitle") == ["Asr window open"], "calendar/prayer: strip")
    need(len(vis(c["stale"], "staleChip")) == 1 and len(vis(c["stale"], "banner")) == 1 and not vis(c["stale"], "todayChip"), "calendar/stale: unknown chip and banner")
    need(len(vis(c["freeday"], "emptyRow")) == 1, "calendar/freeday: Nothing scheduled")
    need(len(vis(c["month"], "monthCell")) == 42 and len(vis(c["month"], "monthView")) == 1 and not vis(c["month"], "weekStrip"), "calendar/month: 42 cells replace the week")
    need(len(vis(c["unverified"], "banner")) == 1, "calendar/unverified: banner")
    ys = [e["y"] for e in vis(c["default"], "tlRow")]
    need(ys == sorted(ys), "calendar/default: timeline rows out of order")
    need(len(vis(c["default"], "nowRow")) == 1, "calendar/default: now marker")
    need(len(vis(c["default"], "heldRow")) == 1, "calendar/default: held block")

if fails:
    print("\n".join("  " + f for f in fails)); sys.exit(1)
PY

errs="$(cat "$work"/out/*.log 2>/dev/null | grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|is not defined' | head -8)"
if [ -n "$errs" ]; then echo "$errs"; bad "4 QML errors in a scene log"; else ok "4 no QML errors in any scene log"; fi

[ "$fails" -eq 0 ] && { echo "barpop-ui ok ($shots)"; exit 0; }
echo "barpop-ui: $fails failure(s)"; exit 1
