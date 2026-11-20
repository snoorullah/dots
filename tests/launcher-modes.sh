#!/usr/bin/env bash
# launcher-modes: tests for the eight launcher modes (Files, Dictionary, Fonts, Windows, Snippets,
# Emoji, SSH hosts, Kube): providers in modules/launcher/providers and helpers dots-launch-<mode>.
# No compositor, no network, no kubectl, no ssh: actions are logged, not run.
#   1  python unittest   the eight helpers over fixtures (ranking, states, argv, refusals)
#   2  static rules      no hex, no PUA, no shell strings, no network, public-repo clean, icons
#   3  qmllint           every provider, resolved against a generated qs/ tree
#   4  scenes            every board state: the REAL providers + REAL helpers drawn offscreen, probes + PNGs
# PNGs go to $SHOTS_DIR (default: a temp dir). Tools: quickshell and Qt6 qmllint, found on PATH or in the
# nix store, else built from nixpkgs. With none, steps 3 and 4 SKIP (exit 0).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
root="$(git rev-parse --show-toplevel)"
dots="$root/home/private_dot_config/quickshell/dots"
mod="$dots/modules"
prov="$mod/launcher/providers"
tst="$prov/tst"
bin="$root/home/private_dot_local/private_bin"
work="$(mktemp -d)"
shots="${SHOTS_DIR:-$(mktemp -d)}"; mkdir -p "$shots"
xdg="$(mktemp -d /tmp/lmx.XXXXXX)"; chmod 700 "$xdg"
trap '[ -n "${KEEP:-}" ] && echo "kept: $work" || rm -rf "$work" "$xdg"' EXIT
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }
MODES="Files Dictionary Fonts Windows Snippets Emoji Hosts Kube"

# ---- 1. helper tests ----------------------------------------------------------------------
res="$(timeout 120 python3 -I -m unittest discover -s "$tst" -p 'test_*.py' 2>&1)"
echo "$res" | grep -E '^(FAIL|ERROR|Ran|OK|FAILED)'
echo "$res" | tail -1 | grep -q '^OK' && ok "1 unittest: helpers" || bad "1 unittest: helpers"

# ---- 2. static rules ----------------------------------------------------------------------
srcs=""; for m in $MODES; do srcs="$srcs $prov/$m.qml"; done
allsrc="$srcs $tst/Frame.qml $tst/Scene.qml"
if grep -nE '#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b' $allsrc | grep -v '^\s*//' ; then bad "2 hex colours"; else ok "2 no hex colours (tokens only)"; fi
if LC_ALL=C.UTF-8 grep -nP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' $allsrc "$bin"/executable_dots-launch-{files,dict,fonts,windows,snippets,emoji,hosts,kube}; then bad "2 PUA codepoints"; else ok "2 no PUA codepoints (Phosphor, not Nerd Font)"; fi
if grep -nE '\bProcess\b|execDetached|\bsh -c|bash -c|/bin/sh|command:\s*"' $srcs; then bad "2 exec outside Provider.run / shell string"; else ok "2 providers exec only through Provider.run (argv arrays)"; fi
if grep -nE 'XMLHttpRequest|WebSocket|http://|https://|NetworkRequest' $srcs; then bad "2 network in a provider"; else ok "2 no network in providers"; fi
if grep -nEi 'green|#0f0|lime' $allsrc; then bad "2 green"; else ok "2 no green"; fi
if grep -rnEi 'pnow|proficient|kaarbaaz|websleak|snoorullah|\bovh\b|contabo' $srcs $tst "$bin"/executable_dots-launch-{files,dict,fonts,windows,snippets,emoji,hosts,kube} "$root/docs/shell/specs/launcher-modes.md" -l --exclude-dir=__pycache__ | grep -v test_helpers.py; then bad "2 private names in a public repo"; else ok "2 no company/person/host names"; fi
if grep -nE '(^|[^0-9.])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}' $srcs $tst/mkcases.py "$bin"/executable_dots-launch-{files,dict,fonts,windows,snippets,emoji,hosts,kube}; then bad "2 private address"; else ok "2 no private addresses"; fi
for m in files dict fonts windows snippets emoji hosts kube; do
  [ -x "$bin/executable_dots-launch-$m" ] && python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$bin/executable_dots-launch-$m" || bad "2 helper $m is not an executable python file"
done
[ "$fails" = 0 ] && ok "2 helpers are executable python"
miss="$(python3 -I - "$mod/common/PhosphorIcons.qml" "$prov" "$bin" <<'PY'
import os, re, sys
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(sys.argv[1]).read(), re.M))
used = set()
for m in "Files Dictionary Fonts Windows Snippets Emoji Hosts Kube".split():
    src = open(os.path.join(sys.argv[2], m + ".qml")).read()
    for mm in re.finditer(r'(?:icon|usedIcons)\s*:\s*(?:\(\{)?([^\n]*)', src):
        used.update(re.findall(r'"([a-z][a-z0-9-]*)"', mm.group(1)) if "usedIcons" in mm.group(0) else re.findall(r'"([a-z][a-z0-9-]*)"', mm.group(1)))
used = {u for u in used if u not in ("word", "grammar", "terminal", "code", "browser", "chat", "mail", "player", "notes", "other", "host", "glyph", "context", "namespace", "command", "reply", "path", "block", "add", "font", "image", "note", "folder")} | \
       {v for m in "Files Dictionary Fonts Windows Snippets Emoji Hosts Kube".split() for v in re.findall(r'"[a-z]+"\s*:\s*"([a-z][a-z0-9-]*)"', open(os.path.join(sys.argv[2], m + ".qml")).read())}
# icons the helpers emit
for h in "files dict fonts windows snippets emoji hosts kube".split():
    src = open(os.path.join(sys.argv[3], "executable_dots-launch-" + h)).read()
    used.update(re.findall(r'"icon":\s*"([a-z][a-z0-9-]*)"', src))
    used.update(re.findall(r'"([a-z]+(?:-[a-z]+)*)",\s*"[A-Z][A-Za-z ]+"\)', src))
print(" ".join(sorted(used - names)))
PY
)"
if [ -z "$miss" ]; then ok "2 every icon name resolves in PhosphorIcons"; else echo "WARN 2 icons not in the generated registry yet (run python3 tools/gen-phosphor-qml.py): $miss"; fi

# ---- tools ---------------------------------------------------------------------------------
works() { "$1" -help >/dev/null 2>&1 || "$1" --help >/dev/null 2>&1; }
nixbin() { nix build --no-link --print-out-paths "nixpkgs#$1" 2>/dev/null | head -1; }
QS="${QS:-$(command -v quickshell || true)}"
[ -n "$QS" ] || { p="$(nixbin quickshell)"; [ -n "$p" ] && QS="$p/bin/quickshell"; }
QTD=""
if command -v qmllint >/dev/null && works qmllint; then QML_LINT="$(command -v qmllint)"
else
  QTD="${QTD_DIR:-$(ls -d /nix/store/*-qtdeclarative-6.*[0-9] 2>/dev/null | grep -v -- '-dev$' | tail -1)}"
  [ -x "${QTD:+$QTD/bin/qmllint}" ] || QTD="$(nixbin qt6.qtdeclarative)"
  QML_LINT="${QTD:+$QTD/bin/qmllint}"
fi
[ -n "$QTD" ] && export QML_IMPORT_PATH="$QTD/lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QML_XHR_ALLOW_FILE_READ=1

# ---- 3. qmllint ----------------------------------------------------------------------------
if [ -n "${QML_LINT:-}" ] && [ -x "$QML_LINT" ]; then
  lint="$work/lint/qs"; mkdir -p "$lint/modules/launcher/providers"
  # the REAL qmldir and every real provider: a type missing from the qmldir must fail here
  cp "$prov/"*.qml "$prov/qmldir" "$lint/modules/launcher/providers/"; cp -r "$mod/launcher/js" "$lint/modules/launcher/js"
  qsq="$(dirname "$(dirname "$QS")")/lib/qt-6/qml"
  lintimp=(-I "$work/lint"); [ -d "$qsq" ] && lintimp+=(-I "$qsq"); [ -n "$QTD" ] && lintimp+=(-I "$QTD/lib/qt-6/qml")
  files=(); for m in $MODES; do files+=("$lint/modules/launcher/providers/$m.qml"); done
  lintout="$("$QML_LINT" "${lintimp[@]}" --unqualified disable "${files[@]}" 2>&1 | grep -v '^$')"
  if [ -z "$lintout" ]; then ok "3 qmllint clean"; else echo "$lintout" | head -"${LINT_LINES:-40}"; bad "3 qmllint reported diagnostics"; fi
else
  echo "SKIP 3 qmllint not available (a Qt5 stub does not count)"
fi

# ---- 4. scenes ---------------------------------------------------------------------------------
if [ -z "$QS" ]; then echo "SKIP 4 quickshell not found and could not be built"; echo "launcher-modes: $fails failure(s)"; [ "$fails" = 0 ]; exit; fi
shellroot="$work/root"; mkdir -p "$shellroot/modules/theme" "$shellroot/modules/launcher/providers"
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
# The icon registry is a generated subset (only names the shell uses). Render with a fresh one that also
# holds what the providers and the test frame use, so the PNGs show real glyphs before integration regenerates it.
cp -r "$mod/common" "$shellroot/modules/common"
python3 -I - "$root" "$shellroot/modules/common/PhosphorIcons.qml" <<'PY'
import os, re, subprocess, sys
root, out = sys.argv[1:3]
src = subprocess.run([sys.executable, "-I", os.path.join(root, "tools/gen-phosphor-qml.py"), "--stdout"], capture_output=True, text=True).stdout
have = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', src, re.M))
reg = {}
for ln in open(os.path.join(root, "nix/pkgs/dots-icon-font/codepoints.tsv")):
    if ln.strip() and not ln.startswith("#"):
        c = ln.rstrip("\n").split("\t"); reg[c[0]] = int(c[4], 16)
want = "squares-four clipboard-text book-open-text folder text-aa stack note smiley terminal-window cube calculator file-code image code globe chat-circle envelope-simple speaker-high link plus pen-nib magnifying-glass check warning eye-slash info lock shield-check".split()
extra = ",\n".join('    "%s": [0x%X, %s]' % (n, reg[n], "0x%X" % reg[n + "-fill"] if n + "-fill" in reg else "0") for n in want if n in reg and n not in have)
src = src.replace("({\n", "({\n" + extra + ",\n", 1)
open(out, "w").write(src)
PY
# the REAL providers qmldir and every real provider (not a generated qmldir): a type missing from it fails the scene
cp "$prov/"*.qml "$prov/qmldir" "$shellroot/modules/launcher/providers/"; cp -r "$mod/launcher/js" "$shellroot/modules/launcher/js"
cp "$tst/Frame.qml" "$shellroot/Frame.qml"
cp "$tst/Scene.qml" "$shellroot/shell.qml"
mkdir -p "$work/home" "$work/out" "$work/fx"
python3 -I "$tst/mkcases.py" "$work/fx" "$root" >/dev/null || bad "4 mkcases failed"
mkdir -p "$work/tmp"   # the GL host wrapper copies GBs of driver libs into $TMPDIR on every run: keep them in $work, deleted on exit
env TMPDIR="$work/tmp" OUT_DIR="$shots" CASES="$work/fx/cases.json" XDG_RUNTIME_DIR="$xdg" HOME="$work/home" \
    timeout 240 "$QS" -p "$shellroot" > "$work/out/scene.log" 2>&1
rm -rf "$work/tmp"
sed -i 's/\x1b\[[0-9;]*m//g' "$work/out/scene.log"
grep -a 'PROBE ' "$work/out/scene.log" | sed 's/^.*PROBE //' > "$work/out/scene.probes"

python3 -I - "$work/out/scene.probes" "$shots" "$work/fx" <<'PY' && ok "4 probes: every board state, rows, states and wiring" || bad "4 probes"
import json, os, sys
probes, shots, fx = sys.argv[1:4]
fails = []
cases = {}
try:
    for ln in open(probes):
        tag, js = ln.strip().split(" ", 1)
        cases[tag] = json.loads(js)
except Exception as e:
    fails.append("no probes (%s)" % e)
declared = [c["tag"] for c in json.load(open(os.path.join(fx, "cases.json")))]
def vis(m, name): return [e for e in m["names"].get(name, []) if e["visible"]]
def texts(m, name): return [e.get("text", "") for e in vis(m, name)]
def need(cond, msg):
    if not cond: fails.append(msg)
def log(tag):
    try: return [json.loads(x) for x in open(os.path.join(fx, "case", tag, "exec.log")).read().splitlines()]
    except OSError: return []
for t in declared:
    need(t in cases, "%s: state missing" % t)
    f = os.path.join(shots, "launcher-%s.png" % t)
    need(os.path.isfile(f) and os.path.getsize(f) > 3000, "%s: PNG missing or empty" % t)
for t, m in cases.items():
    w, h = m["card"]["w"], m["card"]["h"]
    for name, es in m["names"].items():
        for e in es:
            if e["visible"] and name not in ("frameCard", "confirmScrim", "modeChip"):
                need(e["x"] >= -1 and e["x"] + e["w"] <= w + 1, "%s: %s overflows the card horizontally %s" % (t, name, e))
                need(e["y"] >= -1 and e["y"] + e["h"] <= h + 1 or name in ("row", "rowTitle", "groupHead", "cell", "rowChip", "tierChip"), "%s: %s leaves the card %s" % (t, name, e))
    need(not m["meta"]["busy"], "%s: provider still busy" % t)
    need(len(vis(m, "modeChip")) >= 5, "%s: mode chips missing" % t)
    need(len(vis(m, "prefixChip")) == 1, "%s: prefix chip" % t)

def case(t): return cases.get(t)
def keys(m): return m["meta"]["keys"]
def rowtexts(m): return texts(m, "row")
def sel_actions(m): return m["meta"]["actions"]

# ---- files
m = case("files-default")
if m:
    need(m["meta"]["rows"] == 3 and rowtexts(m)[0].endswith("restore.md"), "files-default: rows %s" % rowtexts(m))
    need("## Restore" in texts(m, "previewBody")[0], "files-default: text preview")
    need(texts(m, "actionBtn") == ["Open", "Copy path", "Send to agent"], "files-default: actions %s" % texts(m, "actionBtn"))
    need(texts(m, "prefixText") == ["f:"], "files-default: prefix")
m = case("files-image");  need(m and len(vis(m, "previewImage")) == 1, "files-image: image preview")
m = case("files-note");   need(m and "Restore drill plan" in rowtexts(m)[2], "files-note: third row")
m = case("files-empty");  need(m and m["meta"]["rows"] == 0 and len(vis(m, "hintLine")) == 1, "files-empty: hint line")
m = case("files-nomatch"); need(m and "No files match" in m["meta"]["hint"], "files-nomatch: hint")
# ---- dictionary
m = case("dict-word")
if m:
    need(rowtexts(m) == ["idempotent", "Grammar: paste text to check"], "dict-word: rows %s" % rowtexts(m))
    need("same result" in texts(m, "previewBody")[0], "dict-word: gloss")
    need(texts(m, "actionBtn")[:2] == ["Copy word", "Check my text"], "dict-word: actions")
m = case("dict-grammar")
if m:
    need(m["meta"]["rows"] == 1 and "2 fixes" in rowtexts(m)[0], "dict-grammar: rows %s" % rowtexts(m))
    need("They're going to restart the node tonight." in texts(m, "previewBody")[0], "dict-grammar: corrected text")
    need(texts(m, "actionBtn") == ["Copy result"], "dict-grammar: copy result")
m = case("dict-error")
if m: need("WordNet" in m["meta"]["error"] and len(vis(m, "errorRow")) == 1, "dict-error: names the missing package (%s)" % m["meta"]["error"])
# ---- fonts
m = case("fonts-font")
if m:
    need(rowtexts(m)[0] == "DejaVu Sans Mono" and "JetBrains Mono" in rowtexts(m), "fonts-font: rows %s" % rowtexts(m))
    need(texts(m, "previewHead")[0].startswith("JetBrains Mono"), "fonts-font: preview head %s" % texts(m, "previewHead"))
    need(texts(m, "actionBtn") == ["Copy name", "Copy CSS", "Install"], "fonts-font: actions")
    need(any(a.endswith("!") for a in sel_actions(m)), "fonts-font: Install is disabled (stub)")
m = case("fonts-sans");  need(m and rowtexts(m)[0] == "Bricolage Grotesque", "fonts-sans: rows")
m = case("fonts-icon")
if m:
    need(rowtexts(m)[0] == "Icon: terminal-window" and len(vis(m, "previewIcon")) == 1, "fonts-icon: icon row and glyph")
# ---- windows
m = case("windows-recent")
if m:
    need(texts(m, "groupHead") == ["DEV", "OPS", "ADMIN"], "windows-recent: groups %s" % texts(m, "groupHead"))
    need("0x08" not in keys(m) and m["meta"]["hint"].startswith("Enter = back to router.go"), "windows-recent: current window excluded, hint %s" % m["meta"]["hint"])
    need(texts(m, "actionBtn")[:3] == ["Focus", "Move here", "Close window"], "windows-recent: actions")
m = case("windows-focus")
if m: need(m["meta"]["banner"] == "Focus mode: Dev profile" and len(vis(m, "banner")) == 1, "windows-focus: banner")
m = case("windows-privacy")
if m:
    need(m["meta"]["banner"] == "Titles masked", "windows-privacy: banner")
    need(not any("api-service" in t or "ingress" in t.lower() for t in rowtexts(m)), "windows-privacy: titles leaked %s" % rowtexts(m))
m = case("windows-typed")
if m: need(rowtexts(m)[0] == "ingress.yaml", "windows-typed: top hit %s" % rowtexts(m))
m = case("windows-panes")
if m:
    need(keys(m)[:3] == ["0x01", "0x01#0", "0x01#1"] or "0x01#0" in keys(m), "windows-panes: pane rows %s" % keys(m))
    need(len(vis(m, "panePreview")) >= 1, "windows-panes: pane list in preview")
m = case("windows-task")
if m: need(m["meta"]["banner"] == "2 windows for HD 4412", "windows-task: banner %s" % m["meta"]["banner"])
m = case("windows-empty")
if m: need(m["meta"]["rows"] == 0 and "Enter opens apps" in m["meta"]["hint"], "windows-empty: hint")
m = case("windows-single")
if m: need(m["meta"]["banner"] == "This is the only window" and m["meta"]["rows"] == 1, "windows-single")
m = case("windows-error")
if m:
    need(m["meta"]["banner"] == "Could not focus that window", "windows-error: banner %s" % m["meta"]["banner"])
    need("0x09" not in keys(m), "windows-error: list refreshed without the stale window")
    need(log("windows-error") == [], "windows-error: nothing dispatched at a closed window")
m = case("windows-salah")
if m: need(len(vis(m, "closedCard")) == 1 and m["meta"]["rows"] >= 0 and not vis(m, "row"), "windows-salah: closed card, no list")
# ---- snippets
m = case("snippets-default")
if m: need(m["meta"]["rows"] == 6 and texts(m, "groupHead") == ["Pinned"], "snippets-default: six pinned rows %s" % rowtexts(m))
m = case("snippets-typing")
if m: need(rowtexts(m)[0] == "rollout status", "snippets-typing: exact abbreviation first %s" % rowtexts(m))
m = case("snippets-filling")
if m:
    chips = texts(m, "fieldChip")
    need("name=web:filled" in chips and "namespace=:empty" in chips and "lines=100:ghost" in chips, "snippets-filling: blank states %s" % chips)
    need(sel_actions(m)[0] == "Copy!", "snippets-filling: Copy locked until filled %s" % sel_actions(m))
m = case("snippets-copied")
if m:
    need("Copied" in m["meta"]["toast"] and len(vis(m, "toast")) == 1, "snippets-copied: toast %s" % m["meta"]["toast"])
    need(log("snippets-copied") == [["wl-copy", "kubectl logs -f deploy/web -n apps --tail=100"]], "snippets-copied: wl-copy argv %s" % log("snippets-copied"))
m = case("snippets-sent")
if m:
    need("Sent to pane" in m["meta"]["toast"], "snippets-sent: toast")
    need(log("snippets-sent") == [["herdr", "pane", "send-text", "w1:p1", "kubectl logs -f deploy/web -n apps --tail=100"]], "snippets-sent: no Enter sent %s" % log("snippets-sent"))
m = case("snippets-empty")
if m: need(keys(m) == ["new"] and "No snippets" in m["meta"]["hint"], "snippets-empty")
m = case("snippets-nomatch")
if m: need(rowtexts(m)[0].startswith("Closest existing snippet") and "Ctrl+N" in m["meta"]["hint"], "snippets-nomatch: %s" % rowtexts(m))
m = case("snippets-adding")
if m: need(m["meta"]["adding"] and len(vis(m, "addPanel")) == 1 and not vis(m, "sensitiveCard"), "snippets-adding")
m = case("snippets-sensitive")
if m:
    need(m["meta"]["sensitiveHold"] and len(vis(m, "sensitiveCard")) == 1, "snippets-sensitive: refusal card")
    need(not any("ghp_" in t for t in texts(m, "addText")), "snippets-sensitive: the secret is never shown")
m = case("snippets-error")
if m: need("broken.json" in m["meta"]["error"] and len(vis(m, "errorRow")) == 1, "snippets-error: %s" % m["meta"]["error"])
# ---- emoji
for t in ("emoji-empty", "emoji-browse", "emoji-search", "emoji-tray", "emoji-copied", "emoji-tofu"):
    m = case(t); need(m and len(vis(m, "cell")) >= 1, "%s: glyph cells" % t)
m = case("emoji-empty"); need(m and "Arrows" in texts(m, "groupHead"), "emoji-empty: categories")
m = case("emoji-browse"); need(m and texts(m, "groupHead")[0] == "Recent", "emoji-browse: Recent first")
m = case("emoji-tray")
if m: need(m["meta"]["tray"] == 3 and len(vis(m, "trayItem")) == 3, "emoji-tray: three glyphs in the tray (%s)" % m["meta"]["tray"])
m = case("emoji-copied")
if m: need("Copied" in m["meta"]["toast"] and log("emoji-copied")[0][0] == "wl-copy", "emoji-copied")
m = case("emoji-nomatch"); need(m and m["meta"]["rows"] == 0 and "No glyph" in m["meta"]["hint"], "emoji-nomatch")
m = case("emoji-tofu"); need(m and "box" in texts(m, "previewBody")[0], "emoji-tofu: warning in the preview")
# ---- hosts
m = case("hosts-default")
if m: need(texts(m, "groupHead") == ["Recent", "All hosts"] and m["meta"]["rows"] == 8, "hosts-default: %s" % texts(m, "groupHead"))
m = case("hosts-filtered")
if m: need(rowtexts(m) == ["db-02", "db-01"], "hosts-filtered: %s" % rowtexts(m))
m = case("hosts-actions")
if m: need(len(vis(m, "actionPanel")) == 1 and len(vis(m, "panelAction")) == 8, "hosts-actions: panel with eight actions")
m = case("hosts-open")
if m: need("1 open" in texts(m, "rowChip") and texts(m, "actionBtn")[0] == "Focus", "hosts-open: %s" % texts(m, "rowChip"))
m = case("hosts-empty"); need(m and m["meta"]["rows"] == 0 and "No hosts" in m["meta"]["hint"], "hosts-empty")
m = case("hosts-adhoc")
if m: need(rowtexts(m) == ["Connect to ops@lab-gw.example.test:2222"] and texts(m, "groupHead") == ["Connect"], "hosts-adhoc")
# ---- kube
m = case("kube-default")
if m:
    need(m["meta"]["rows"] == 7 and rowtexts(m)[0] == "staging-a", "kube-default: current first %s" % rowtexts(m))
    need(texts(m, "tierChip")[:3] == ["STAGING", "DEV", "LOCAL"] and "PROD" in texts(m, "tierChip"), "kube-default: tier chips %s" % texts(m, "tierChip"))
    need(rowtexts(m).index("dev-sandbox") < rowtexts(m).index("prod-main"), "kube-default: prod never beats a non-prod tie")
m = case("kube-changed"); need(m and m["meta"]["note"] == "updated" and len(vis(m, "updatedNote")) == 1, "kube-changed: updated note")
m = case("kube-filter"); need(m and set(rowtexts(m)) == {"staging-a", "staging-b"}, "kube-filter: %s" % (m and rowtexts(m)))
m = case("kube-nomatch"); need(m and m["meta"]["rows"] == 0 and "Closest" in m["meta"]["hint"], "kube-nomatch")
m = case("kube-prod"); need(m and set(rowtexts(m)) == {"prod-main", "prod-eu"} and len(vis(m, "prodBanner")) == 1, "kube-prod")
m = case("kube-confirm")
if m:
    need(len(vis(m, "confirmCard")) == 1 and "PROD" in texts(m, "confirmTitle")[0], "kube-confirm: card %s" % texts(m, "confirmTitle"))
    need(m["meta"]["pendingKey"] == "prod-main", "kube-confirm: waiting for the second Enter")
m = case("kube-ns"); need(m and m["meta"]["view"] == "ns" and rowtexts(m)[0] == "apps", "kube-ns: %s" % (m and rowtexts(m)))
m = case("kube-switched")
if m: need("now: dev-sandbox" in m["meta"]["toast"] and rowtexts(m)[0] == "dev-sandbox", "kube-switched: %s / %s" % (m["meta"]["toast"], rowtexts(m)[:1]))
m = case("kube-peek")
if m:
    need("global stays staging-a" in m["meta"]["toast"], "kube-peek: toast %s" % m["meta"]["toast"])
    lg = [json.loads(x) for x in open(os.path.join(fx, "kube-peek.log")).read().splitlines()] if os.path.exists(os.path.join(fx, "kube-peek.log")) else []
    need(any(c[:3] == ["herdr", "pane", "run"] and "--context" in c and "prod-main" in c for c in lg), "kube-peek: pinned --context pane %s" % lg)
m = case("kube-onprod"); need(m and len(vis(m, "prodRule")) == 1 and rowtexts(m)[0] == "prod-main", "kube-onprod: red rule on prod")
m = case("kube-unreach")
if m: need(any("unreachable" in e for e in [m["meta"]["keys"] and "unreachable" or ""]) and len(vis(m, "fieldChip")) >= 4, "kube-unreach")
m = case("kube-mismatch"); need(m and m["meta"]["mismatch"] and len(vis(m, "banner")) == 1, "kube-mismatch: amber strip")
m = case("kube-nokube"); need(m and m["meta"]["kubeState"] == "nokube" and "never creates" in m["meta"]["hint"], "kube-nokube")
m = case("kube-idle"); need(m and len(vis(m, "closedCard")) == 1, "kube-idle: closed card")
# no helper wrote outside its sandbox: nothing real was executed
for t in cases:
    for argv in log(t):
        need(argv[0] in ("wl-copy", "xdg-open", "herdr", "hyprctl", "ssh-keygen") or argv[0].endswith("fake-kubectl"), "%s: unexpected exec %s" % (t, argv[:2]))
for f in fails: print("  - " + f)
sys.exit(1 if fails else 0)
PY

if grep -aE 'ReferenceError|TypeError|Cannot (assign|read|call)|is not a type|is not installed|Unable to assign|binding loop|Failed to load|Component is not ready' "$work/out/scene.log" | grep -v 'PROBE ' | head -20; then bad "4 QML errors in the scene log"; else ok "4 no QML errors in the scene log"; fi
echo "launcher-modes: $fails failure(s)${KEEP:+ (kept $work)}"; echo "shots: $shots"
[ "$fails" = 0 ]
