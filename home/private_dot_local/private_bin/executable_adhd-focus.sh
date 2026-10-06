#!/usr/bin/env bash
# adhd-focus.sh — Flowtime deep-focus daemon (count-up, prayer-scaffolded).
#
# No pomodoro: blocks count up and never force-stop. A gentle, dismissible
# nudge fires only past ~90 min. Next salah is read from prayer-times.conf.
#
# Usage:
#   adhd-focus.sh start <taskid>   begin a count-up timew interval (via task start)
TASK="${TASK_BIN:-/home/linuxbrew/.linuxbrew/bin/task}"  # taskwarrior (go-task shadows `task` in PATH)
#   adhd-focus.sh stop             stop the active focus block
#   adhd-focus.sh status           print elapsed + minutes to next salah
#   adhd-focus.sh nudge            fire a dismissible notify-send if >=90m elapsed
set -euo pipefail

CONF="$HOME/.config/adhd/prayer-times.conf"
STATE="$HOME/.cache/focus"

# next_prayer — first prayer in the config whose time is after now; else Fajr tmrw.
next_prayer() {
    local now n t rest
    now=$(date +%H%M)
    if [ -f "$CONF" ]; then
        while read -r n t rest; do
            case "$n" in ''|'#'*) continue ;; esac
            [ -z "$t" ] && continue
            if [ "${t/:/}" -gt "$now" ] 2>/dev/null; then
                echo "$n $t"
                return
            fi
        done < "$CONF"
    fi
    echo "Fajr (tmrw)"
}

case "${1:-status}" in
    start)
        "$TASK" start "${2:?taskid}" >/dev/null 2>&1
        mkdir -p "$(dirname "$STATE")"
        printf '%s %s\n' "$(date +%s)" "${2}" > "$STATE"
        notify-send "Deep block started" "→ $(next_prayer)" 2>/dev/null || true
        ;;
    stop)
        "$TASK" stop "$(awk '{print $2}' "$STATE" 2>/dev/null)" >/dev/null 2>&1 || true
        rm -f "$STATE"
        ;;
    status)
        if [ -f "$STATE" ]; then
            s=$(awk '{print $1}' "$STATE")
            printf 'block %dm · → %s\n' $(( ($(date +%s) - s) / 60 )) "$(next_prayer)"
        else
            printf 'idle · → %s\n' "$(next_prayer)"
        fi
        ;;
    nudge)
        if [ -f "$STATE" ]; then
            s=$(awk '{print $1}' "$STATE")
            if [ $(( ($(date +%s) - s) / 60 )) -ge 90 ]; then
                notify-send "Long block — breathe?" \
                    "Dismiss to keep going · next: $(next_prayer)" 2>/dev/null || true
            fi
        fi
        ;;
esac
