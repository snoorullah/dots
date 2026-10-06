#!/usr/bin/env bash
# otter-systemd.sh — systemd service manager (fzf-based otter-launcher module)
#
# Ported from rofi-systemd.sh: lists loaded service units with a
# color-coded status dot (Pango markup -> ANSI truecolor escapes), then
# offers a start/stop/restart/logs sub-menu for the selected service.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

e=$'\e'
COLOR_ACTIVE="${e}[38;2;80;250;123m"    # #50fa7b green  -- active
COLOR_INACTIVE="${e}[38;2;255;85;85m"   # #ff5555 red    -- inactive
COLOR_OTHER="${e}[38;2;241;250;140m"    # #f1fa8c yellow -- any other state
COLOR_DIM="${e}[38;2;98;114;164m"       # #6272a4 comment -- dimmed [sub]
RESET="${e}[0m"

# list_services -- "<colored dot> <name> <dim>[sub]<reset>" per loaded
# service unit, same fields/order as rofi-systemd.sh's Pango version.
list_services() {
    systemctl list-units --type=service --no-pager --no-legend --plain | \
    while read -r unit load active sub _; do
        [[ -z "$unit" ]] && continue
        local name="${unit%.service}"
        local color
        case "$active" in
            active)   color="$COLOR_ACTIVE" ;;
            inactive) color="$COLOR_INACTIVE" ;;
            *)        color="$COLOR_OTHER" ;;
        esac
        printf '%s●%s %s %s[%s]%s\n' "$color" "$RESET" "$name" "$COLOR_DIM" "$sub" "$RESET"
    done
}

services="$(list_services)"
if [[ -z "$services" ]]; then
    notify-send "Systemd" "No services found" -u normal
    exit 0
fi

chosen="$(echo "$services" | fzf --ansi --header='systemd services')"
[[ -z "$chosen" ]] && exit 0

# Strip ANSI escapes, then take the token after the dot -- that's the
# service name (field 1 is the "●" dot character).
name="$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$chosen" | awk '{print $2}')"
[[ -z "$name" ]] && exit 0

action="$(printf 'start\nstop\nrestart\nview logs\n' | fzf --header="$name")"
[[ -z "$action" ]] && exit 0

case "$action" in
    start)
        pkexec systemctl start "${name}.service"
        notify-send "Systemd" "Started: $name" -t 3000
        ;;
    stop)
        pkexec systemctl stop "${name}.service"
        notify-send "Systemd" "Stopped: $name" -t 3000
        ;;
    restart)
        pkexec systemctl restart "${name}.service"
        notify-send "Systemd" "Restarted: $name" -t 3000
        ;;
    "view logs")
        setsid -f kitty --config "$HOME/.config/kitty/otter.conf" -e journalctl -u "${name}.service" -f --no-pager >/dev/null 2>&1
        ;;
esac
