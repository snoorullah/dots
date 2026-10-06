#!/usr/bin/env bash
# otter-run.sh — run an arbitrary command (fzf-based otter-launcher module)
#
# fzf over every executable name on $PATH, with --print-query so a command
# that isn't in the list (custom args, pipes, etc.) can still be typed and
# run verbatim. Reference: rofilaunch.sh mode 'r' (rofi -show run).
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

result="$(compgen -c | sort -u | fzf --print-query --header=$' run')"

# --print-query prints the typed query on line 1, and (only if the user
# actually selected a match rather than just hitting Enter on the query
# itself) the chosen entry on line 2. Prefer the selected match; fall back
# to whatever was typed.
query="$(sed -n '1p' <<<"$result")"
match="$(sed -n '2p' <<<"$result")"
cmd="${match:-$query}"

[[ -z "$cmd" ]] && exit 0

setsid -f sh -c "$cmd" >/dev/null 2>&1
