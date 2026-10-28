#!/usr/bin/env bash
# Headless Quickshell harness: a private Hyprland on the headless backend, the shell on
# top of it, grim to take pictures. Source it; it never touches the live session.
#
#   . tests/qs-harness.sh
#   qsh_up [hyprland.lua]       start the compositor + HL-1 (default: bare config)
#   qsh_shell <dir> [KEY=VAL..] start quickshell -p <dir> with that extra env
#   qsh_ipc <surface> <fn> [a]  qs ipc call dots.<surface> <fn> [a]
#   qsh_shot <out.png>          grim -o HL-1
#   qsh_down                    reap exactly the processes this run started
#
# Why each line is the way it is (all learned the hard way):
#  - XDG_RUNTIME_DIR is a SHORT fresh dir: Hyprland's ipc socket path has a ~108 char
#    limit and $TMPDIR is longer than that on this machine.
#  - HYPRLAND_INSTANCE_SIGNATURE/WAYLAND_DISPLAY are unset first, or hyprctl and
#    quickshell talk to the LIVE compositor.
#  - grim -o HL-1, never bare grim: the 0x0 ghost output breaks a bare capture.
#  - `timeout` on every process, so a wedged compositor cannot outlive the run.
#  - no `pkill -f <pattern>`: a pattern can match this very script. We kill pids we own.
#  - `>|` for redirects: zsh users source this with noclobber set.
# Needs: Hyprland (headless), quickshell, grim. qsh_have prints what is missing.

QSH_PIDS=()

qsh_have() {
  local miss=() c
  for c in Hyprland hyprctl quickshell grim; do command -v "$c" >/dev/null 2>&1 || miss+=("$c"); done
  [ ${#miss[@]} -eq 0 ] && return 0
  echo "qs-harness: missing: ${miss[*]}" >&2; return 1
}

# The shell claims org.freedesktop.Notifications, watches MPRIS and talks to NetworkManager
# over the SESSION bus. Run against the live one it would fight the real notification
# daemon, so a harness caller must be inside dbus-run-session (qsh_reexec does that).
qsh_reexec() {   # usage, first line of a test:  qsh_reexec "$0" "$@"
  [ -n "${QSH_IN_BUS:-}" ] && return 0
  exec env QSH_IN_BUS=1 dbus-run-session -- bash "$@"
}

qsh_up() {
  qsh_have || return 1
  [ -n "${QSH_IN_BUS:-}" ] || { echo "qs-harness: refusing to run on the live session bus (call qsh_reexec first)" >&2; return 1; }
  local cfg="${1:-}"
  QSH_DIR="$(mktemp -d /tmp/qsh.XXXXXX)"; chmod 0700 "$QSH_DIR"
  QSH_REAL_HOME="$HOME"
  mkdir -p "$QSH_DIR/run" "$QSH_DIR/home/.local/state" "$QSH_DIR/home/.config" "$QSH_DIR/home/.cache"
  chmod 0700 "$QSH_DIR/run"
  unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
  export XDG_RUNTIME_DIR="$QSH_DIR/run"
  if [ -z "$cfg" ]; then
    cfg="$QSH_DIR/hyprland.lua"
    # solid background, no logo, no animation: pixel assertions need a flat canvas
    cat >| "$cfg" <<'LUA'
-- harness: bare config
hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
           background_color = "rgb(111111)" },
  animations = { enabled = false },
})
LUA
  fi
  AQ_BACKENDS=headless LIBSEAT_BACKEND=noop timeout "${QSH_TIMEOUT:-90}" Hyprland -c "$cfg" >| "$QSH_DIR/hypr.log" 2>&1 &
  QSH_PIDS+=($!)
  local i
  for i in $(seq 1 50); do
    [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break
    sleep 0.2
  done
  [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || { echo "qs-harness: compositor did not start"; tail -5 "$QSH_DIR/hypr.log"; return 1; }
  export WAYLAND_DISPLAY=wayland-1
  HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | grep _ | head -1)"
  export HYPRLAND_INSTANCE_SIGNATURE
  hyprctl output create headless HL-1 >/dev/null 2>&1
  # scale 1: the compositor picks 2 for a headless output, which doubles every pixel the
  # assertions count. The 0x0 HDMI-A-2 ghost is the headless backend's own placeholder.
  hyprctl eval 'hl.monitor({ output = "HL-1", mode = "1920x1080@60", position = "0x0", scale = 1 })' >/dev/null 2>&1
  hyprctl dismissnotify >/dev/null 2>&1      # the "started without start-hyprland" banner
  sleep 0.5
}

# Everything the shell reads lives under a throwaway HOME, so a test can place
# tokens.json and state files without touching the real ones.
qsh_shell() {
  local dir="$1"; shift
  local -a envs=("HOME=$QSH_DIR/home" "XDG_STATE_HOME=$QSH_DIR/home/.local/state"
                 "XDG_CONFIG_HOME=$QSH_DIR/home/.config" "XDG_CACHE_HOME=$QSH_DIR/home/.cache"
                 "QT_QUICK_BACKEND=software" "QT_QPA_PLATFORM=wayland")
  QSH_LOG="${QSH_LOG_NAME:-qs.log}"; QSH_LOG="$QSH_DIR/$QSH_LOG"
  env "${envs[@]}" "$@" timeout "${QSH_TIMEOUT:-90}" quickshell -p "$dir" >| "$QSH_LOG" 2>&1 &
  QSH_LAST_PID=$!
  QSH_PIDS+=($!)
  local i
  for i in $(seq 1 60); do
    grep -q 'Configuration Loaded' "$QSH_LOG" 2>/dev/null && break
    sleep 0.25
  done
  grep -q 'Configuration Loaded' "$QSH_LOG" 2>/dev/null || { echo "qs-harness: shell did not load"; tail -15 "$QSH_LOG"; return 1; }
  sleep "${QSH_SETTLE:-1.2}"
}

qsh_ipc() {
  local s="$1" f="$2"; shift 2
  env HOME="$QSH_DIR/home" timeout 10 quickshell -p "${QSH_SHELL_DIR:?}" ipc call "dots.$s" "$f" "$@" 2>&1
}

# stop one process we started (the timeout wrapper and what it runs), by pid
qsh_kill() {
  local p="$1"
  pkill -P "$p" 2>/dev/null
  kill "$p" 2>/dev/null
  sleep 0.3
}

# size of a layer surface by namespace, from the compositor itself: "W H". Exact, unlike a
# screenshot, so panel/toast/OSD widths are asserted against what was actually mapped.
qsh_layer_size() {
  hyprctl -j layers | jq -r --arg ns "$1" '[.[] | .levels[][] | select(.namespace == $ns and .w > 0)] | first | "\(.w) \(.h)"' 2>/dev/null
}

qsh_shot() { timeout 20 grim -o HL-1 "$1"; }

qsh_down() {
  local p
  for p in "${QSH_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  sleep 0.3
  for p in "${QSH_PIDS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
  QSH_PIDS=()
  [ -n "${QSH_DIR:-}" ] && [ -d "$QSH_DIR" ] && [ "${QSH_KEEP:-0}" != 1 ] && rm -rf "$QSH_DIR"
  return 0
}
