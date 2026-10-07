#!/usr/bin/env bash
# Refresh environment variables from tmux session environment
# Prevents stale SSH_AUTH_SOCK, DISPLAY, etc. after reconnecting

set -eu

vars="SSH_AUTH_SOCK SSH_CONNECTION DISPLAY SSH_TTY"

for var in $vars; do
  val=$(tmux show-environment -g "$var" 2>/dev/null) || continue
  if printf %s "$val" | grep -q '^-'; then
    unset "$var" 2>/dev/null || true
  else
    val="${val#*=}"
    export "$var"="$val"
  fi
done

# Update the running shell's environment
if [ -n "${TMUX:-}" ]; then
  for var in $vars; do
    val=$(tmux show-environment "$var" 2>/dev/null) || continue
    if printf %s "$val" | grep -q '^-'; then
      tmux set-environment -u "$var" 2>/dev/null || true
    fi
  done
fi
