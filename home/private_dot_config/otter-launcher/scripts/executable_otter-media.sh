#!/usr/bin/env bash
# otter-media.sh — media playback controls via playerctl (fzf-based otter-launcher module)
#
# Same playerctl calls as rofi-media.sh, ported to fzf. The header shows
# the currently-playing artist/title (or a fallback if nothing is playing)
# so there's still "now playing" feedback without a full player window.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

# get_track_info -- "Artist - Title", falling back gracefully when no
# MPRIS player is running (playerctl exits non-zero in that case).
get_track_info() {
    local artist title
    artist="$(playerctl metadata artist 2>/dev/null)"
    title="$(playerctl metadata title 2>/dev/null)"
    echo "${artist:-Unknown} - ${title:-No Track}"
}

# Icons match rofi-media.sh exactly (same codepoints as the reference script).
prev=$'󰒮  previous'
play_pause=$'󰐎  play/pause'
next=$'󰒭  next'
shuffle=$'󰒟  shuffle'
loop=$'󰑖  loop'

options="$prev
$play_pause
$next
$shuffle
$loop"

track_info="$(get_track_info)"
chosen="$(echo "$options" | fzf --header=$' '"$track_info")"

case "$chosen" in
    "$prev")        playerctl previous ;;
    "$play_pause")  playerctl play-pause ;;
    "$next")        playerctl next ;;
    "$shuffle")     playerctl shuffle toggle ;;
    "$loop")        playerctl loop ;;
esac
