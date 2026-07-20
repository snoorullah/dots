#!/usr/bin/env bash
# otter-power.sh — power menu (fzf-based otter-launcher module)
#
# Same actions/commands as rofi-power.sh, ported to fzf: lock and suspend
# fire immediately, reboot/shutdown/logout go through a Yes/No confirm
# first so a stray Enter can't take down the session.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

# Icons match rofi-power.sh exactly (same codepoints, same glyphs).
lock=$'  lock'
suspend=$'⏾  suspend'
logout=$'\U000f0343  logout'
reboot=$'  reboot'
shutdown=$'⏻  shutdown'

options="$lock
$suspend
$logout
$reboot
$shutdown"

# confirm_action — Yes/No fzf gate for destructive actions.
# Parameters: $1 — message shown in the header.
# Returns: 0 if "Yes" was chosen, 1 otherwise (including Esc/no selection).
confirm_action() {
    local answer
    answer="$(printf 'Yes\nNo\n' | fzf --header="$1" --prompt='  ')"
    [[ "$answer" == "Yes" ]]
}

chosen="$(echo "$options" | fzf --header=$'⏻ power')"

case "$chosen" in
    "$lock")
        setsid -f hyprlock >/dev/null 2>&1
        ;;
    "$suspend")
        systemctl suspend
        ;;
    "$logout")
        confirm_action 'Logout?' && hyprctl dispatch exit
        ;;
    "$reboot")
        confirm_action 'Reboot?' && systemctl reboot
        ;;
    "$shutdown")
        confirm_action 'Shutdown?' && systemctl poweroff
        ;;
esac
