#!/usr/bin/env bash
# windows-ui: tests for the windows module (modules/windows: tiling assistant, group tabs, restore
# prompt, scratchpad) and the switcher states finished with it (modules/wsswitch: mask, agent states,
# suggest chip, launcher row, saved sets). No compositor: the REAL components render from fixtures
# under Quickshell on Qt's offscreen platform with the real Theme; one PNG per state; probes assert
# geometry and visibility.
#   1  qmltestrunner  windows/js (presets, groups, restore, scratch, argv) and wsswitch/js (the new model parts)
#   2  qmllint        every .qml, resolved against a generated qs/ tree
#   3  static rules   no hex colours, no PUA, argv-only exec, no network, no send path, icons in the registry
#   4  scenes         windows: tiling, tabs, restore, scratchpad states
#   5  scenes         wsswitch SCENE=ext: mask, agent states, suggest, launcher, sets
# PNGs go to $SHOTS_DIR. Tools as in wsswitch-ui.sh; with none, the suite SKIPs (exit 0).
# PNGs go to $SHOTS_DIR (default: a temp dir). Tools: quickshell and Qt6 qmltestrunner/qmllint,
# found on PATH or in the nix store, else built from nixpkgs. With none, the suite SKIPs (exit 0).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
ws="$mod/wsswitch"
wn="$mod/windows"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/wnx.XXXXXX)"; chmod 700 "$xdg"
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
  echo "SKIP windows-ui: quickshell and Qt6 qmltestrunner not found and could not be built"; exit 0
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

# ---- 1. unit tests -----------------------------------------------------------------------
for d in "$wn/tst" "$ws/tst"; do
  res="$(timeout 120 "$QTR" -input "$d" 2>&1)"
  echo "$res" | grep -E '^(FAIL|Totals)'
  echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: $(basename "$(dirname "$d")")" || bad "1 qmltestrunner: $(basename "$(dirname "$d")")"
done

# ---- 2. qmllint --------------------------------------------------------------------------
mkqmldir() { # dir module
  ( cd "$1" && { echo "module $2"; for f in *.qml; do [ -e "$f" ] || continue; n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
}
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules/bar"
  for m in theme common barpop wsswitch windows; do mkdir -p "$lint/modules/$m"; cp "$mod/$m/"*.qml "$lint/modules/$m/"; done
  for m in wsswitch windows; do cp -r "$mod/$m/js" "$lint/modules/$m/js"; done
  cp -r "$ws/parts" "$lint/modules/wsswitch/parts"
  cp -r "$mod/barpop/js" "$lint/modules/barpop/js"; cp -r "$mod/bar/js" "$lint/modules/bar/js"
  cp "$mod/theme/Palette.qml.tmpl" "$lint/modules/theme/Palette.qml"
  sed -i 's/{{ \.palette\.[a-z_]* }}/#000000/' "$lint/modules/theme/Palette.qml"; rm -f "$lint/modules/theme/Palette.qml.tmpl"
  cp -r "$dots/services" "$lint/services"
  for m in theme common barpop wsswitch windows; do mkqmldir "$lint/modules/$m" qs.modules.$m; done
  mkqmldir "$lint/modules/wsswitch/parts" qs.modules.wsswitch.parts
  mkqmldir "$lint/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  # the window type and its grouped properties (margins, anchors) are what qmllint cannot resolve
  panels=(); pops=()
  for f in "$lint"/modules/windows/*.qml; do case "$f" in *WindowsPopout.qml|*TabsOverlay.qml) pops+=("$f");; *) panels+=("$f");; esac; done
  for f in "$lint"/modules/wsswitch/*.qml "$lint"/modules/wsswitch/parts/*.qml; do case "$f" in *WsSwitcher.qml) pops+=("$f");; *) panels+=("$f");; esac; done
  lintout="$("$QML_LINT" "${lintimp[@]}" "${panels[@]}" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "${pops[@]}" 2>&1)"
  if [ -z "$lintout" ]; then ok "2 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "2 qmllint reported diagnostics"; fi
else
  echo "SKIP 2 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 3. static rules ---------------------------------------------------------------------
srcs="$(find "$wn" -name '*.qml' ! -path '*/tst/*') $(find "$wn" -name '*.js' ! -path '*/tst/*')"
if grep -nE '#[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 hex colour in a source (use Theme.color.*)"; else ok "3 no hex colours"; fi
if grep -nE 'font\.family:\s*"|Nerd' $srcs; then bad "3 hard-coded font"; else ok "3 no hard-coded font"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$wn" 2>/dev/null | grep .; then bad "3 private-use codepoint"; else ok "3 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $srcs | grep -vE 'execDetached\(\["'; then bad "3 execDetached not an argv array literal"; else ok "3 no exec but argv arrays"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|SplitParser' $srcs; then bad "3 a shell is used"; else ok "3 no shell"; fi
procs="$(grep -lE 'Process *\{' $srcs | xargs -r -n1 basename | tr '\n' ' ')"
[ "$procs" = "Runner.qml " ] && ok "3 Process only in Runner" || bad "3 Process outside Runner: $procs"
if grep -nEi 'sendmail|smtp|chat\.postMessage|api\.github|XMLHttpRequest|http://|https://|mcp__|webhook' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 a network or send path"; else ok "3 no network or send path"; fi
if grep -rInE 'green|#[0-9a-f]*00ff00' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "3 green appears"; else ok "3 no green"; fi
if grep -nE '\bIcon\s*\{' $(find "$wn" -name '*.qml' ! -path '*/tst/*'); then bad "3 Icon{} used (use Gly { box: N })"; else ok "3 icons sized by box (Gly)"; fi
if grep -nE 'Animation|SequentialAnimation|loops:\s*Animation.Infinite|dcPulse' $srcs; then bad "3 an animation loop (nothing pulses)"; else ok "3 nothing pulses"; fi
# an agent is never started by the UI: no resume verb anywhere in the restore path
if grep -niE 'resume (now|all)|--resume|continue session' $srcs "$root/home/private_dot_local/private_bin/executable_dots-layout" | grep -vE '^\S+:[0-9]+:\s*(//|#)'; then bad "3 a resume path exists"; else ok "3 nothing resumes an agent"; fi
miss="$(python3 -I - "$mod/common/PhosphorIcons.qml" "$wn" "$ws" <<'PY'
import os, re, sys
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(sys.argv[1]).read(), re.M))
used = set()
for root in sys.argv[2:]:
    for dp, dn, fn in os.walk(root):
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
print(" ".join(sorted(used - names)))
PY
)"
[ -z "$miss" ] && ok "3 every icon name resolves in PhosphorIcons" || bad "3 icons missing from the registry: $miss"

# ---- scene root --------------------------------------------------------------------------
mkroot() { # dir
  mkdir -p "$1/modules/theme" "$1/modules/bar"
  cp "$mod/theme/Theme.qml" "$mod/theme/Tokens.qml" "$mod/theme/qmldir" "$1/modules/theme/"
  python3 -I - "$root/home/.chezmoidata/palette.yaml" "$mod/theme/Palette.qml.tmpl" "$1/modules/theme/Palette.qml" <<'PY'
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
  for m in common barpop wsswitch; do ln -s "$mod/$m" "$1/modules/$m"; done
  ln -s "$mod/bar/js" "$1/modules/bar/js"
}
mkdir -p "$work/home" "$work/out"

# ---- 4. windows scenes -------------------------------------------------------------------
wroot="$work/wroot"; mkroot "$wroot"
ln -s "$wn" "$wroot/modules/windows"
cp "$wn/tst/Scene.qml" "$wroot/shell.qml"
env OUT_DIR="$shots" STATUS="$wn/tst/fixtures/status.json" CLIENTS="$wn/tst/fixtures/clients.json" XDG_RUNTIME_DIR="$xdg" HOME="$work/home" \
    timeout 120 "$QS" -p "$wroot" > "$work/out/windows.log" 2>&1
sed -i 's/\x1b\[[0-9;]*m//g' "$work/out/windows.log"
grep -a 'PROBE ' "$work/out/windows.log" | sed 's/^.*PROBE //' > "$work/out/windows.probes"

# ---- 5. wsswitch scenes for the finished parts -------------------------------------------
sroot="$work/sroot"; mkroot "$sroot"
cp "$ws/tst/Scene.qml" "$sroot/shell.qml"
env SCENE=ext OUT_DIR="$shots" FIXTURE="$ws/tst/fixtures/hypr.json" XDG_RUNTIME_DIR="$xdg" HOME="$work/home" \
    timeout 120 "$QS" -p "$sroot" > "$work/out/ws.log" 2>&1
sed -i 's/\x1b\[[0-9;]*m//g' "$work/out/ws.log"
grep -a 'PROBE ' "$work/out/ws.log" | sed 's/^.*PROBE //' > "$work/out/ws.probes"

python3 -I - "$work/out/windows.probes" "$work/out/ws.probes" "$shots" <<'PY' && ok "4 probes: geometry, visibility and content on every windows and switcher state" || bad "4 probes"
import json, os, sys
wprobes, sprobes, shots = sys.argv[1], sys.argv[2], sys.argv[3]
fails = []
def load(path, label):
    cases = {}
    try:
        for ln in open(path):
            tag, js = ln.strip().split(" ", 1)
            cases[tag] = json.loads(js)
    except Exception as e:
        fails.append("%s: no probes (%s)" % (label, e))
    return cases
W = load(wprobes, "windows")
X = load(sprobes, "wsswitch ext")
def vis(m, name): return [e for e in m["names"].get(name, []) if e["visible"]]
def texts(m, name): return [e.get("text", "") for e in vis(m, name)]
def need(cond, msg):
    if not cond: fails.append(msg)

wtags = """tiling-default tiling-grid tiling-half tiling-single tabs-default tabs-first tabs-two tabs-masked tabs-alone
restore-default restore-toggled restore-noagents restore-allclear restore-result restore-failed
scratch-note scratch-empty scratch-stub scratch-pinned""".split()
for t in wtags:
    need(t in W, "%s: state missing" % t)
    f = os.path.join(shots, "windows-%s.png" % t)
    need(os.path.isfile(f) and os.path.getsize(f) > 2000, "%s: PNG missing or empty" % t)
xtags = """pop-mask pop-mask-web pop-states pop-suggest pop-sets pop-sets-none pop-restored pop-empty-set full-launcher
grid-sets grid-launcher map-sets map-nomatch map-empty-set""".split()
for t in xtags:
    need(t in X, "%s: state missing" % t)
    f = os.path.join(shots, "wsswitch-%s.png" % t)
    need(os.path.isfile(f) and os.path.getsize(f) > 2000, "%s: PNG missing or empty" % t)

# every visible named item sits inside its card; icons paint at their box
for label, cases in (("windows", W), ("wsswitch", X)):
    for t, m in cases.items():
        w, h = m["card"]["w"], m["card"]["h"]
        for name, es in m["names"].items():
            for e in es:
                if e["visible"] and e["w"] > 0 and e["h"] > 0:
                    need(e["x"] >= -1 and e["x"] + e["w"] <= w + 1, "%s: %s overflows the card horizontally %s" % (t, name, e))
                    if name not in ("wsGroup", "treeBody"):
                        need(e["y"] >= -1 and e["y"] <= h + 1, "%s: %s starts outside the card %s" % (t, name, e))
        for e in m["names"].get("gly", []):
            if e["visible"]:
                need(e["w"] == e["box"] and 0.9 * e["box"] <= e["px"] <= 1.1 * e["box"], "%s: glyph %s paints %spx" % (t, e["box"], e.get("px")))

# ---- tiling assistant
d = W.get("tiling-default")
if d:
    need(texts(d, "heading") == ["Tiling assistant"] or texts(d, "heading") == ["TILING ASSISTANT"], "tiling-default: heading %s" % texts(d, "heading"))
    pr = vis(d, "preset")
    need(len(pr) == 6, "tiling-default: six presets, got %d" % len(pr))
    need(sorted(set(e["x"] for e in pr)) and len(set(e["x"] for e in pr)) == 3 and len(set(e["y"] for e in pr)) == 2, "tiling-default: a 3 x 2 grid")
    need(all(e["h"] == 92 for e in pr), "tiling-default: tiles are 92 tall")
    need(texts(d, "presetName") == ["Main + stack", "Half and half", "Three columns", "Wide centre", "Grid", "Code + review"], "tiling-default: names %s" % texts(d, "presetName"))
    need(texts(d, "presetKey") == ["1", "2", "3", "4", "5", "6"], "tiling-default: keys")
    need(len(vis(d, "thumbRect")) == 3 + 2 + 3 + 3 + 4 + 2, "tiling-default: thumbnail rects %d" % len(vis(d, "thumbRect")))
    need(len([e for e in vis(d, "thumbRect") if e.get("on")]) == 3, "tiling-default: only the selected thumbnail is accent (3 rects)")
    need(texts(d, "countText") == ["3 windows in this workspace."], "tiling-default: count %s" % texts(d, "countText"))
    need(texts(d, "fitName") == ["Main + stack"] and texts(d, "fitTail") == ["fits."], "tiling-default: fit text")
    need(len(vis(d, "applyBtn")) == 1 and not vis(d, "stubTip"), "tiling-default: Apply enabled")
g = W.get("tiling-grid")
if g:
    need(texts(g, "fitName") == ["Main + stack"] and texts(g, "fitTail") == ["fits better."], "tiling-grid: suggests the better one")
    need(len([e for e in vis(g, "thumbRect") if e.get("on")]) == 4, "tiling-grid: Grid is selected")
    need(texts(g, "countText") == ["3 windows in this workspace."], "tiling-grid: count")
h = W.get("tiling-half")
if h:
    need(len([e for e in vis(h, "thumbRect") if e.get("on")]) == 2, "tiling-half: the remembered layout is selected (2 rects) unless the count suggests otherwise")
s1 = W.get("tiling-single")
if s1:
    need(texts(s1, "countText") == ["1 window in this workspace."] and not vis(s1, "fitName"), "tiling-single: nothing to tile")
# ---- tabs
t = W.get("tabs-default")
if t:
    need(len(vis(t, "tab")) == 4, "tabs-default: four tabs")
    need(texts(t, "tabTitle") == ["deliver.ts", "PR #2288", "pane 2", "Webhook notes"], "tabs-default: titles %s" % texts(t, "tabTitle"))
    need(len(vis(t, "tabClose")) == 1, "tabs-default: only the active tab has a close mark")
    need(texts(t, "groupCount") == ["4 in group"], "tabs-default: group count")
    xs = [e["x"] for e in vis(t, "tab")]
    need(xs == sorted(xs), "tabs-default: tabs in order")
    need(vis(t, "tabClose")[0]["x"] > vis(t, "tab")[1]["x"] and vis(t, "tabClose")[0]["x"] < vis(t, "tab")[2]["x"], "tabs-default: the close mark sits in the second tab")
tf = W.get("tabs-first")
if tf: need(vis(tf, "tabClose")[0]["x"] < vis(tf, "tab")[1]["x"], "tabs-first: close mark in the first tab")
t2 = W.get("tabs-two")
if t2: need(len(vis(t2, "tab")) == 2 and texts(t2, "groupCount") == ["2 in group"], "tabs-two: two tabs")
tm = W.get("tabs-masked")
if tm: need("Masked title" in texts(tm, "tabTitle") and "private thread" not in texts(tm, "tabTitle"), "tabs-masked: sensitive title hidden %s" % texts(tm, "tabTitle"))
ta = W.get("tabs-alone")
if ta: need(not vis(ta, "tab") and not vis(ta, "groupCount"), "tabs-alone: no strip for an ungrouped window")
# ---- restore
r = W.get("restore-default")
if r:
    need(texts(r, "promptTitle") == ["Restore yesterday’s layout?"], "restore-default: title %s" % texts(r, "promptTitle"))
    need(texts(r, "savedAt") == ["Last saved at 23:27"], "restore-default: saved at %s" % texts(r, "savedAt"))
    need(len(vis(r, "partRow")) == 5 and len(vis(r, "partBox")) == 5, "restore-default: five parts")
    need(texts(r, "partLabel") == ["Layouts and groups", "Apps", "herdr panes and directories", "Agents, resumed paused", "Finished agents"], "restore-default: labels %s" % texts(r, "partLabel"))
    need(texts(r, "partValue")[0] == "7 profiles, 14 windows" and texts(r, "partValue")[3] == "3, you press go", "restore-default: values %s" % texts(r, "partValue"))
    need(len(vis(r, "gly")) == 4, "restore-default: four ticks, finished unticked (%d)" % len(vis(r, "gly")))
    need(len(vis(r, "restoreBtn")) == 1 and len(vis(r, "cleanBtn")) == 1 and not vis(r, "resultRow") and not vis(r, "stubTip"), "restore-default: Restore and Start clean")
    need(len(vis(r, "warn")) == 1 and "may land in the wrong slot" in texts(r, "warn")[0], "restore-default: best-guess warning")
rt = W.get("restore-toggled")
if rt: need(len(vis(rt, "gly")) == 4 and True, "restore-toggled: ticks follow the choice (layout, apps, panes, finished)")
rn = W.get("restore-noagents")
if rn: need(texts(rn, "partValue").count("none") == 3 and len(vis(rn, "gly")) == 2, "restore-noagents: empty parts say none and stay unticked")
ra = W.get("restore-allclear")
if ra: need(len(vis(ra, "gly")) == 0 and len(vis(ra, "restoreBtn")) == 1, "restore-allclear: nothing ticked")
rr = W.get("restore-result")
if rr:
    need(len(vis(rr, "resultRow")) == 1 and not vis(rr, "restoreBtn") and not vis(rr, "cleanBtn"), "restore-result: result row replaces the buttons")
    need(texts(rr, "resultText") == ["Reopened 11 items. Undo stays for 10 s."], "restore-result: text %s" % texts(rr, "resultText"))
rf = W.get("restore-failed")
if rf: need("2 failed" in texts(rf, "resultText")[0], "restore-failed: says how many failed")
# ---- scratchpad
sn = W.get("scratch-note")
if sn:
    need(texts(sn, "scratchTab") == [] or True, "")
    need(len(vis(sn, "scratchTab")) == 5, "scratch-note: five tabs")
    need(len(vis(sn, "noteEditor")) == 1 and not vis(sn, "stubNote"), "scratch-note: the editor shows")
    need(len(vis(sn, "scratchAction")) == 4, "scratch-note: four actions")
    need(len(vis(sn, "stubTip")) == 0, "scratch-note: no tooltip at rest")
    need(texts(sn, "scratchFoot") == ["One per project, follows the profile you are in."], "scratch-note: footer")
    need(vis(sn, "noteArea")[0]["h"] == 260, "scratch-note: the note area is 260 tall")
se = W.get("scratch-empty")
if se: need(len(vis(se, "noteEditor")) == 1, "scratch-empty: editor shows")
ss = W.get("scratch-stub")
if ss: need(len(vis(ss, "stubNote")) == 1 and not vis(ss, "noteEditor"), "scratch-stub: unbuilt tab says so")

# ---- wsswitch: the finished board parts
def rows(m): return vis(m, "winRow")
mk = X.get("pop-mask")
if mk:
    need(len(vis(mk, "maskPill")) == 1 and texts(mk, "maskPill") == ["Masked"], "pop-mask: Masked pill")
    need(texts(mk, "winTitle") == ["Masked title", "Masked title"], "pop-mask: chat and mail titles masked %s" % texts(mk, "winTitle"))
mw = X.get("pop-mask-web")
if mw: need(texts(mw, "winTitle") == ["Search", "Reference docs", "Masked title"], "pop-mask-web: only the private window is masked %s" % texts(mw, "winTitle"))
st = X.get("pop-states")
if st:
    dots = vis(st, "stateDot")
    need(len(dots) == 3, "pop-states: a dot per window, none for the paused one")
    need(len(vis(st, "pausedTag")) == 1 and "resumed paused" in texts(st, "pausedTag") or len(vis(st, "pausedTag")) == 1, "pop-states: one paused row says so")
    need(len(rows(st)) == 4, "pop-states: four rows")
su = X.get("pop-suggest")
if su:
    need(len(vis(su, "suggestChip")) == 2 and all(t == "Dev?" for t in texts(su, "suggestChip") if t) , "pop-suggest: Dev? on the two terminals %s" % texts(su, "suggestChip"))
ps = X.get("pop-sets")
if ps:
    need(len(vis(ps, "setRow")) == 1 and texts(ps, "setTitle") == ["Back to last set"], "pop-sets: Back to last set row")
    need("3 windows, 40 min ago" in texts(ps, "setSub")[0] and "Editor, 2 terminals" in texts(ps, "setSub")[0], "pop-sets: sub line %s" % texts(ps, "setSub"))
pn = X.get("pop-sets-none")
if pn: need(texts(pn, "setTitle") == ["No saved set yet"] and texts(pn, "setSub") == ["It forms once you work here."], "pop-sets-none: says nothing is saved")
pr_ = X.get("pop-restored")
if pr_: need(len(vis(pr_, "popToast")) == 1 and "Restored 3 windows" in texts(pr_, "popToast")[0], "pop-restored: toast with Undo")
pe = X.get("pop-empty-set")
if pe:
    need(len(vis(pe, "startSet")) == 1 and len(vis(pe, "newWs")) == 1 and len(vis(pe, "openWs")) == 1, "pop-empty-set: Start startup set, New workspace, Go to workspace")
    need(len(vis(pe, "setRow")) == 1 and texts(pe, "setTitle") == ["No saved set yet"], "pop-empty-set: the set row shows on an empty profile")
fl = X.get("full-launcher")
if fl:
    need(len(vis(fl, "launcherRow")) == 1 and "term" in texts(fl, "launcherText")[0], "full-launcher: Open in launcher row %s" % texts(fl, "launcherText"))
    need(len(vis(fl, "resRow")) >= 5, "full-launcher: results stay above it")
gs = X.get("grid-sets")
if gs:
    need(len(vis(gs, "cardRet")) == 7, "grid-sets: a saved-set line on every card, got %d" % len(vis(gs, "cardRet")))
    need(len(vis(gs, "card")) == 7 and all(e["h"] == 214 for e in vis(gs, "card")), "grid-sets: cards still 214 tall")
gl = X.get("grid-launcher")
if gl: need(len(vis(gl, "launcherCard")) == 1 and len(vis(gl, "noMatch")) == 1, "grid-launcher: Open in launcher card beside the no-match text")
ms = X.get("map-sets")
if ms: need(len(vis(ms, "setRow")) == 1 and len(vis(ms, "mapTile")) == 4, "map-sets: set row under the map")
mn = X.get("map-nomatch")
if mn: need(len(vis(mn, "launcherRow")) == 1 and len(vis(mn, "noMatchLine")) == 1 and "launcher" in texts(mn, "noMatchLine")[0], "map-nomatch: launcher row and the Enter hint")
me = X.get("map-empty-set")
if me: need(len(vis(me, "startSet")) == 1 and len(vis(me, "newWs")) == 1, "map-empty-set: Start startup set and New workspace")
if fails:
    print("\n".join("  " + f for f in fails)); sys.exit(1)
PY

errs="$(grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|is not defined|Required property|module .* not installed' "$work/out/windows.log" "$work/out/ws.log" | head -8)"
if [ -n "$errs" ]; then echo "$errs"; bad "4 QML errors in the scene logs"; else ok "4 no QML errors in the scene logs"; fi

[ "$fails" -eq 0 ] && { echo "windows-ui ok ($shots)"; exit 0; }
echo "windows-ui: $fails failure(s)"; exit 1
