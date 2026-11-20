#!/usr/bin/env bash
# launcher-ui: tests for the launcher core and its first providers (modules/launcher). No compositor: the
# REAL Card renders from the REAL LauncherState with the real All, Apps, Commands, Math and Clipboard
# providers (fixture files, the real Python helpers, shimmed wl-copy/herdr/dots-launch) under Quickshell on
# Qt's offscreen platform; one PNG per board state, probes on geometry, rows and what each action ran.
#   1  qmltestrunner  js/Model (prefix, cycle, All rank, recents, selection, key routing, fuzzy)
#   2  python         launcher_math, launcher_cmds, launcher_recents, dots-clip (encryption, filters, pins, clear)
#   3  qmllint        every .qml against a generated tree (other modes' providers are the real ones)
#   4  static rules   tokens not hex, Phosphor not PUA, argv-only, no shell, no network or send, no loops
#   5  scenes         every board state + key flows + action argv logs
# PNGs go to ${SHOTS_DIR:-$(mktemp -d)}. Tools: quickshell and Qt6 qmltestrunner/qmllint on PATH or in the
# nix store; without them the QML parts SKIP, the Python part always runs.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
L="$mod/launcher"
clipsrc="$root/home/private_dot_local/private_bin/executable_dots-clip"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/lnx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }

# ---- 2. python (no Qt needed) ------------------------------------------------------------
if [ -z "${ONLY_SCENE:-}" ]; then
for t in math cmds recents clip; do
  if DOTS_CLIP="$clipsrc" python3 -W ignore -I "$L/tst/test_$t.py" > "$work/py-$t.log" 2>&1; then ok "2 python: $t ($(grep -E '^Ran' "$work/py-$t.log"))"
  else tail -25 "$work/py-$t.log"; bad "2 python: $t"; fi
done
[ -x "$clipsrc" ] && ok "2 dots-clip is executable" || bad "2 dots-clip is not executable"
fi

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
  echo "SKIP launcher-ui QML parts: quickshell and Qt6 qmltestrunner not found and could not be built"
  [ "$fails" -eq 0 ] && { echo "launcher-ui ok (python only)"; exit 0; }; exit 1
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

mkqmldir() { # dir module
  ( cd "$1" && { echo "module $2"; for f in *.qml; do [ -e "$f" ] || continue; n="${f%.qml}"
      if grep -q '^pragma Singleton' "$f"; then echo "singleton $n 1.0 $f"; else echo "$n 1.0 $f"; fi; done; } > qmldir )
}

# ---- 1. unit tests -----------------------------------------------------------------------
if [ -z "${ONLY_SCENE:-}" ]; then
res="$(timeout 120 "$QTR" -input "$L/tst" 2>&1)"
echo "$res" | grep -E '^(FAIL|Totals)'
echo "$res" | grep -q ' 0 failed' && ok "1 qmltestrunner: launcher model" || bad "1 qmltestrunner: launcher model"

# ---- 3. qmllint --------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules/bar"
  for m in theme common barpop launcher; do mkdir -p "$lint/modules/$m"; cp "$mod/$m/"*.qml "$lint/modules/$m/"; done
  for d in parts providers; do mkdir -p "$lint/modules/launcher/$d"; cp "$L/$d/"*.qml "$lint/modules/launcher/$d/"; done
  cp "$L/tst/Stub.qml" "$lint/modules/launcher/providers/Stub.qml"
  cp -r "$L/js" "$lint/modules/launcher/js"
  cp -r "$mod/barpop/js" "$lint/modules/barpop/js"; cp -r "$mod/bar/js" "$lint/modules/bar/js"
  cp "$mod/theme/Palette.qml.tmpl" "$lint/modules/theme/Palette.qml"
  sed -i 's/{{ \.palette\.[a-z_]* }}/#000000/' "$lint/modules/theme/Palette.qml"; rm -f "$lint/modules/theme/Palette.qml.tmpl"
  cp -r "$mod/overview" "$lint/modules/overview"; rm -rf "$lint/modules/overview/tst"
  cp -r "$dots/services" "$lint/services"
  for m in theme common barpop launcher overview; do mkqmldir "$lint/modules/$m" qs.modules.$m; done
  for d in parts pages; do [ -d "$lint/modules/overview/$d" ] && mkqmldir "$lint/modules/overview/$d" qs.modules.overview.$d; done
  mkqmldir "$lint/modules/launcher/parts" qs.modules.launcher.parts
  mkqmldir "$lint/modules/launcher/providers" qs.modules.launcher.providers
  mkqmldir "$lint/services" qs.services
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  lm="$lint/modules/launcher"
  mine=("$lm"/LauncherState.qml "$lm"/parts/*.qml "$lm"/providers/{All,Apps,Commands,Math,Clipboard,Stub}.qml)
  # Process, Instantiator and the window type are what qmllint cannot fully resolve from plugin type info
  lintout="$("$QML_LINT" "${lintimp[@]}" "${mine[@]}" 2>&1)"
  lintout+="$("$QML_LINT" "${lintimp[@]}" --uncreatable-type disable --unresolved-type disable --unqualified disable "$lm"/Launcher.qml 2>&1)"
  if [ -z "$lintout" ]; then ok "3 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "3 qmllint reported diagnostics"; fi
else
  echo "SKIP 3 qmllint not available"
fi
[ -n "${ONLY_LINT:-}" ] && { [ "$fails" -eq 0 ] && exit 0 || exit 1; }

# ---- 4. static rules ---------------------------------------------------------------------
mine_qml="$(ls "$L"/*.qml "$L"/parts/*.qml "$L"/providers/{All,Apps,Commands,Math,Clipboard}.qml)"
mine_js="$(ls "$L"/js/*.js)"
mine_py="$(ls "$L"/js/*.py) $clipsrc"
srcs="$mine_qml $mine_js"
if grep -nE '#[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "4 hex colour in a source (use Theme.color.*)"; else ok "4 no hex colours"; fi
if grep -nE 'font\.family:\s*"|Nerd' $srcs; then bad "4 hard-coded font"; else ok "4 no hard-coded font"; fi
if grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' $mine_qml $mine_js $mine_py 2>/dev/null | grep .; then bad "4 private-use codepoint (use Phosphor names)"; else ok "4 no PUA codepoints"; fi
if grep -nE 'execDetached\(' $srcs | grep -vE 'execDetached\(\['; then bad "4 execDetached not an array literal of strings first"; else ok "4 every exec is an argv array"; fi
if grep -nE '"(sh|bash|zsh)"|-c"|SplitParser|os\.system|shell *= *True|Popen\(" |subprocess\.[a-z_]+\("' $srcs $mine_py | grep -v '^\S*:[0-9]*:\s*#'; then bad "4 a shell string"; else ok "4 no shell strings"; fi
if grep -nEi 'sendmail|smtp|chat\.postMessage|api\.github|XMLHttpRequest|https?://|urllib|http\.client|requests|socket|curl |wget|pnow-erp|gh (pr|issue)' $srcs $mine_py | grep -vE '^\S+:[0-9]+:\s*(//|#)' | grep -v 'example.com'; then bad "4 a network or send path"; else ok "4 no network or send path"; fi
if grep -rInE '\bgreen\b|00ff00' $srcs | grep -vE '^\S+:[0-9]+:\s*//'; then bad "4 green appears"; else ok "4 no green"; fi
if grep -nE 'SequentialAnimation|loops:\s*Animation.Infinite|RotationAnimator|running: *true' $srcs; then bad "4 an animation loop (nothing pulses)"; else ok "4 nothing pulses"; fi
if grep -nE 'implicitHeight: *[0-9]+ *$' /dev/null; then :; fi
if grep -nE 'Quickshell\.(env)\("[A-Z_]*(TOKEN|SECRET|PASSWORD)' $srcs; then bad "4 reads a secret from the environment"; else ok "4 no secret read"; fi
for f in $mine_js "$L"/js/*.py "$clipsrc"; do
  grep -q 'SPDX-License-Identifier: MIT' "$f" && ok "4 $(basename "$f") carries the MIT header" || bad "4 $(basename "$f") lacks the MIT header"
done
# every Phosphor name the launcher uses (QML literals and the helpers' icon fields) is in the font registry
miss="$(python3 -I - "$root/nix/pkgs/dots-icon-font/codepoints.tsv" "$L" "$clipsrc" <<'PY'
import ast, glob, os, re, sys
reg = {l.split("\t")[0] for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")}
used = set()
for f in glob.glob(os.path.join(sys.argv[2], "*.qml")) + glob.glob(os.path.join(sys.argv[2], "parts", "*.qml")) + \
         [os.path.join(sys.argv[2], "providers", n + ".qml") for n in ("All", "Apps", "Commands", "Math", "Clipboard")]:
    for ln in open(f):
        if re.search(r"\b(Icon)\s*\{", ln) or re.match(r"\s*icon\s*:", ln) or re.search(r"[{,;]\s*icon\s*:", ln):
            used.update(re.findall(r'\b(?:name|icon)\s*:\s*"([a-z][a-z0-9-]*)"', ln))
        used.update(re.findall(r'icon: *"([a-z][a-z0-9-]*)"', ln))
        used.update(re.findall(r'\|\| *"([a-z][a-z0-9-]*)"', ln) if "icon" in ln else [])
        if re.search(r'name: *root\.why === "salah" \?', ln): used.update(re.findall(r'\? *"([a-z][a-z0-9-]*)" *: *"([a-z][a-z0-9-]*)"', ln)[0])
for f in glob.glob(os.path.join(sys.argv[2], "js", "*.py")) + [sys.argv[3]]:
    t = ast.parse(open(f).read())
    for n in ast.walk(t):
        if isinstance(n, ast.Dict):
            for k, v in zip(n.keys, n.values):
                if isinstance(k, ast.Constant) and k.value == "icon" and isinstance(v, ast.Constant): used.add(v.value)
        if isinstance(n, ast.FunctionDef) and n.name == "icon_for":
            for r in ast.walk(n):
                if isinstance(r, ast.Constant) and isinstance(r.value, str) and re.fullmatch(r"[a-z]+(-[a-z]+)*", r.value) and r.value not in ("kind", "image", "text", "https") or (isinstance(r, ast.Constant) and r.value == "image"):
                    used.add(r.value)
used -= {"kind", "text", "https", "http"}
print(" ".join(sorted(u for u in used if u and u not in reg)))
PY
)"
[ -z "$miss" ] && ok "4 every icon name resolves in the Phosphor registry" || bad "4 icons missing from the registry: $miss"

fi   # ONLY_SCENE skips 1-4

# ---- 5. scenes ---------------------------------------------------------------------------
# shell root: the real theme (Palette from palette.yaml), the real common/ with an icon table generated from
# every name in the tree, and the launcher without its window (Launcher.qml needs the live services).
shellroot="$work/root"; mkdir -p "$shellroot/modules"
cp -r "$mod/theme" "$shellroot/modules/theme"
python3 -I - "$root/home/.chezmoidata/palette.yaml" "$mod/theme/Palette.qml.tmpl" "$shellroot/modules/theme/Palette.qml" <<'PY'
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
cp -r "$mod/common" "$shellroot/modules/common"
python3 -I "$root/tools/gen-phosphor-qml.py" --stdout > "$shellroot/modules/common/PhosphorIcons.qml"
mkdir -p "$shellroot/modules/barpop"; cp "$mod/barpop/Gly.qml" "$shellroot/modules/barpop/"; printf 'module qs.modules.barpop\nGly 1.0 Gly.qml\n' > "$shellroot/modules/barpop/qmldir"
lr="$shellroot/modules/launcher"; mkdir -p "$lr/parts" "$lr/providers"
cp "$L/LauncherState.qml" "$lr/"; cp -r "$L/js" "$lr/js"; cp "$L/parts/"* "$lr/parts/"
for p in Provider All Apps Commands Math Clipboard; do cp "$L/providers/$p.qml" "$lr/providers/"; done
cp "$L/tst/Stub.qml" "$lr/providers/Stub.qml"
printf 'module qs.modules.launcher\nLauncherState 1.0 LauncherState.qml\n' > "$lr/qmldir"
mkqmldir "$lr/providers" qs.modules.launcher.providers
cp "$L/tst/Scene.qml" "$shellroot/shell.qml"

# fixtures: desktop entries, commands, recents, clipboard history, and shims that log what would have run
fx="$work/fx"; mkdir -p "$fx/apps/applications" "$fx/cfg" "$fx/st" "$fx/clip" "$fx/bin" "$fx/shim" "$fx/log" "$fx/home"
cat > "$fx/apps/applications/dbconsole.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=DB-02 Console
GenericName=Database client
Exec=true
D
cat > "$fx/apps/applications/browser.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=Firefox
GenericName=Web browser
Comment=Browse the web
Exec=true
D
cat > "$fx/cfg/commands.json" <<'D'
[{"id": "ssh-db-02", "name": "ssh db-02", "tags": ["ssh"], "cmd": "ssh db-02"},
 {"id": "pods", "name": "Pods not running", "tags": ["k8s"], "cmd": "kubectl get pods -A --field-selector=status.phase!=Running"},
 {"id": "pressure", "name": "Node pressure", "tags": ["k8s"], "cmd": "kubectl describe nodes | grep -A5 Conditions"},
 {"id": "ns", "name": "Pods in a namespace", "tags": ["k8s"], "cmd": "kubectl get pods -n <namespace>"}]
D
cp "$clipsrc" "$fx/bin/dots-clip"; chmod +x "$fx/bin/dots-clip"
for n in wl-copy dots-launch notify-send; do
  cat > "$fx/shim/$n" <<S
#!/usr/bin/env bash
{ printf 'ARGV'; printf '\t%s' "\$@"; echo; } >> "$fx/log/$n.log"
[ -t 0 ] || { printf 'STDIN\t'; cat; echo; } >> "$fx/log/$n.log"
exit 0
S
done
cat > "$fx/shim/herdr" <<S
#!/usr/bin/env bash
{ printf 'ARGV'; printf '\t%s' "\$@"; echo; } >> "$fx/log/herdr.log"
case "\$1 \$2" in
  "pane list")  echo '{"result":{"panes":[{"pane_id":"t:p1","focused":true}]}}';;
  "pane split") echo '{"result":{"pane":{"pane_id":"t:p9"}}}';;
  *) echo '{}';;
esac
S
chmod +x "$fx/shim/"*
# HOME stays the real one: the GL wrapper caches under it and rebuilds slowly under a fake HOME
fxenv=(DOTS_CLIP_STATE="$fx/clip" DOTS_LAUNCHER_STATE="$fx/st" DOTS_LAUNCHER_CONFIG="$fx/cfg" XDG_RUNTIME_DIR="$xdg" DOTS_THEME_TOKENS=/nonexistent/tokens.json)
export PATH="$fx/shim:$PATH"
png() { python3 -I -c "
import struct, sys, zlib
w, h = 640, 380
raw = b''.join(b'\x00' + bytes(v for x in range(w) for v in ((x * 255 // w), (y * 255 // h), 160)) for y in range(h))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
sys.stdout.buffer.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))"; }
( export "${fxenv[@]}" DOTS_CLIP_TYPES=text/plain
  png | "$fx/bin/dots-clip" store --image
  echo "https://example.com/pull/2291" | "$fx/bin/dots-clip" store
  echo "kubectl get nodes -o wide" | "$fx/bin/dots-clip" store
  r="$L/js/launcher_recents.py"
  python3 -I "$r" add '{"p":"cmd","key":"pods","title":"Pods not running","sub":"k8s, used 41 times","icon":"terminal-window","q":"pods"}' >/dev/null
  python3 -I "$r" add '{"p":"apps","key":"browser","title":"Firefox","sub":"Web browser","icon":"app-window","q":"firefox"}' >/dev/null
  python3 -I "$r" add '{"p":"math","key":"math","title":"8192","sub":"1024 * 8","icon":"calculator","q":"1024 * 8"}' >/dev/null
  python3 -I "$r" add '{"p":"cmd","key":"ssh-db-02","title":"ssh db-02","sub":"ssh, used 3 times","icon":"terminal-window","q":"ssh db"}' >/dev/null )

run_scene() {
  env OUT_DIR="$shots" "${fxenv[@]}" DOTS_LAUNCHER_BIN="$fx/bin" XDG_DATA_HOME="$fx/apps" XDG_DATA_DIRS="$fx/apps" \
      timeout "${SCENE_TIMEOUT:-170}" "$QS" -p "$shellroot" > "$work/scene.log" 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' "$work/scene.log"
  grep -a 'PROBE ' "$work/scene.log" | sed 's/^.*PROBE //' > "$work/scene.probes"
}
run_scene
n=$(wc -l < "$work/scene.probes")
[ "$n" -ge 40 ] && ok "5 scene walked $n steps" || { grep -aE 'ERROR|WARN' "$work/scene.log" | head -12; bad "5 scene reached only $n of 41 steps"; }

python3 -I - "$work/scene.probes" "$shots" "$fx/log" "$fx/clip" <<'PY' && ok "5 probes: layout, rows, keys, actions" || bad "5 probes"
import json, os, sys
probes, shots, logs, clipdir = sys.argv[1:5]
P = {}
try:
    for ln in open(probes):
        tag, js = ln.strip().split(" ", 1)
        P[tag] = json.loads(js)
except Exception as e:
    print("FAIL no probes (%s)" % e); sys.exit(1)
fails = []
def need(c, msg):
    if not c: fails.append(msg)
def vis(m, name): return [e for e in m["names"].get(name, []) if e["visible"]]
def texts(m, name): return [e.get("text", "") for e in vis(m, name)]
def titles(m): return [e["title"] for e in vis(m, "row")]
def log(name):
    p = os.path.join(logs, name + ".log")
    return [l.rstrip("\n").split("\t") for l in open(p)] if os.path.exists(p) else []

steps = """all-recents all-query all-math all-nomatch clip clip-filter clip-image clip-nomatch dict-word dict-grammar files fonts
fonts-icon cmd cmd-secondary cmd-new math math-units tab-next tab-back backspace-chip confirm confirm-esc confirm-enter esc-clear
esc-close act-app act-app-open act-math act-math-copy act-cmd act-cmd-run act-clip act-clip-pin act-clip-paste act-clip-delete
recents-after recents-run locked salah error""".split()
for t in steps:
    need(t in P, "%s: step missing" % t)
    f = os.path.join(shots, "launcher-%s.png" % t)
    need(os.path.isfile(f) and os.path.getsize(f) > 3000, "%s: PNG missing or empty" % t)

# ---- geometry that holds in every state --------------------------------------------------
for t, m in P.items():
    need((m["card"]["w"], m["card"]["h"]) == (1080, 620), "%s: card %s, board says 1080x620" % (t, m["card"]))
    if m["blocked"]:
        need(len(vis(m, "closedCard")) == 1 and not vis(m, "row") and not vis(m, "tab") and not vis(m, "field"), "%s: closed card only" % t)
        continue
    sb = vis(m, "searchBar"); need(len(sb) == 1 and sb[0]["h"] == 56 and sb[0]["w"] == 1080, "%s: search bar 56 high" % t)
    tb = vis(m, "tabs"); need(len(tb) == 1 and tb[0]["h"] == 40 and tb[0]["y"] == 57, "%s: tabs 40 high under the search bar" % t)
    tabs = vis(m, "tab")
    need([e["tab"] for e in tabs] == ["all", "clip", "dict", "files", "fonts", "cmd", "math"], "%s: chips %s" % (t, [e["tab"] for e in tabs]))
    need(len([e for e in tabs if e["active"]]) == 1 and [e for e in tabs if e["active"]][0]["tab"] == m["mode"], "%s: exactly the current mode is active" % t)
    need(all(e["h"] == 28 for e in tabs), "%s: chips 28 high" % t)
    rs = vis(m, "results"); pv = vis(m, "preview")
    need(len(rs) == 1 and len(pv) == 1 and rs[0]["w"] == 491 and pv[0]["x"] == 491 and pv[0]["w"] == 589, "%s: results 5fr | preview 6fr (%s %s)" % (t, rs, pv))
    for e in vis(m, "row"):
        need(e["h"] == 44, "%s: row %s is %s high" % (t, e["title"], e["h"]))
        need(e["x"] >= 8 and e["x"] + e["w"] <= 491, "%s: row inside the left column" % t)
    need(len([e for e in vis(m, "row") if e["selected"]]) == (1 if m["nrows"] else 0) or m["nrows"] > len(vis(m, "row")), "%s: one selected row" % t)
    ft = vis(m, "footer"); need(len(ft) == 1 and ft[0]["h"] == 32 and ft[0]["y"] == 588, "%s: footer 32 high at the bottom" % t)
    need(texts(m, "hints") == ["Nav N/E move · Enter use · Tab mode · Esc close"], "%s: key hints %s" % (t, texts(m, "hints")))
    need(not (m["names"].get("empty") and vis(m, "empty") and m["nrows"]), "%s: empty state shown with rows" % t)
    acts = vis(m, "action")
    if m["nrows"] and not m["confirm"]:
        need(all(e["x"] >= 491 for e in acts), "%s: actions live in the preview pane" % t)
        if acts: need(acts[0]["primary"] and not any(e["primary"] for e in acts[1:]), "%s: only action 0 is primary" % t)
        if acts: need(all(e["h"] == 28 for e in acts), "%s: action buttons 28 high" % t)

# ---- board states ---------------------------------------------------------------------------
m = P["all-recents"]
need(m["mode"] == "all" and m["query"] == "" and m["nrows"] == 4, "all-recents: four recents, got %s" % m["nrows"])
need(titles(m) == ["ssh db-02", "8192", "Firefox", "Pods not running"], "all-recents: newest first %s" % titles(m))
need(not vis(m, "prefix"), "all-recents: no prefix chip in All")
m = P["all-query"]
need(titles(m)[:2] == ["ssh db-02", "DB-02 Console"] and set(titles(m)) >= {"DB-02 Console", "Add vCPUs to db-02", "ssh db-02", "db-02 in Infra"}, "all-query: merged rows, the recent command boosted above the app %s" % titles(m))
need(m["sel"] == 0 and not m["busy"] and "Searching" not in m["status"], "all-query: top row selected and every provider answered (sel %s busy %s)" % (m["sel"], m["busy"]))
need("Save a new command" not in titles(m), "all-query: the Save row stays out of All")
m = P["all-math"]
need(titles(m)[0] == "8192", "all-math: the sum ranks first %s" % titles(m))
m = P["all-nomatch"]
need(m["nrows"] == 0 and len(vis(m, "empty")) == 1, "all-nomatch: empty state")
m = P["clip"]
need(m["mode"] == "clip" and texts(m, "prefix") == ["c:"] and m["query"] == "", "clip: typing c: moves into the chip (%s)" % texts(m, "prefix"))
need(titles(m) == ["kubectl get nodes -o wide", "https://example.com/pull/2291", "Screenshot, 640 × 380", "Hidden: copied from a password manager"], "clip: rows %s" % titles(m))
need([e["label"] for e in vis(m, "action")] == ["Paste", "Pin", "Delete"], "clip: actions %s" % [e["label"] for e in vis(m, "action")])
need(texts(m, "head") == ["Text"], "clip: head %s" % texts(m, "head"))
need(texts(m, "field") == [""], "clip: the field holds no prefix")
m = P["clip-filter"]
need(titles(m) == ["kubectl get nodes -o wide"], "clip-filter: %s" % titles(m))
m = P["clip-image"]
need(len(vis(m, "image")) == 1 and texts(m, "head") == ["Image"], "clip-image: image preview")
m = P["clip-nomatch"]
need(m["nrows"] == 0 and "matches" in texts(m, "empty")[0], "clip-nomatch: %s" % texts(m, "empty"))
m = P["dict-word"]
need(m["mode"] == "dict" and titles(m)[0] == "idempotent" and texts(m, "head") == ["idempotent"], "dict-word")
need([e["label"] for e in vis(m, "action")] == ["Copy word", "Check my text"], "dict-word: actions")
m = P["dict-grammar"]; need(m["sel"] == 1 and texts(m, "head") == ["Check grammar"], "dict-grammar")
m = P["files"]; need(m["nrows"] == 3 and len(vis(m, "action")) == 3, "files: three rows, three actions")
m = P["fonts"]; need(m["nrows"] == 3 and texts(m, "head") == ["JetBrains Mono 0O Il1"], "fonts")
need(vis(m, "head")[0]["h"] >= 40, "fonts: the font name is shown large")
m = P["fonts-icon"]; need(texts(m, "head") == ["terminal-window"], "fonts-icon")
m = P["cmd"]
need(m["mode"] == "cmd" and texts(m, "prefix") == [">"] and m["query"] == "k8s", "cmd: prefix chip and query")
need(titles(m)[-1] == "Save a new command" and m["nrows"] == 4, "cmd: three k8s commands and the Save row %s" % titles(m))
need([e["label"] for e in vis(m, "action")] == ["Run in pane", "Copy", "Edit"], "cmd: actions")
m = P["cmd-secondary"]
need(m["sec"] == 1 and [e["picked"] for e in vis(m, "action")] == [False, True, False], "cmd-secondary: Ctrl+J picks the first secondary")
m = P["cmd-new"]; need(titles(m) == ["Save a new command"] and vis(m, "row")[0]["sub"] == "Enter saves: my cmd", "cmd-new: only the Save row, naming the command (%s)" % [e.get("sub") for e in vis(m, "row")])
m = P["math"]
need(m["mode"] == "math" and texts(m, "prefix") == ["="] and titles(m) == ["8192"], "math: prefix chip and one row %s" % titles(m))
need([e["label"] for e in vis(m, "action")] == ["Copy result"], "math: Copy result")
m = P["math-units"]; need(titles(m) == ["3072 MiB"], "math-units: %s" % titles(m))
m = P["tab-next"]; need(m["mode"] == "clip", "tab-next: Tab moves All -> Clipboard, got %s" % m["mode"])
m = P["tab-back"]; need(m["mode"] == "math", "tab-back: Shift+Tab twice wraps to Math, got %s" % m["mode"])
m = P["backspace-chip"]; need(m["mode"] == "all", "backspace-chip: Backspace on an empty chip returns to All")
m = P["confirm"]
need(m["confirm"] and len(vis(m, "confirmCard")) == 1 and texts(m, "confirmTitle") == ["Send to agent?"], "confirm: card shown")
need(len(vis(m, "confirmGo")) == 1 and len(vis(m, "confirmCancel")) == 1, "confirm: two buttons")
m = P["confirm-esc"]; need(not m["confirm"] and m["query"] == "restore" and m["closes"] == 0, "confirm-esc: Esc closes only the card")
m = P["confirm-enter"]; need(not m["confirm"] and m["closes"] == 1 and m["farewell"] == "Done: runbooks/restore.md" and not m["open"], "confirm-enter: Enter confirms, the second activate runs, the window closes (%s %s)" % (m["closes"], m["farewell"]))
m = P["esc-clear"]; need(m["query"] == "" and m["closes"] == 1 and m["open"], "esc-clear: Esc clears the field first (%r %s)" % (m["query"], m["closes"]))
m = P["esc-close"]; need(m["closes"] == 2 and not m["open"], "esc-close: Esc on an empty field closes (%s)" % m["closes"])
m = P["act-app"]; need(titles(m)[:1] == ["DB-02 Console"] and m["sel"] == 0, "act-app: the app is the top row (%s)" % titles(m))
m = P["act-app-open"]; need(m["closes"] == 3 and not m["open"], "act-app: closes (%s)" % m["closes"])
need(["ARGV", "dbconsole"] in log("dots-launch"), "act-app: ran `dots-launch dbconsole` (%s)" % log("dots-launch"))
m = P["act-math-copy"]; need(m["closes"] == 4 and m["farewell"] == "Copied 4", "act-math: %s %s" % (m["closes"], m["farewell"]))
need(["ARGV", "4"] in log("wl-copy"), "act-math: wl-copy 4")
m = P["act-cmd-run"]; need(m["closes"] == 5 and m["status"], "act-cmd: closes (%s, sel %s)" % (m["closes"], m["sel"]))
h = log("herdr")
need(["ARGV", "pane", "run", "t:p9", "kubectl get pods -A --field-selector=status.phase!=Running"] in h, "act-cmd: herdr pane run argv (%s)" % h[-3:])
need(any(l[:4] == ["ARGV", "pane", "split", "--pane"] for l in h), "act-cmd: split a pane first")
m = P["act-clip-pin"]; need(m["toast"] == "Pinned" and m["nrows"] == 1, "act-clip-pin: %s rows=%s" % (m["toast"], m["nrows"]))
need("Pinned" in vis(m, "row")[0]["sub"], "act-clip-pin: the row says Pinned (%s)" % vis(m, "row")[0]["sub"])
m = P["act-clip-paste"]; need(m["closes"] == 6 and m["farewell"].startswith("Copied"), "act-clip-paste: %s %s" % (m["closes"], m["farewell"]))
w = log("wl-copy")
need(["ARGV", "--type", "text/plain"] in w and any(l[0] == "STDIN" and "kubectl get nodes" in l[1] for l in w), "act-clip-paste: wl-copy got the text on stdin")
m = P["act-clip-delete"]; need(m["toast"] == "Deleted" and m["nrows"] == 0, "act-clip-delete: %s rows=%s" % (m["toast"], m["nrows"]))
m = P["recents-after"]
need(titles(m)[:3] == ["Pods not running", "4", "DB-02 Console"], "recents-after: activations are remembered %s" % titles(m))
need("kubectl get nodes -o wide" not in titles(m) and "Pins" not in titles(m), "recents-after: the clipboard (sensitive) never appears in Recents")
m = P["recents-run"]; need(m["closes"] == 7, "recents-run: re-queries the provider, runs action 0, closes (%s)" % m["closes"])
runs = [l for l in log("herdr") if l[:3] == ["ARGV", "pane", "run"]]
need(len(runs) >= 2, "recents-run: herdr ran twice (%d)" % len(runs))
m = P["locked"]; need(texts(m, "closedTitle") == ["Locked. The launcher stays closed."], "locked: %s" % texts(m, "closedTitle"))
m = P["salah"]; need("Salah" in texts(m, "closedTitle")[0], "salah: closed card")
m = P["error"]; need(titles(m) == ["The word list is not installed."], "error: one error row %s" % titles(m))
# nothing plaintext in the clipboard store, and no preview left behind after the last close
blob = b"".join(open(os.path.join(clipdir, f), "rb").read() for f in os.listdir(clipdir))
need(b"kubectl get nodes" not in blob and b"example.com" not in blob, "clip store holds plaintext")
if fails:
    print("\n".join("FAIL 5 " + x for x in fails)); sys.exit(1)
print("PASS 5 geometry on every state, board contents, key routing, confirm flow, action argv")
PY

if grep -aE 'ERROR|Type .* unavailable|is not a type|ReferenceError|TypeError|SCENE TIMEOUT|Cannot read property|Binding loop' "$work/scene.log" | head -8 | grep .; then bad "5 QML errors in the scene log"; else ok "5 no QML errors in the scene log"; fi

[ "$fails" -eq 0 ] && { echo "launcher-ui ok"; exit 0; }
echo "launcher-ui: $fails failure(s)"; exit 1
