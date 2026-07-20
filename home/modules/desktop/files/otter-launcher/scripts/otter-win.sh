#!/usr/bin/env bash
# otter-win.sh — Hyprland window switcher (fzf-based otter-launcher module)
#
# hyprctl clients -j -> jq -> "address \t class — title" -> fzf -> focuswindow.
# Degrades gracefully (prints a message, no crash) if jq or hyprctl aren't
# available, or if there's nothing to show.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

# list_windows — emits "<address>\t<class> — <title>" for every mapped
# Hyprland client. Prints nothing (and nothing to stderr beyond a notice)
# if hyprctl/jq are missing or hyprctl can't reach the compositor socket.
list_windows() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq not found — window switching unavailable" >&2
        return 1
    fi
    if ! command -v hyprctl >/dev/null 2>&1; then
        echo "hyprctl not found — window switching unavailable" >&2
        return 1
    fi

    local clients_json
    clients_json="$(hyprctl clients -j 2>/dev/null)"
    if [[ -z "$clients_json" ]]; then
        echo "no response from hyprctl — is Hyprland running?" >&2
        return 1
    fi

    echo "$clients_json" | jq -r '.[] | "\(.address)\t\(.class) — \(.title)"' 2>/dev/null
}

# Debug/verification hook: print the raw list and exit, skipping fzf.
if [[ "${1:-}" == "--list" ]]; then
    list_windows
    exit 0
fi

windows="$(list_windows)"
if [[ -z "$windows" ]]; then
    echo "no windows to switch to" >&2
    exit 1
fi

selection="$(echo "$windows" | fzf --delimiter=$'\t' --with-nth=2 --header=$' windows')"
[[ -z "$selection" ]] && exit 0

addr="$(cut -f1 <<<"$selection")"
hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
