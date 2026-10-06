#!/usr/bin/env bash
# otter-ytm.sh — YouTube Music (ytm-player) control menu for otter-launcher.
#
# Separate from otter-media.sh (playerctl/MPRIS): ytm exposes NO MPRIS, so it's
# driven via its headless subcommands. Prefix: ym. Header shows now-playing.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"
YTM="$(command -v ytm || echo "$HOME/.local/bin/ytm")"

now_header() {
    local j t a icon
    j="$("$YTM" now 2>/dev/null)" || { echo "  ytm — nothing playing"; return; }
    [ -z "$j" ] && { echo "  ytm — nothing playing"; return; }
    t="$(printf '%s' "$j" | jq -r '.track.title // "—"' 2>/dev/null)"
    a="$(printf '%s' "$j" | jq -r '(.track.artist // .track.artists[0].name // "")' 2>/dev/null)"
    icon="$(printf '%s' "$j" | jq -r 'if .is_playing then "▶" else "⏸" end' 2>/dev/null)"
    echo "  ${icon}  ${t}${a:+ — $a}"
}

toggle() {
    if [ "$("$YTM" now 2>/dev/null | jq -r '.is_playing // false' 2>/dev/null)" = "true" ]; then
        "$YTM" pause >/dev/null 2>&1
    else
        "$YTM" play >/dev/null 2>&1
    fi
}

do_search() {
    local q results pick vid
    q="$(: | fzf --print-query --prompt '  search ytm: ' | head -1)"
    [ -z "${q:-}" ] && return
    # songs only → each line: "<videoId>\t<title> — <artist>"
    results="$("$YTM" search "$q" -f songs --json -l 25 2>/dev/null \
        | jq -r '.[] | select(.videoId) | "\(.videoId)\t\(.title) — \(.artists[0].name // "?")"' 2>/dev/null)"
    [ -z "$results" ] && { notify-send "🎵 ytm" "no songs for “$q”" 2>/dev/null; return; }
    pick="$(printf '%s\n' "$results" | cut -f2- | fzf --prompt '  add to queue: ')" || return
    [ -z "${pick:-}" ] && return
    vid="$(printf '%s\n' "$results" | awk -F'\t' -v p="$pick" '$2==p{print $1; exit}')"
    [ -n "$vid" ] && "$YTM" queue add "$vid" >/dev/null 2>&1 \
        && notify-send "🎵 queued" "$pick" 2>/dev/null
}

peek_queue() {
    local q
    q="$("$YTM" queue 2>/dev/null | jq -r '.tracks[]? | "  \(.title) — \(.artist // .artists[0].name // "?")"' 2>/dev/null)"
    [ -z "$q" ] && q="  (queue empty)"
    printf '%s\n' "$q" | fzf --prompt '  up next (read-only, esc): ' --header 'queue' >/dev/null || true
}

main() {
    local play_pause=$'⏯  play/pause' next=$'⏭  next' prev=$'⏮  previous' \
          like=$'\U000f0982  like' dislike=$'\U000f0986  dislike' queue=$'  queue' \
          search=$'  search → queue' tui=$'  open ytm TUI'
    local opts chosen
    opts="$play_pause
$next
$prev
$like
$dislike
$queue
$search
$tui"
    chosen="$(printf '%s\n' "$opts" | fzf --header="$(now_header)")" || exit 0
    case "$chosen" in
        "$play_pause") toggle ;;
        "$next")       "$YTM" next >/dev/null 2>&1 ;;
        "$prev")       "$YTM" prev >/dev/null 2>&1 ;;
        "$like")       "$YTM" like >/dev/null 2>&1 ;;
        "$dislike")    "$YTM" dislike >/dev/null 2>&1 ;;
        "$queue")      peek_queue ;;
        "$search")     do_search ;;
        "$tui")        setsid -f kitty -e "$YTM" >/dev/null 2>&1 ;;
    esac
}
main
