#!/usr/bin/env bash
# adhd-break-end.sh — run by hypridle unlock_cmd. Ends a deliberate break ONLY if a
# `break` interval is currently active (so a plain idle-lock unlock never stops a task).
set -uo pipefail
export PATH="/usr/bin:$HOME/.local/bin:$PATH"
TIMEW=/usr/bin/timew
STATE="$HOME/.cache/adhd/break-active"
HIS=$(find /run/user/1001/hypr -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | head -1)
HYPRLAND_INSTANCE_SIGNATURE="$HIS" hyprctl dispatch dpms on >/dev/null 2>&1 || true
# Stop ONLY if a `break` interval is active — gate strictly on the active
# interval's TAGS (never the JSON blob; its annotation text could contain the
# word "break" and wrongly stop a real task on an idle-lock unlock).
n="$("$TIMEW" get dom.active.tag.count 2>/dev/null | tr -dc '0-9')"
is_break=0
if [ -n "$n" ]; then
    i=1
    while [ "$i" -le "$n" ]; do
        [ "$("$TIMEW" get "dom.active.tag.$i" 2>/dev/null)" = "break" ] && { is_break=1; break; }
        i=$((i+1))
    done
fi
[ "$is_break" = 1 ] && "$TIMEW" stop >/dev/null 2>&1 || true
rm -f "$STATE"
