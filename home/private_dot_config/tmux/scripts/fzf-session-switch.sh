#!/usr/bin/env bash
# Direct session switcher — skips the menu, goes straight to fzf pick
set -u

if [ -z "${TMUX_FZF_FLOAT:-}" ] && [ -n "${TMUX:-}" ]; then
    exec "$HOME/.config/tmux/scripts/fzf-float.sh" "$0" "$@"
fi

TMUX_BIN="/usr/bin/tmux"
current=$($TMUX_BIN display-message -p '#S')
sessions=$($TMUX_BIN list-sessions -F '#S: #{session_windows} windows#{?session_attached, (attached),}' | grep -v "^${current}:")

target=$(printf "%s" "$sessions" | fzf \
    --prompt="  " \
    --header="tmux-fzf › session › switch" \
    --no-multi) || exit 0

[ -z "$target" ] && exit 0
session=$(echo "$target" | cut -d: -f1)
$TMUX_BIN switch-client -t "$session"
