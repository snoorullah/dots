#!/usr/bin/env bash
# Fuzzy password picker for pass (password-store)
# Opens fzf popup (tmux display-popup or Herdr popup), copies selected password to clipboard
# Auto-clears clipboard after 45 seconds

set -eu

# Works under tmux and Herdr: tmux status-line message when in tmux, desktop toast otherwise.
note() {
  if [ -n "${TMUX:-}" ]; then
    tmux display-message "$1"
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="dots-mux" "$1"
  else
    printf '%s\n' "$1" >&2
  fi
}

STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# List all passwords (strip .gpg extension and store path)
entries=$(find "$STORE_DIR" -name '*.gpg' -printf '%P\n' 2>/dev/null | sed 's/\.gpg$//' | sort)

if [ -z "$entries" ]; then
  note "Password store is empty"
  exit 0
fi

# Fuzzy pick
selected=$(printf '%s\n' "$entries" | fzf-tmux -p -w 60% -h 40% \
  --prompt='  ' \
  --header='enter=copy  ctrl-u=user  ctrl-o=otp' \
  --expect='ctrl-u,ctrl-o' \
  --no-multi)

[ -z "$selected" ] && exit 0

# Parse fzf --expect key
key=$(printf '%s' "$selected" | head -1)
entry=$(printf '%s' "$selected" | tail -1)

[ -z "$entry" ] && exit 0

case "$key" in
  ctrl-u)
    # Copy username (second line of entry, or "user:" field)
    user=$(pass show "$entry" 2>/dev/null | grep -iE '^(user|username|login):' | head -1 | sed 's/^[^:]*:[[:space:]]*//')
    if [ -n "$user" ]; then
      printf '%s' "$user" | wl-copy 2>/dev/null || printf '%s' "$user" | xclip -selection clipboard 2>/dev/null
      note "Copied username for $entry"
    else
      note "No username found for $entry"
    fi
    ;;
  ctrl-o)
    # Copy OTP if pass-otp is available
    if otp=$(pass otp "$entry" 2>/dev/null); then
      printf '%s' "$otp" | wl-copy 2>/dev/null || printf '%s' "$otp" | xclip -selection clipboard 2>/dev/null
      note "Copied OTP for $entry (30s)"
    else
      note "No OTP configured for $entry"
    fi
    ;;
  *)
    # Copy password (first line) — auto-clears after 45s
    pass -c "$entry" 2>/dev/null
    note "Copied password for $entry (clears in 45s)"
    ;;
esac
