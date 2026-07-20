#!/usr/bin/env bash
# otter-tabs.sh — zen-browser tab switcher via brotab (bt), Dracula/otter styled.
# Fuzzy-search open tabs; Enter switches to it in the SAME window (bt activate +
# focus zen, no new window); ctrl-d closes a tab; ctrl-y copies its URL.
# Reuses zen-utils.sh (zen_focus_browser) and the shared otter fzf style.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"
source "$HOME/.config/rofi/scripts/zen-utils.sh"

sel="$(bt list 2>/dev/null | fzf \
    --ansi --delimiter='\t' --with-nth=2.. --tabstop=4 --no-multi \
    --header='zen tabs    enter switch   ctrl-d close   ctrl-y copy-url' --header-first \
    --bind='ctrl-d:execute-silent(bt close {1})+reload(bt list)' \
    --bind='ctrl-y:execute-silent(printf %s {3} | wl-copy)+abort')" || exit 0

[ -n "$sel" ] || exit 0
tab_id="$(printf '%s' "$sel" | awk -F'\t' '{print $1}')"
[ -n "$tab_id" ] || exit 0
bt activate "$tab_id" 2>/dev/null   # switch to the tab IN the existing zen window
zen_focus_browser                    # raise zen to the foreground
