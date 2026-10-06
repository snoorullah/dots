#!/usr/bin/env bash
# screenshot.sh [region|full] — grim/slurp; copies to clipboard + saves.
set -uo pipefail
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
f="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
case "${1:-region}" in
  region) geo="$(slurp 2>/dev/null)" || exit 0; grim -g "$geo" "$f" ;;
  full)   grim "$f" ;;
  *) echo "usage: screenshot.sh region|full" >&2; exit 2 ;;
esac
[ -s "$f" ] && { wl-copy < "$f"; notify-send "📸 screenshot" "$(basename "$f")"; }
