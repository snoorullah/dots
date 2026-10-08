#!/usr/bin/env bash
# Fuzzy-pick tmuxinator projects in a floating terminal
set -eu

# Re-launch in floating terminal if called from tmux directly
if [ -z "${TMUX_FZF_FLOAT:-}" ] && [ -n "${TMUX:-}" ]; then
    export TMUX_FZF_FLOAT=1
    exec "$HOME/.config/tmux/scripts/fzf-float.sh" "$0" "$@"
fi

project=$(tmuxinator list -n 2>/dev/null | tail -n +2 | tr ' ' '\n' | grep -v '^$' | fzf \
    --prompt='  Project  ' \
    --header='enter=start project' \
    --layout=reverse \
    --border=rounded \
    --margin=1,2) || exit 0

[ -z "$project" ] && exit 0

tmuxinator start "$project"
