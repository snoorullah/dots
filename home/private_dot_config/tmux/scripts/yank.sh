#!/usr/bin/env bash
# Smart clipboard backend — tries system clipboard, falls back to OSC 52

set -eu

buf=$(cat "$@")

copy_backend_remote_tunnel_port=$(tmux show-option -gvq "@copy_backend_remote_tunnel_port" 2>/dev/null)

copy_to_osc52() {
  buflen=$(printf %s "$buf" | wc -c)
  maxlen=74994
  if [ "$buflen" -gt "$maxlen" ]; then
    printf "input too long: %d bytes, max %d\n" "$buflen" "$maxlen" >&2
    return 1
  fi
  encoded=$(printf %s "$buf" | base64 | tr -d '\n')

  # Build OSC 52 escape sequence
  esc="\033]52;c;${encoded}\a"

  # Determine the correct escape wrapping for tmux
  pane_active_tty=$(tmux list-panes -F "#{pane_active} #{pane_tty}" | awk '$1=="1" { print $2 }')
  printf "\033Ptmux;\033%b\033\\\\" "$esc" > "$pane_active_tty"
}

# Try xsel first
if command -v xsel >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  printf %s "$buf" | xsel -bi
  exit 0
fi

# Try xclip
if command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  printf %s "$buf" | xclip -selection clipboard
  exit 0
fi

# Try wl-copy (Wayland)
if command -v wl-copy >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  printf %s "$buf" | wl-copy
  exit 0
fi

# Fallback: OSC 52
copy_to_osc52
