#!/usr/bin/env bash
# A shell started before the compositor must pick the session up later, without a restart.
# What must never happen: a command run from a boot-time pane has no WAYLAND_DISPLAY.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
command -v zsh >/dev/null || { echo "SKIP: no zsh"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/run" "$tmp/bin"
cat > "$tmp/bin/systemctl" <<'SH'
#!/bin/sh
echo call >> "$STUB_LOG"
printf 'HOME=/x\nWAYLAND_DISPLAY=wayland-1\nDISPLAY=:0\nHYPRLAND_INSTANCE_SIGNATURE=sig\nXDG_CURRENT_DESKTOP=Hyprland\nFOO=no\n'
SH
chmod +x "$tmp/bin/systemctl"
sed -n '/^_dots_graphical_env() {/,/^}/p' "$root/home/dot_zshrc.tmpl" > "$tmp/fn.zsh"
grep -q '^add-zsh-hook precmd _dots_graphical_env' "$root/home/dot_zshrc.tmpl"
grep -q '^add-zsh-hook preexec _dots_graphical_env' "$root/home/dot_zshrc.tmpl"
grep -q '\[ -O "$_xsock" \]' "$root/home/dot_zshrc.tmpl"
env -i HOME="$tmp" PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run" STUB_LOG="$tmp/log" RUN="$tmp/run" \
  DISPLAY=:1024 XAUTHORITY=/greeter/auth zsh -f -c '
  source '"$tmp"'/fn.zsh
  fails=0; check() { [[ "$2" == "$3" ]] || { print "FAIL $1: got [$2] want [$3]"; fails=1; } }
  calls() { [[ -f $STUB_LOG ]] && wc -l < $STUB_LOG | tr -d " " || print 0; }

  _dots_graphical_env
  check "no compositor yet: unset" "${WAYLAND_DISPLAY:-}" ""
  check "no compositor yet: no systemctl" "$(calls)" 0
  check "no compositor yet: display kept" "$DISPLAY" ":1024"

  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" $RUN/wayland-1
  : > $RUN/wayland-1.lock
  _dots_graphical_env
  check "compositor up: wayland" "$WAYLAND_DISPLAY" "wayland-1"
  check "compositor up: display" "$DISPLAY" ":0"
  check "compositor up: signature" "$HYPRLAND_INSTANCE_SIGNATURE" "sig"
  check "greeter auth dropped" "${XAUTHORITY:-}" ""
  check "other vars left alone" "${FOO:-}" ""
  check "one systemctl call" "$(calls)" 1
  check "exported to children" "$(zsh -f -c "print \$WAYLAND_DISPLAY")" "wayland-1"

  _dots_graphical_env
  check "healthy: no more calls" "$(calls)" 1

  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" $RUN/wayland-2
  export WAYLAND_DISPLAY=wayland-9
  _dots_graphical_env
  check "stale value replaced" "$WAYLAND_DISPLAY" "wayland-1"
  exit $fails
'
echo "zsh-graphical ok"
