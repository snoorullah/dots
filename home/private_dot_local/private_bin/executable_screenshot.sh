#!/usr/bin/env bash
# screenshot.sh [region|full]
# Uses HyprCapture (hyprcapture <region|fullscreen>; CLI UNVERIFIED, upstream is a Lua plugin) when installed; otherwise grim/slurp -> file + clipboard + notification.
set -uo pipefail
mode="${1:-region}"
case "$mode" in region|full) ;; *) echo "usage: screenshot.sh region|full" >&2; exit 2 ;; esac

if command -v hyprcapture >/dev/null 2>&1; then
  case "$mode" in
    region) exec hyprcapture region ;;
    full)   exec hyprcapture fullscreen ;;
  esac
fi

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
