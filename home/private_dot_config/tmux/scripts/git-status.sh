#!/usr/bin/env bash
# Git branch + colored sync status icon (nerd fonts)
# Palette: green=#50fa7b yellow=#f5d547 red=#ff4d4d purple=#bd93f9 blue=#6a8cff muted=#585880

set -eu

RESET="#[fg=#585880,bg=default,nobold]"
pane_path="${1:-$(tmux display-message -p '#{pane_current_path}')}"

cd "$pane_path" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch=$(git branch --show-current 2>/dev/null) || exit 0
[ -z "$branch" ] && exit 0

ahead=0
behind=0
counts=$(git rev-list --count --left-right "@{upstream}...HEAD" 2>/dev/null) || counts=""
if [ -n "$counts" ]; then
  behind=$(printf %s "$counts" | cut -f1)
  ahead=$(printf %s "$counts" | cut -f2)
fi

if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
  icon="#[fg=#bd93f9,bold]󰕚 "
  suffix=" #[fg=#f5d547]+${ahead}#[fg=#ff4d4d]-${behind}"
elif [ "$ahead" -gt 0 ]; then
  icon="#[fg=#f5d547,bold]󰜷 "
  suffix=" #[fg=#f5d547]+${ahead}"
elif [ "$behind" -gt 0 ]; then
  icon="#[fg=#ff4d4d,bold]󰜮 "
  suffix=" #[fg=#ff4d4d]-${behind}"
else
  icon="#[fg=#50fa7b,bold]󱍸 "
  suffix=""
fi

printf " %s#[fg=#6a8cff,nobold]%s%s$RESET " "$icon" "$branch" "$suffix"
