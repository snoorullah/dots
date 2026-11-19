#!/usr/bin/env bash
# dots-theme: both producers emit a schema-valid tokens.json with the SAME key set,
# every derived tone matches an independent derivation, and emit writes its consumers.
# Offline: matugen is a stub on PATH, nothing here touches the real ~/.local/state.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
out="$(mktemp -d)"; trap 'rm -rf "$out"' EXIT
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out" || { echo "FAIL: render"; exit 1; }
bin="$out/.local/bin/dots-theme"
[ -x "$bin" ] || { echo "FAIL: dots-theme not rendered executable"; exit 1; }

# no matugen template may take its accent from the wallpaper primary (token contract: accent is FIXED)
acc="$(sed -n 's/^[[:space:]]*accent:[[:space:]]*"\{0,1\}#\{0,1\}\([0-9a-fA-F]\{6\}\)".*/\1/p' "$root/home/.chezmoidata/palette.yaml" 2>/dev/null | head -1)"
[ -n "$acc" ] || { echo "FAIL: palette.yaml has no parseable accent key"; exit 1; }
if grep -rniE 'accent.*colors\.(primary|tertiary|secondary)' "$root/home/private_dot_config/matugen/templates"; then
  echo "FAIL: a matugen template derives its accent from the wallpaper"; exit 1
fi
grep -qi "$acc" "$root/home/private_dot_config/matugen/templates/hyprlock.conf" || { echo "FAIL: hyprlock matugen template does not pin accent $acc"; exit 1; }

# a stub matugen printing the shape matugen 4.x gives for `image --json hex`
# (checked against the real binary: colors.<role>.dark.color)
stub="$out/stub"; mkdir -p "$stub"
cat > "$stub/matugen-good.json" <<'JSON'
{"colors":{
"background":{"dark":{"color":"#10141a"},"default":{"color":"#10141a"},"light":{"color":"#f9f9ff"}},
"surface":{"dark":{"color":"#10141a"}},
"surface_dim":{"dark":{"color":"#10141a"}},
"surface_container":{"dark":{"color":"#1c2026"}},
"surface_container_high":{"dark":{"color":"#262a31"}},
"outline":{"dark":{"color":"#8a919e"}},
"outline_variant":{"dark":{"color":"#414751"}},
"on_surface":{"dark":{"color":"#dfe2eb"}},
"on_surface_variant":{"dark":{"color":"#c0c7d4"}},
"primary":{"dark":{"color":"#a2c9ff"}},
"on_primary":{"dark":{"color":"#00315b"}}}}
JSON
# a light scheme: the fixed status colours genuinely cannot be read on it, so it must be refused
cat > "$stub/matugen-light.json" <<'JSON'
{"colors":{
"background":{"dark":{"color":"#e9edf5"}},
"surface":{"dark":{"color":"#e9edf5"}},
"surface_dim":{"dark":{"color":"#d9dde5"}},
"surface_container":{"dark":{"color":"#eef1f9"}},
"surface_container_high":{"dark":{"color":"#e3e7ef"}},
"outline":{"dark":{"color":"#6f7580"}},
"outline_variant":{"dark":{"color":"#c0c7d4"}},
"on_surface":{"dark":{"color":"#181c22"}},
"on_surface_variant":{"dark":{"color":"#414751"}},
"primary":{"dark":{"color":"#2a5a99"}},
"on_primary":{"dark":{"color":"#ffffff"}}}}
JSON
cat > "$stub/matugen" <<'EOF'
#!/bin/sh
cat "${MATUGEN_FIXTURE:-$(dirname "$0")/matugen-good.json}"
EOF
chmod +x "$stub/matugen"
# no live wallpaper daemon may answer during the test
for x in swww hyprctl; do printf '#!/bin/sh\nexit 1\n' > "$stub/$x"; chmod +x "$stub/$x"; done
# gsettings records what it is asked to set
cat > "$stub/gsettings" <<'EOF'
#!/bin/sh
echo "$@" >> "$GSETTINGS_LOG"
EOF
chmod +x "$stub/gsettings"
# a gowall stand-in only when the real one is not on PATH (it just copies)
if ! command -v gowall >/dev/null; then
  cat > "$stub/gowall" <<'EOF'
#!/bin/sh
files=""; outd=""
while [ $# -gt 0 ]; do case "$1" in --batch) files="$2"; shift;; --output) outd="$2"; shift;; esac; shift; done
mkdir -p "$outd"; echo "$files" | tr ',' '\n' | while read -r f; do cp "$f" "$outd/"; done
EOF
  chmod +x "$stub/gowall"
fi
export GSETTINGS_LOG="$out/gsettings.log"

# a tiny icon theme: one coloured svg, one symlink, one png
src="$out/icons-src/Fixture"; mkdir -p "$src/scalable/apps" "$src/16x16/apps"
printf '[Icon Theme]\nName=Fixture\nDirectories=scalable/apps,16x16/apps\n' > "$src/index.theme"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><defs><linearGradient id="a12"/></defs><rect fill="url(#a12)" width="16" height="16"/><circle fill="#e44444" stroke="#fff" r="4"/></svg>\n' > "$src/scalable/apps/red.svg"
ln -s red.svg "$src/scalable/apps/alias.svg"
python3 - "$src" <<'PY2'
import zlib, struct, sys
def ch(t, d):
    x = struct.pack('>I', len(d)) + t + d
    return x + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
raw = b''.join(b'\x00' + bytes((228, 68, 68)) * 16 for _ in range(16))
open(sys.argv[1] + '/16x16/apps/p.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))
PY2
export DOTS_ICON_SRC="$src" DOTS_ICONS_DIR="$out/icons-out/dots-themed"
: > "$out/wall.png"

real_matugen="$(command -v matugen || true)"
export HOME="$out" XDG_STATE_HOME="$out/state" XDG_CONFIG_HOME="$out/cfgout"
export PATH="$stub:$PATH"
mkdir -p "$XDG_CONFIG_HOME"

python3 - "$root" "$bin" "$out" <<'PY'
import json, os, re, subprocess, sys
root, bin_, out = sys.argv[1:4]
import jsonschema
schema = json.load(open(f"{root}/docs/contracts/tokens.schema.json"))
tok = f"{out}/state/dots-theme/tokens.json"
fails = []
def check(name, ok, extra=""):
    if not ok: fails.append(f"{name} {extra}".strip())

def run(*a):
    r = subprocess.run([bin_, *a], capture_output=True, text=True)
    check(f"dots-theme {' '.join(a)} exit 0", r.returncode == 0, r.stderr.strip())
    return r

def keys(d, p=""):
    for k, v in d.items():
        if isinstance(v, dict): yield from keys(v, f"{p}{k}.")
        else: yield p + k

# palette, parsed independently of the template
pal = {}
for line in open(f"{root}/home/.chezmoidata/palette.yaml"):
    m = re.match(r'^  (ground|panel|raised|line|border|text|text_dim|accent|accent_fg|waiting|failed|unknown): "(#[0-9a-f]{6})"', line)
    if m: pal[m.group(1)] = m.group(2)
    elif re.match(r'^  [a-z_]+:\s*$', line): break
check("palette parsed", len(pal) == 12)

# hex binding: the lock screen and the matugen templates carry no palette value that
# palette.yaml does not define, and the pinned accent IS palette.accent
pal_hex = {v.lstrip("#") for v in pal.values()}
lock = open(f"{out}/.config/hypr/hyprlock.conf").read()
lock_hex = set(re.findall(r'rgb\(([0-9a-fA-F]{6})\)', lock)) | set(re.findall(r'##([0-9a-fA-F]{6})', lock))
check("hyprlock.conf uses only palette.yaml colours", bool(lock_hex) and lock_hex <= pal_hex, str(lock_hex - pal_hex))
check("hyprlock.conf has no unrendered template", "{{" not in lock)
for t in ("hyprlock.conf", "hyprland.conf", "swaync.css"):
    tx = open(f"{root}/home/private_dot_config/matugen/templates/{t}").read()
    lits = set(h.lower() for h in re.findall(r'(?:rgb\(|#)([0-9a-fA-F]{6})\b', tx))
    bad = lits - {pal["accent"].lstrip("#")}
    check(f"matugen {t}: hex literals are only palette.accent", not bad, str(bad))

def rgb(h): return [int(h[i:i+2], 16) for i in (1, 3, 5)]
def hx(c): return "#" + "".join(f"{round(v):02x}" for v in c)
def mix(a, b, t): return hx([x + (y - x) * t for x, y in zip(rgb(a), rgb(b))])

run("preset")
preset = json.load(open(tok))
jsonschema.validate(preset, schema)
c = preset["color"]
check("source preset", preset["source"] == "preset" and preset["wallpaper"] is None)
want = {
    "bg": pal["ground"], "surface": pal["panel"], "surfaceDim": mix(pal["ground"], "#000000", .20),
    "surfaceContainer": pal["raised"], "surfaceContainerHigh": mix(pal["raised"], "#ffffff", .06),
    "outline": pal["border"], "outlineVariant": pal["line"],
    "fg": pal["text"], "fgDim": pal["text_dim"], "fgFaint": mix(pal["ground"], pal["text_dim"], .70),
    "accent": pal["accent"], "accentFg": pal["accent_fg"],
    "waiting": pal["waiting"], "failed": pal["failed"], "unknown": pal["unknown"],
}
for k, v in want.items(): check(f"preset derivation {k}", c[k] == v, f"got {c[k]} want {v}")

# determinism: a second run is byte-identical
a = open(tok).read(); run("preset"); check("preset is deterministic", open(tok).read() == a)

run("wallpaper", f"{out}/wall.png")
wall = json.load(open(tok))
jsonschema.validate(wall, schema)
check("source wallpaper", wall["source"] == "wallpaper" and wall["wallpaper"] == f"{out}/wall.png")
check("same key set in both modes", sorted(keys(preset)) == sorted(keys(wall)))
check("wallpaper accent is the fixed palette accent, not matugen primary", wall["color"]["accent"] == preset["color"]["accent"] == pal["accent"])
check("wallpaper accentFg is fixed", wall["color"]["accentFg"] == pal["accent_fg"])
for k in ("waiting", "failed", "unknown"):
    check(f"status colour {k} stays semantic in wallpaper mode", wall["color"][k] == preset["color"][k])

# a wallpaper that matugen cannot map must fail loudly and leave tokens.json intact
before = open(tok).read()
r = subprocess.run([bin_, "wallpaper", f"{out}/missing.png"], capture_output=True, text=True)
check("missing wallpaper exits non-zero", r.returncode != 0)
check("failed run leaves tokens.json intact", open(tok).read() == before)

# new interaction tokens exist in both producers; panel radius is unified with card
for t_ in (preset, wall):
    check("alpha.pressed/rest/on present", all(k in t_["alpha"] for k in ("pressed", "rest", "on")))
    check("radius.panel == radius.card == 14", t_["radius"]["panel"] == 14 == t_["radius"]["card"])
    check("space on the 4 px grid", all(v % 4 == 0 for v in t_["space"].values()), str(t_["space"]))
    check("radius chip/row/card 6/10/14", (t_["radius"]["chip"], t_["radius"]["row"], t_["radius"]["card"]) == (6, 10, 14))
    check("slide <= 180 (slow 180), fade 240", t_["motion"]["slow"] == 180 and t_["motion"]["fade"] == 240, str(t_["motion"]))
    check("type scale: page 28/36 w600, display 40/48 w500", (t_["font"]["size"]["page"], t_["font"]["line"]["page"], t_["font"]["weight"]["page"], t_["font"]["size"]["display"], t_["font"]["line"]["display"], t_["font"]["weight"]["display"]) == (28, 36, 600, 40, 48, 500))
    check("fonts: Bricolage + plain JetBrains Mono", t_["font"]["sans"] == "Bricolage Grotesque" and t_["font"]["mono"] == "JetBrains Mono")
    check("no green in the colour set", not any(k in t_["color"] for k in ("green", "amber", "red", "purple", "pink", "cyan", "yellow")))

# default (no args) is wallpaper mode when a wallpaper is known, preset otherwise
os.makedirs(f"{out}/.cache", exist_ok=True)
open(f"{out}/.cache/current-wallpaper", "w").write(f"{out}/wall.png")
run()
auto = json.load(open(tok)); jsonschema.validate(auto, schema)
check("default is wallpaper mode", auto["source"] == "wallpaper" and auto["color"]["accent"] == pal["accent"])
check("default keeps the key set", sorted(keys(auto)) == sorted(keys(preset)))
os.remove(f"{out}/.cache/current-wallpaper")
r = run()
auto = json.load(open(tok))
check("no wallpaper -> preset fallback", auto["source"] == "preset" and auto["color"]["accent"] == pal["accent"])
check("fallback says so", "using the preset" in r.stderr, r.stderr)
open(f"{out}/.cache/current-wallpaper", "w").write(f"{out}/wall.png")
env_nomatugen = dict(os.environ, PATH=os.path.dirname(subprocess.check_output(["which", "python3"], text=True).strip()) + ":/usr/bin:/bin")
env_nomatugen["PATH"] = ":".join(d for d in env_nomatugen["PATH"].split(":") if not os.path.exists(d + "/matugen"))
r = subprocess.run([bin_], capture_output=True, text=True, env=env_nomatugen)
check("matugen missing -> exit 0 + preset", r.returncode == 0 and json.load(open(tok))["source"] == "preset", r.stderr)

# icons: built from the current palette, cached by hash, GTK setting only with --apply
idir = f"{out}/icons-out/dots-themed"
import shutil; shutil.rmtree(f"{out}/icons-out", ignore_errors=True)
run("wallpaper", f"{out}/wall.png", "--no-icons")
check("--no-icons builds nothing", not os.path.isdir(idir))
r = run("icons")
svg = open(f"{idir}/scalable/apps/red.svg").read()
check("icons: original red is gone", "#e44444" not in svg, svg)
check("icons: url(#id) and id untouched", "url(#a12)" in svg and 'id="a12"' in svg, svg)
check("icons: symlink preserved", os.path.islink(f"{idir}/scalable/apps/alias.svg"))
check("icons: png carried", os.path.isfile(f"{idir}/16x16/apps/p.png"))
idx = open(f"{idir}/index.theme").read()
check("icons: index.theme renamed + inherits", "Name=dots-themed" in idx and "Inherits=Fixture,hicolor" in idx, idx)
check("icons: no gsettings call without --apply", not os.path.exists(f"{out}/gsettings.log"))
m1 = os.stat(f"{idir}/scalable/apps/red.svg").st_mtime_ns
r = run("icons")
check("icons: second run is a no-op", "up to date" in r.stdout and os.stat(f"{idir}/scalable/apps/red.svg").st_mtime_ns == m1, r.stdout)
r = run("icons", "--apply")
check("icons: --apply sets the GTK icon theme",
      "set org.gnome.desktop.interface icon-theme dots-themed" in open(f"{out}/gsettings.log").read())
run("preset")
r = run("icons")
check("icons: palette change regenerates", "wrote" in r.stdout, r.stdout)
svg2 = open(f"{idir}/scalable/apps/red.svg").read()
check("icons: output follows the palette", svg2 != svg)
run("wallpaper", f"{out}/wall.png")
check("wallpaper regenerates icons by default", open(f"{idir}/scalable/apps/red.svg").read() != svg2)

# ── contrast gate: judge what renders, with thresholds fit to use ──────────
import shutil
def lum(h):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
def cr(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
SURF = ("bg", "surface", "surfaceDim", "surfaceContainer", "surfaceContainerHigh")
MARKS = ("waiting", "failed", "unknown", "accent")
worst = "#a0a0a0"
run("wallpaper", f"{out}/wall.png", "--no-icons")
wall = json.load(open(tok))
marks_min = min(cr(wall["color"][k], mix(worst, wall["color"][s], .78)) for s in SURF for k in MARKS)
text_min = min(cr(wall["color"][k], wall["color"][s]) for s in SURF for k in MARKS)
check("realistic matugen fixture passes with margin (marks >= 3.3:1 on composited surfaces)", marks_min >= 3.3, f"{marks_min:.2f}")
check("fixture status colours read as text on opaque surfaces (>= 4.5:1)", text_min >= 4.5, f"{text_min:.2f}")
print(f"gate margins: marks {marks_min:.2f}:1 (need 3.0) text {text_min:.2f}:1 (need 4.5)")

lightfx = f"{out}/stub/matugen-light.json"
before = open(tok).read()
env_light = dict(os.environ, MATUGEN_FIXTURE=lightfx)
r = subprocess.run([bin_, "wallpaper", f"{out}/wall.png", "--no-icons"], capture_output=True, text=True, env=env_light)
check("unreadable light scheme is refused", r.returncode != 0 and ("3:1" in r.stderr or "4.5:1" in r.stderr), r.stderr)
check("refused scheme leaves tokens.json intact", open(tok).read() == before)
open(f"{out}/.cache/current-wallpaper", "w").write(f"{out}/wall.png")
r = subprocess.run([bin_, "auto", "--no-icons"], capture_output=True, text=True, env=env_light)
check("auto falls back to the preset on a refused scheme", r.returncode == 0 and json.load(open(tok))["source"] == "preset" and "using the preset" in r.stderr, r.stderr)
os.remove(f"{out}/.cache/current-wallpaper")

# schema, generator, Tokens.qml and the overview stub agree on motion
bad = json.loads(json.dumps(preset)); bad["motion"]["slow"] = 200
try:
    jsonschema.validate(bad, schema); check("schema rejects slide > 180", False)
except jsonschema.ValidationError:
    pass
qml = "home/private_dot_config/quickshell/dots/modules"
def qml_group(txt, name):
    """Parse the `name: { ... }` object literal (nested ok) into a dict, or None."""
    m = re.search(r"\b" + name + r"\s*:\s*\(?\{", txt)
    if not m:
        return None
    i = m.end() - 1; depth = 0
    for j in range(i, len(txt)):
        depth += txt[j] == "{"; depth -= txt[j] == "}"
        if depth == 0:
            body = txt[i:j + 1]; break
    else:
        return None
    body = re.sub(r"//[^\n]*", "", body)
    body = re.sub(r"Easing\.(\w+)", r'"\1"', body)
    body = re.sub(r"([{,]\s*)([A-Za-z_]\w*)\s*:", r'\1"\2":', body)
    try:
        return json.loads(body)
    except ValueError:
        return None
STATIC = ("alpha", "radius", "space", "font", "motion", "bar")
for name, path in (("Tokens.qml", f"{qml}/theme/Tokens.qml"), ("stub Theme.qml", f"{qml}/overview/tst/stub/modules/theme/Theme.qml")):
    txt = open(f"{root}/{path}").read()
    for grp in STATIC:
        got = qml_group(txt, grp)
        check(f"{name} {grp} matches the generator", got == preset[grp], f"{got} vs {preset[grp]}")

# the shell must refuse a stale wallpaper-era tokens.json too (Theme.qml apply(), run under node
# with Tokens.build() lifted from Tokens.qml and Palette from palette.yaml)
if shutil.which("node"):
    th = open(f"{root}/{qml}/theme/Theme.qml").read()
    tk = open(f"{root}/{qml}/theme/Tokens.qml").read()
    ma = re.search(r"\n  function apply\(text\) \{.*?\n  \}\n", th, re.S)
    mb = re.search(r"\n  function rgb.*?\n  function build\(\) \{.*?\n  \}\n", tk, re.S)
    check("Theme.apply/Tokens.build extractable", bool(ma and mb))
    if ma and mb:
        js = ("var Palette=" + json.dumps(pal) + ";var console={log:function(){}};"
              "var Tokens=(function(){" + mb.group(0) + "return {build:build};})();"
              "var root={tok:null};" + ma.group(0) + ";"
              "var d=Tokens.build();var out=[];"
              "var stale=JSON.parse(JSON.stringify(d));stale.source='wallpaper';stale.color.accent='#94cdf7';"
              "stale.color.accentFg='#00315b';stale.motion.slow=240;"
              "apply(JSON.stringify(stale));out.push(root.tok.motion.slow);out.push(root.tok.color.accent);"
              "var hues=JSON.parse(JSON.stringify(d));hues.color.amber='#f2b04d';"
              "apply(JSON.stringify(hues));out.push(Object.keys(root.tok.color).length);"
              "var slow=JSON.parse(JSON.stringify(d));slow.color.accent='#123456';slow.motion.slow=240;"
              "apply(JSON.stringify(slow));out.push(root.tok.color.accent);"
              "var ok=JSON.parse(JSON.stringify(d));ok.source='wallpaper';ok.color.bg='#010203';"
              "apply(JSON.stringify(ok));out.push(root.tok.color.bg);"
              "process.stdout.write(JSON.stringify(out));")
        r = subprocess.run(["node", "-e", js], capture_output=True, text=True)
        check("Theme.apply runs under node", r.returncode == 0, r.stderr.strip()[-300:])
        if r.returncode == 0:
            got = json.loads(r.stdout)
            check("shell refuses stale wallpaper-era file: slide 180", got[0] == 180, str(got))
            check("shell refuses stale wallpaper-era file: accent is the palette accent", got[1] == pal["accent"], str(got))
            check("shell refuses an extra-hue colour set", got[2] == 15, str(got))
            check("shell refuses motion.slow > 180 even with 15 colour keys", got[3] == pal["accent"], str(got))
            check("shell still accepts a valid v1 file", got[4] == "#010203", str(got))

# a stale pre-v1 tokens.json must never produce a traceback
old_schema = {"v": 1, "source": "preset", "mode": "dark", "wallpaper": None,
              "color": {"bg": "#101010", "amber": "#f2b04d", "red": "#ff0000", "green": "#00ff00", "purple": "#aa00ff", "fg": "#ffffff"},
              "alpha": {"slab": .8}, "radius": {"chip": 6}, "space": {"s": 4}, "font": {"sans": "x"}, "motion": {"slow": 240}, "bar": {"height": 30}}
for label, body in (("old-schema keys", json.dumps(old_schema)), ("no version", json.dumps({"color": {"amber": "#fff"}})),
                    ("json list", "[1, 2]"), ("truncated json", '{"v": 1, "col')):
    for cmd in (("emit",), ("icons",), ("status",)):
        open(tok, "w").write(body)
        shutil.rmtree(f"{out}/icons-out", ignore_errors=True)
        r = subprocess.run([bin_, *cmd], capture_output=True, text=True)
        check(f"stale tokens ({label}): `{cmd[0]}` exits 0", r.returncode == 0, r.stderr.strip()[-200:])
        check(f"stale tokens ({label}): `{cmd[0]}` no traceback", "Traceback" not in r.stderr and "KeyError" not in r.stderr, r.stderr.strip()[-200:])
    open(tok, "w").write(body)
    run("emit")
    fixed = json.load(open(tok)); jsonschema.validate(fixed, schema)
    check(f"stale tokens ({label}): emit regenerates from the preset", fixed["source"] == "preset" and fixed["color"]["accent"] == pal["accent"])
run("preset")

# icons: the recolour hue ramp is its own list, not the token colours
shutil.rmtree(f"{out}/icons-out", ignore_errors=True)
run("icons")
rsvg = open(f"{idir}/scalable/apps/red.svg").read()
fills = re.findall(r'fill="(#[0-9a-f]{6})"', rsvg)
token_vals = set(json.load(open(tok))["color"].values()) | set(pal.values())
check("icons: red icon recoloured onto the ramp, not a token colour", bool(fills) and fills[-1] not in token_vals and rgb(fills[-1])[0] > max(rgb(fills[-1])[1:]), rsvg)

# emit regenerates the consumers from tokens.json
for p in ("hypr/colors.conf", "ghostty/dots-theme.conf", "swaync/dots-theme.css", "hypr/hyprlock-colors.conf"):
    f = f"{out}/cfgout/{p}"
    check(f"emit wrote {p}", os.path.isfile(f))
check("colors.conf carries the accent", "rgb(" + pal["accent"].lstrip("#") + ")" in open(f"{out}/cfgout/hypr/colors.conf").read())
os.remove(f"{out}/cfgout/hypr/colors.conf"); run("emit")
check("emit alone rebuilds colors.conf", os.path.isfile(f"{out}/cfgout/hypr/colors.conf"))
leftover = [n for n in os.listdir(f"{out}/state/dots-theme") if n.endswith(".tmp")]
check("no .tmp files left behind", not leftover, str(leftover))

if fails:
    print("\n".join("FAIL: " + f for f in fails)); sys.exit(1)
print("theme ok")
PY
rc=$?
[ "$rc" = 0 ] || exit "$rc"

# when a real matugen is installed, prove the role mapping against its actual output too
if [ -n "$real_matugen" ] && command -v magick >/dev/null; then
  magick -size 64x64 'gradient:#336699-#aa4466' "$out/real.png"
  PATH="$(dirname "$real_matugen"):$PATH" "$bin" wallpaper "$out/real.png" || { echo "FAIL: real matugen run"; exit 1; }
  jq -e '.source == "wallpaper" and (.color.accent | test("^#[0-9a-f]{6}$"))' "$XDG_STATE_HOME/dots-theme/tokens.json" >/dev/null \
    || { echo "FAIL: real matugen tokens"; exit 1; }
  echo "theme ok (real matugen)"
fi
