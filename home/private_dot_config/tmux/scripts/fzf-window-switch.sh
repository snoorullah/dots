#!/usr/bin/env bash
# Direct window switcher — skips the menu, goes straight to fzf pick
set -u

if [ -z "${TMUX_FZF_FLOAT:-}" ] && [ -n "${TMUX:-}" ]; then
    exec "$HOME/.config/tmux/scripts/fzf-float.sh" "$0" "$@"
fi

TMUX_BIN="/usr/bin/tmux"
current=$($TMUX_BIN display-message -p '#S:#I')
windows=$($TMUX_BIN list-windows -a -F '#S:#I: #{window_name}#{?window_active, (active),}' | grep -v "^${current}:")

target=$(printf "%s" "$windows" | fzf \
    --prompt="  " \
    --header="tmux-fzf › window › switch" \
    --no-multi) || exit 0

[ -z "$target" ] && exit 0
session=$(echo "$target" | cut -d: -f1)
win=$(echo "$target" | cut -d: -f2 | sed 's/:.*//')
$TMUX_BIN switch-client -t "$session" 2>/dev/null
$TMUX_BIN select-window -t "$session:$win"
