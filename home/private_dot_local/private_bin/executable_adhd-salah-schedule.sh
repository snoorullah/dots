#!/usr/bin/env bash
# adhd-salah-schedule.sh — schedule today's 5 salah nudges as transient user timers at each
# iqamah time. Re-run daily (times change). Skips prayer times already past for today.
set -uo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
CONF="$HOME/.config/adhd/prayer-times.conf"
[ -f "$CONF" ] || exit 0
now="$(date +%H%M)"
while read -r name t _rest; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -z "${t:-}" ] && continue
    hhmm="${t/:/}"
    (( 10#$hhmm <= 10#$now )) && continue   # already passed today — force base-10 so leading-zero HHMM (e.g. 0508) isn't parsed as octal
    # One-shot for TODAY (dated OnCalendar self-cleans after it elapses) + a date-stamped unit
    # name, so tomorrow's re-run arms the NEW iqamah time instead of colliding with a frozen unit.
    systemd-run --user --quiet \
        --on-calendar="$(date +%Y-%m-%d) ${t}:00" \
        --timer-property=AccuracySec=30s \
        --timer-property=RemainAfterElapse=no \
        --unit="adhd-salah-nudge-${name}-$(date +%Y%m%d)" \
        "$HOME/.local/bin/adhd-salah-nudge.sh" "$name" 2>/dev/null || true
done < "$CONF"
echo "salah nudges scheduled"
