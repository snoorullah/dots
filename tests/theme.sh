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

# a stub matugen printing the shape matugen 4.x gives for `image --json hex`
# (checked against the real binary: colors.<role>.dark.color)
stub="$out/stub"; mkdir -p "$stub"
cat > "$stub/matugen" <<'EOF'
#!/bin/sh
cat <<'JSON'
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
    m = re.match(r'^  (bg|fg|sel|comment|cyan|green|orange|pink|purple|red|yellow): "(#[0-9a-f]{6})"', line)
    if m: pal[m.group(1)] = m.group(2)
check("palette parsed", len(pal) == 11)

def rgb(h): return [int(h[i:i+2], 16) for i in (1, 3, 5)]
def hx(c): return "#" + "".join(f"{round(v):02x}" for v in c)
def mix(a, b, t): return hx([x + (y - x) * t for x, y in zip(rgb(a), rgb(b))])

run("preset")
preset = json.load(open(tok))
jsonschema.validate(preset, schema)
c = preset["color"]
check("source preset", preset["source"] == "preset" and preset["wallpaper"] is None)
want = {
    "bg": pal["bg"], "surface": mix(pal["bg"], "#ffffff", .04), "surfaceDim": mix(pal["bg"], "#000000", .20),
    "surfaceContainer": pal["sel"], "surfaceContainerHigh": mix(pal["sel"], "#ffffff", .06),
    "outline": pal["comment"], "outlineVariant": mix(pal["comment"], pal["bg"], .5),
    "fg": pal["fg"], "fgDim": mix(pal["comment"], pal["fg"], .40), "fgFaint": mix(pal["bg"], mix(pal["comment"], pal["fg"], .40), .70),
    "accent": pal["purple"], "accentFg": pal["bg"], "amber": pal["orange"], "red": pal["red"],
}
for k, v in want.items(): check(f"preset derivation {k}", c[k] == v, f"got {c[k]} want {v}")

# determinism: a second run is byte-identical
a = open(tok).read(); run("preset"); check("preset is deterministic", open(tok).read() == a)

run("wallpaper", f"{out}/wall.png")
wall = json.load(open(tok))
jsonschema.validate(wall, schema)
check("source wallpaper", wall["source"] == "wallpaper" and wall["wallpaper"] == f"{out}/wall.png")
check("same key set in both modes", sorted(keys(preset)) == sorted(keys(wall)))
check("wallpaper accent comes from matugen primary", wall["color"]["accent"] == "#a2c9ff")
for k in ("amber", "red", "green"):
    check(f"status colour {k} stays semantic in wallpaper mode", wall["color"][k] == preset["color"][k])

# a wallpaper that matugen cannot map must fail loudly and leave tokens.json intact
before = open(tok).read()
r = subprocess.run([bin_, "wallpaper", f"{out}/missing.png"], capture_output=True, text=True)
check("missing wallpaper exits non-zero", r.returncode != 0)
check("failed run leaves tokens.json intact", open(tok).read() == before)

# new interaction tokens exist in both producers; panel radius is unified with card
for t_ in (preset, wall):
    check("alpha.pressed/rest/on present", all(k in t_["alpha"] for k in ("pressed", "rest", "on")))
    check("radius.panel == radius.card == 16", t_["radius"]["panel"] == 16 == t_["radius"]["card"])

# default (no args) is wallpaper mode when a wallpaper is known, preset otherwise
os.makedirs(f"{out}/.cache", exist_ok=True)
open(f"{out}/.cache/current-wallpaper", "w").write(f"{out}/wall.png")
run()
auto = json.load(open(tok)); jsonschema.validate(auto, schema)
check("default is wallpaper mode", auto["source"] == "wallpaper" and auto["color"]["accent"] == "#a2c9ff")
check("default keeps the key set", sorted(keys(auto)) == sorted(keys(preset)))
os.remove(f"{out}/.cache/current-wallpaper")
r = run()
auto = json.load(open(tok))
check("no wallpaper -> preset fallback", auto["source"] == "preset" and auto["color"]["accent"] == pal["purple"])
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

# emit regenerates the consumers from tokens.json
for p in ("hypr/colors.conf", "ghostty/dots-theme.conf", "swaync/dots-theme.css", "hypr/hyprlock-colors.conf"):
    f = f"{out}/cfgout/{p}"
    check(f"emit wrote {p}", os.path.isfile(f))
check("colors.conf carries the accent", "rgb(a2c9ff)" in open(f"{out}/cfgout/hypr/colors.conf").read())
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
