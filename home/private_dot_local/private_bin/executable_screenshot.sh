#!/usr/bin/env bash
# screenshot.sh [region|full]
# grim/slurp -> timestamped file + clipboard + notification. (HyprCapture, a Hyprland plugin, is
# called directly from the Print binds in hyprland.lua when loaded; this is the fallback.)
set -uo pipefail
mode="${1:-region}"
case "$mode" in region|full) ;; *) echo "usage: screenshot.sh region|full" >&2; exit 2 ;; esac

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$dir"
f="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
case "$mode" in
  region) geo="$(slurp 2>/dev/null)" || exit 0; grim -g "$geo" "$f" ;;
  full)   grim "$f" ;;
esac
if [ -s "$f" ]; then
  wl-copy < "$f"
  notify-send "screenshot" "$f"
fi
