#!/usr/bin/env bash
# qs-dots end to end: static rules, the dots-shell switch, then the real shell on a
# private headless Hyprland (tests/qs-harness.sh) with pixel assertions (tests/pixel.py).
#
# Parts that need a tool this machine lacks print SKIP and do not fail; the summary says
# how many. QS_IDLE_SECS shortens the idle-cost window (the spec's 60 s is the default).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
. "$root/tests/qs-harness.sh"
# the harness half runs inside a private session bus so it can never touch the real
# notification daemon; re-exec once, before anything else has happened
if qsh_have 2>/dev/null; then qsh_reexec "$0" "$@"; fi

fails=0; skips=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
skip() { echo "SKIP: $*"; skips=$((skips + 1)); }

out="$(mktemp -d)"
cleanup() { qsh_down; rm -rf "$out"; }
trap cleanup EXIT
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out" || { echo "FAIL: render"; exit 1; }
dots="$out/.config/quickshell/dots"
py="$root/tests"

# ── 1. static rules ────────────────────────────────────────────────────
[ -f "$dots/shell.qml" ] && ok "shell.qml rendered" || fail "shell.qml not rendered"

# no private-use codepoint anywhere (Material Symbols go by ligature name), re-asserted here
if LC_ALL=C.UTF-8 grep -rIlP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$dots" "$out/.local/bin/dots-shell" "$out/.local/bin/dots-theme" "$root/third_party" 2>/dev/null | grep .; then
  fail "private-use codepoint in the shell tree"
else ok "no private-use codepoints"; fi

# no GPL file copied: vendor/ is absent, or every file in it has an SPDX header and a NOTICE line
if [ -d "$root/home/private_dot_config/quickshell/dots/vendor" ]; then
  bad=0
  while IFS= read -r f; do
    head -5 "$f" | grep -q 'SPDX-License-Identifier' || bad=1
  done < <(find "$root/home/private_dot_config/quickshell/dots/vendor" -type f)
  grep -q 'vendor/ii' "$root/third_party/NOTICE" || bad=1
  [ "$bad" = 0 ] && ok "vendor/ is headed and noticed" || fail "vendor/ files lack an SPDX header or a NOTICE line"
else ok "no vendor/ (no GPL file copied)"; fi
grep -q 'ii-p3drovfx' "$root/third_party/NOTICE" && grep -q 'tally-screentime' "$root/third_party/NOTICE" \
  && ok "NOTICE lists both upstreams" || fail "NOTICE misses an upstream"

# every file that mentions a company-ish name would trip lint.sh; this is the shell's own copy of the rule.
# The banned handle is assembled at run time (as tests/track.sh does): it is a pattern this
# file must MATCH, and writing it as a literal would make this very file a hit for the rule.
pat_co="$(printf 'pnow|kaarbaaz|code42|proficient|%s|contabo' "web""sleak")"
if grep -rIiE "$pat_co" "$dots" "$out/.local/bin/dots-shell" "$out/.local/bin/dots-theme" "$out/.config/matugen" 2>/dev/null | grep .; then
  fail "company name in the shell tree"; else ok "shell tree names no company"; fi

# ── 2. hyprland wiring ─────────────────────────────────────────────────
lua="$out/.config/hypr/hyprland.lua"
for ns in qs-bar qs-notif qs-osd qs-panel qs-overview; do
  grep -q "namespace = \"$ns\"" "$lua" && ok "layer rule $ns" || fail "layer rule $ns missing"
done
n=$(grep -c 'dots-shell start' "$lua")
[ "$n" = 1 ] && ok "one autostart line" || fail "autostart: $n dots-shell start lines"
for b in 'ALT + I' 'SHIFT + I' 'ALT + F' 'SHIFT + T' 'ALT + J' 'ALT + Q'; do
  grep -q "mod .. \" + $b\"" "$lua" && ok "bind $b" || fail "bind $b missing"
done
# each new bind key is declared once (a duplicate would silently shadow)
dups=$(grep -oE 'hl.bind\(mod \.\. " \+ [A-Za-z0-9 +]*[A-Za-z0-9]"' "$lua" | sort | uniq -d)
[ -z "$dups" ] && ok "no duplicate binds" || fail "duplicate binds: $dups"
if command -v Hyprland >/dev/null 2>&1; then
  r="$(Hyprland --verify-config -c "$lua" 2>&1)"
  echo "$r" | grep -q 'config ok' && ok "Hyprland accepts the rendered config" || { fail "Hyprland rejects the config"; echo "$r" | tail -5; }
else skip "Hyprland --verify-config (Hyprland not installed)"; fi

# ── 3. dots-shell, with every external command stubbed ─────────────────
sh="$out/.local/bin/dots-shell"
stub="$out/stub"; mkdir -p "$stub" "$out/qs/dots"
log="$out/calls.log"
for c in pkill pgrep setsid waybar swaync swayosd-server swayosd-client quickshell wpctl brightnessctl sleep; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$log" > "$stub/$c"
  chmod +x "$stub/$c"
done
# setsid -f <cmd> ... : record the command it would have started
printf '#!/bin/sh\nshift\necho "setsid $*" >> "%s"\n' "$log" > "$stub/setsid"; chmod +x "$stub/setsid"
: > "$out/qs/dots/shell.qml"
run() { : > "$log"; env HOME="$out/home" XDG_STATE_HOME="$out/state" DOTS_QS_DIR="$out/qs/dots" PATH="$stub:$PATH" bash "$sh" "$@"; }
mkdir -p "$out/home"

[ "$(run status)" = waybar ] && ok "default shell is waybar" || fail "default shell is not waybar"
run use quickshell
[ "$(run status)" = quickshell ] && ok "use quickshell is remembered" || fail "use quickshell not remembered"
run use quickshell; grep -q '^pkill swaync' "$log" && grep -q '^pkill waybar' "$log" && grep -q '^pkill swayosd-server' "$log" \
  && ok "use quickshell stops waybar, swaync, swayosd" || fail "use quickshell did not stop the waybar side"
grep -q '^setsid quickshell -p .* -n' "$log" && ok "use quickshell starts quickshell once" || fail "quickshell not started"
# swaync must be stopped BEFORE quickshell starts (it has to own the bus name)
[ "$(grep -n '^pkill swaync' "$log" | head -1 | cut -d: -f1)" -lt "$(grep -n '^setsid quickshell' "$log" | head -1 | cut -d: -f1)" ] \
  && ok "swaync stopped before quickshell starts" || fail "swaync stopped after quickshell started"
run start; grep -q '^setsid quickshell' "$log" && ! grep -q '^setsid waybar' "$log" && ok "start follows the active shell (quickshell)" || fail "start ignored the active shell"
run use waybar
[ "$(run status)" = waybar ] && ok "use waybar is remembered" || fail "use waybar not remembered"
run use waybar; grep -q '^setsid waybar' "$log" && grep -q '^setsid swaync' "$log" && grep -q '^setsid swayosd-server -s .*swayosd/style.css' "$log" \
  && ok "use waybar restores waybar, swaync, swayosd with its stylesheet" || fail "use waybar did not restore the waybar side"
grep -q '^quickshell kill' "$log" && ok "use waybar stops quickshell" || fail "use waybar did not stop quickshell"
run toggle; [ "$(run status)" = quickshell ] && ok "toggle flips to quickshell" || fail "toggle did not flip"
run toggle; [ "$(run status)" = waybar ] && ok "toggle flips back" || fail "toggle did not flip back"
run use nonsense >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "unknown shell refused" || fail "unknown shell accepted"
# no quickshell config on disk -> refuse, and start falls back to waybar rather than a bare desktop
mv "$out/qs/dots/shell.qml" "$out/qs/dots/shell.qml.off"
printf 'quickshell\n' > "$out/state/dots-shell/active"
run start 2>/dev/null; grep -q '^setsid waybar' "$log" && ok "missing shell falls back to waybar" || fail "no fallback when the shell is missing"
mv "$out/qs/dots/shell.qml.off" "$out/qs/dots/shell.qml"
# media keys: waybar -> swayosd; quickshell -> wpctl/brightnessctl + OSD ipc
printf 'waybar\n' > "$out/state/dots-shell/active"
run key volume raise; grep -q '^swayosd-client --output-volume raise' "$log" && ok "volume key under waybar -> swayosd" || fail "volume key under waybar"
printf 'quickshell\n' > "$out/state/dots-shell/active"
run key volume raise; grep -q '^wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+' "$log" && grep -q 'quickshell ipc .* call dots.osd display volume' "$log" \
  && ok "volume key under quickshell -> wpctl + OSD" || fail "volume key under quickshell"
run key brightness lower; grep -q '^brightnessctl -c backlight set 5%-' "$log" && ok "brightness key under quickshell" || fail "brightness key under quickshell"
# the live hyprland config no longer starts waybar/swaync/swayosd directly
if grep -E 'exec_cmd\("(waybar|swaync|swayosd-server)[" ]' "$lua"; then fail "hyprland still starts the waybar side directly"; else ok "autostart goes only through dots-shell"; fi

# ── 4. qmllint ─────────────────────────────────────────────────────────
qml_imports() {
  local d q
  if [ -n "${QS_QML_IMPORTS:-}" ]; then tr ':' '\n' <<< "$QS_QML_IMPORTS"; return; fi
  q="$(readlink -f "$(command -v quickshell 2>/dev/null)" 2>/dev/null)"; [ -n "$q" ] && echo "$(dirname "$(dirname "$q")")/lib/qt-6/qml"
  d="$(readlink -f "$(command -v qmllint 2>/dev/null)" 2>/dev/null)"; [ -n "$d" ] && echo "$(dirname "$(dirname "$d")")/lib/qt-6/qml"
}
if command -v qmllint >/dev/null 2>&1 && qmllint --version >/dev/null 2>&1 && command -v quickshell >/dev/null 2>&1; then
  inc=(); while IFS= read -r d; do [ -d "$d" ] && inc+=(-I "$d"); done < <(qml_imports)
  # Quickshell does not export its C++ types in a way qmllint can resolve for these two
  # categories (a Process exit signal's QProcess::ExitStatus, PanelWindow itself); everything
  # else is a real warning. Each remaining false positive carries its own inline directive.
  # modules/overview imports through the qs. module path, which qmllint cannot resolve from the
  # rendered tree; tests/overview-ui.sh lints it (and its stub Theme's agreement with the real one).
  lintout="$(find "$dots" -name '*.qml' -not -path '*/modules/overview/*' | sort | xargs qmllint --uncreatable-type disable --signal-handler-parameters disable "${inc[@]}" 2>&1)"
  if [ -z "$lintout" ]; then ok "qmllint: zero warnings over $(find "$dots" -name '*.qml' -not -path '*/modules/overview/*' | wc -l) files"
  else fail "qmllint warnings"; echo "$lintout" | head -30; fi
else skip "qmllint (qmllint 6 or quickshell not installed)"; fi

# ── 5. the live shell on a private compositor ──────────────────────────
if ! qsh_have; then
  skip "headless harness (Hyprland, quickshell or grim missing)"
else
  qsh_up || { fail "private compositor did not start"; exit 1; }
  home="$QSH_DIR/home"; st="$home/.local/state"; mkdir -p "$home/.local/bin"
  # ops stub: nominal. Everything else the bar reads is absent, which must mean "hidden".
  printf '#!/bin/sh\necho "{\\"text\\":\\"\\",\\"class\\":\\"ok\\",\\"tooltip\\":\\"\\"}"\n' > "$home/.local/bin/dots-ops"
  chmod +x "$home/.local/bin/dots-ops"
  export QSH_SHELL_DIR="$dots"
  qsh_shell "$dots" || { fail "shell did not load"; exit 1; }
  grep -qE 'ERROR.*(shell|modules|services)/.*qml|Could not|is not a type|ReferenceError|TypeError' "$QSH_LOG" \
    && { fail "QML errors in the shell log"; grep -E 'ERROR|Could not|is not a type|ReferenceError|TypeError' "$QSH_LOG" | head; } \
    || ok "shell log is free of QML errors"

  shots="$QSH_DIR/shots"; mkdir -p "$shots"

  # 5a. the bar at 1920 x 30, nominal
  qsh_shot "$shots/nominal.png"
  read -r bw bh <<< "$(qsh_layer_size qs-bar)"
  [ "$bh" = 30 ] && ok "qs-bar layer is 30 high" || fail "qs-bar layer height '$bh' (want 30)"
  python3 - "$py" "$shots/nominal.png" <<'PY' && ok "nominal bar: 30 rows, three slabs, no amber, no red" || fail "nominal bar pixels"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2]); fails = []
bg = s.pixel(960, 600)                                    # flat compositor background
rows = s.rows_with_non_bg((0, 0, s.w, 40), bg=bg)
if len(rows) != 30 or rows[0] != 0 or rows[-1] != 29: fails.append(f"bar rows {len(rows)} ({rows[:1]}..{rows[-1:]}), want exactly 0..29")
runs = s.col_runs((0, 0, s.w, 30), bg=bg)
if len(runs) != 3: fails.append(f"{len(runs)} slabs {runs}, want 3")
for name, hexc in (("amber", "#ffb86c"), ("red", "#ff5555")):
    n = s.count_colour(hexc, (0, 0, s.w, 40), tol=30)
    if n: fails.append(f"nominal bar holds {n} {name} pixels")
if fails: print("\n".join(fails)); sys.exit(1)
PY

  # 5b. lamp test: amber and red appear, dividers are 1 px
  qsh_ipc bar lamp >/dev/null; sleep 0.5
  qsh_shot "$shots/lamp.png"
  python3 - "$py" "$shots/lamp.png" <<'PY' && ok "lamp test: amber and red present, 1 px dividers" || fail "lamp pixels"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2]); fails = []
bg = s.pixel(960, 600)
runs = s.col_runs((0, 0, s.w, 30), bg=bg)
for name, hexc in (("amber", "#ffb86c"), ("red", "#ff5555")):
    if not s.has_colour((0, 0, s.w, 40), hexc, tol=30, min_count=20): fails.append(f"lamp shows no {name}")
right = runs[-1]
lines = s.thin_verticals((right[0], 4, right[1], 26), 18)
if not lines: fails.append("no 1 px divider found in the lit right slab")
if len({c for _, c in lines}) > 1: fails.append(f"divider colours differ: {lines}")
if fails: print("\n".join(fails)); sys.exit(1)
PY
  sleep 1.2   # the lamp lets go by itself
  qsh_shot "$shots/after-lamp.png"
  python3 - "$py" "$shots/after-lamp.png" <<'PY' && ok "lamp lets go: nominal again" || fail "lamp did not let go"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2])
bad = sum(s.count_colour(h, (0, 0, s.w, 40), tol=30) for h in ("#ffb86c", "#ff5555"))
sys.exit(1 if bad else 0)
PY

  # 5c. tokens: defaults == preset, and a tokens.json change repaints without a restart
  theme="$out/.local/bin/dots-theme"
  tenv=(env HOME="$home" XDG_STATE_HOME="$st" XDG_CONFIG_HOME="$home/.config")
  python3 - "$py" "$shots/nominal.png" "$shots/defaults-left.png" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2]); c = s.crop((0, 0, 200, 30))
open(sys.argv[3], "wb").write(c.data)
PY
  "${tenv[@]}" "$theme" preset >/dev/null; sleep 3.6   # tokens.json did not exist: the missing-file retry (3 s) is what finds it
  qsh_shot "$shots/preset.png"
  python3 - "$py" "$shots/preset.png" "$shots/defaults-left.png" <<'PY' && ok "tokens.json preset paints the same bar as the built-in defaults" || fail "defaults differ from preset"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2]); c = s.crop((0, 0, 200, 30))
sys.exit(0 if c.data == open(sys.argv[3], "rb").read() else 1)
PY
  jq '.color.surface = "#3b2f6f"' "$st/dots-theme/tokens.json" > "$st/dots-theme/t.tmp" && mv "$st/dots-theme/t.tmp" "$st/dots-theme/tokens.json"; sleep 1.0
  qsh_shot "$shots/retinted.png"
  python3 - "$py" "$shots/retinted.png" "$shots/preset.png" <<'PY' && ok "a tokens.json change repaints the live shell" || fail "tokens.json change did not repaint"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
a = pixel.Shot(sys.argv[2]).crop((0, 0, 200, 30)); b = pixel.Shot(sys.argv[3]).crop((0, 0, 200, 30))
sys.exit(0 if a.data != b.data else 1)
PY
  if command -v matugen >/dev/null 2>&1 && command -v magick >/dev/null 2>&1; then
    magick -size 64x64 'gradient:#336699-#aa4466' "$home/wall.png"
    "${tenv[@]}" "$theme" wallpaper "$home/wall.png" >/dev/null && sleep 1.0 && qsh_shot "$shots/wall.png"
    python3 - "$py" "$shots/wall.png" "$shots/preset.png" <<'PY' && ok "wallpaper tokens repaint the live shell" || fail "wallpaper tokens did not repaint"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
a = pixel.Shot(sys.argv[2]).crop((0, 0, 200, 30)); b = pixel.Shot(sys.argv[3]).crop((0, 0, 200, 30))
sys.exit(0 if a.data != b.data else 1)
PY
  else skip "wallpaper repaint (matugen or magick missing)"; fi
  "${tenv[@]}" "$theme" preset >/dev/null; sleep 0.8

  # 5d. toasts, under the private bus
  tid="$(notify-send -p 'harness one' 'first body' 2>/dev/null)"; sleep 0.8
  c="$(qsh_ipc notif count | tr -d '[:space:]')"
  [ "$c" = 1 ] && ok "notify-send shows one toast" || fail "toast count '$c' (want 1)"
  read -r tw th <<< "$(qsh_layer_size qs-notif)"
  [ "$tw" = 380 ] && ok "toast is 380 wide" || fail "toast width '$tw' (want 380)"
  qsh_shot "$shots/toast.png"
  python3 - "$py" "$shots/toast.png" <<'PY' && ok "toast pixels: 380 +-2 wide, top right" || fail "toast pixels"
import sys
sys.path.insert(0, sys.argv[1]); import pixel
s = pixel.Shot(sys.argv[2]); bg = s.pixel(960, 600)
box = s.bbox_of_non_bg((1400, 34, 1920, 400), bg=bg)
pixel.assert_width(box, 380, tol=2, what="toast")
if box[2] < 1900 or box[1] < 36: raise SystemExit(f"toast at {box}, want flush top-right")
PY
  notify-send -r "$tid" 'harness two' 'second body' >/dev/null 2>&1; sleep 0.6
  c="$(qsh_ipc notif count | tr -d '[:space:]')"
  [ "$c" = 1 ] && ok "replaces_id updates in place (still one toast)" || fail "replace left $c toasts"
  dbus-send --session --dest=org.freedesktop.Notifications --type=method_call /org/freedesktop/Notifications org.freedesktop.Notifications.CloseNotification "uint32:$tid" >/dev/null 2>&1; sleep 0.6
  c="$(qsh_ipc notif count | tr -d '[:space:]')"
  [ "$c" = 0 ] && ok "closing the notification retracts the toast" || fail "toast did not retract ($c)"

  # 5e. OSD, popouts
  qsh_ipc osd display volume >/dev/null; sleep 0.5
  read -r ow oh <<< "$(qsh_layer_size qs-osd)"
  [ "$ow $oh" = "220 48" ] && ok "OSD is 220x48" || fail "OSD size '$ow $oh'"
  for spec in "bar calendar:300" "quick toggle:320" "notif toggle:380"; do
    surf="${spec%%:*}"; want="${spec##*:}"; set -- $surf
    qsh_ipc "$1" "$2" >/dev/null; sleep 0.6
    read -r pw ph <<< "$(qsh_layer_size qs-panel)"
    [ "$pw" = "$want" ] && ok "$1 $2 popout is $want wide (h $ph)" || fail "$1 $2 popout width '$pw' (want $want)"
    qsh_ipc "$1" "$2" >/dev/null; sleep 0.5       # toggle closed again
  done

  # 5f. the workspace command Hypr.qml sends really switches workspace (Lua dispatch form)
  hyprctl dispatch 'hl.dsp.focus({ workspace = "4" })' >/dev/null 2>&1; sleep 0.3
  [ "$(hyprctl -j activeworkspace | jq -r .id)" = 4 ] && ok "hl.dsp.focus workspace switch works" || fail "workspace switch via hl.dsp.focus failed"

  # 5g. idle cost, measured on the quiet shell
  secs="${QS_IDLE_SECS:-60}"
  qpid="$(pgrep -P "$QSH_LAST_PID" | head -1)"
  if [ -n "$qpid" ] && [ -r "/proc/$qpid/stat" ]; then
    tick="$(getconf CLK_TCK)"
    t0="$(awk '{print $14 + $15}' "/proc/$qpid/stat")"; sleep "$secs"
    t1="$(awk '{print $14 + $15}' "/proc/$qpid/stat")"
    rss_kb="$(awk '/VmRSS/ {print $2}' "/proc/$qpid/status")"
    pct="$(awk -v a="$t0" -v b="$t1" -v t="$tick" -v s="$secs" 'BEGIN { printf "%.2f", (b - a) / t / s * 100 }')"
    [ "${rss_kb:-999999}" -lt 184320 ] && ok "idle RSS $((rss_kb / 1024)) MB (< 180)" || fail "idle RSS $((rss_kb / 1024)) MB (want < 180)"
    awk -v p="$pct" 'BEGIN { exit !(p < 1.0) }' && ok "idle CPU ${pct}% over ${secs}s (< 1%)" || fail "idle CPU ${pct}% over ${secs}s (want < 1%)"
  else skip "idle cost (could not find the quickshell pid)"; fi

  # 5h. another daemon owns the notification bus: the shell must not fight for it
  qsh_kill "$QSH_LAST_PID"
  mkdir -p "$QSH_DIR/owner"
  cat > "$QSH_DIR/owner/shell.qml" <<'QML'
import Quickshell
import Quickshell.Services.Notifications
ShellRoot { NotificationServer { bodySupported: true } }
QML
  QSH_LOG_NAME=owner.log qsh_shell "$QSH_DIR/owner" && owner_pid="$QSH_LAST_PID"
  QSH_LOG_NAME=held.log qsh_shell "$dots"; sleep 1.5
  held_pid="$QSH_LAST_PID"
  grep -q 'held by another daemon' "$QSH_DIR/held.log" && ok "shell stays out when another daemon owns the bus" || fail "shell did not notice the other daemon"
  kill -0 "$held_pid" 2>/dev/null && ok "shell keeps running (no crash loop)" || fail "shell died with the bus held"
  [ -n "${owner_pid:-}" ] && qsh_kill "$owner_pid"
fi

echo
if [ "$fails" = 0 ]; then echo "shell ok ($skips skipped)"; exit 0; fi
echo "shell: $fails FAILED ($skips skipped)"; exit 1
