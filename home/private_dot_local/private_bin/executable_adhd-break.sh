#!/usr/bin/env bash
# adhd-break.sh (Super+Shift+P) — deliberate break: pause the active task as a `break`
# interval, blank the monitor, and lock. Unlock ends it (see adhd-break-end.sh).
set -uo pipefail
export PATH="/usr/bin:$HOME/.local/bin:$PATH"
TIMEW=/usr/bin/timew
STATE="$HOME/.cache/adhd/break-active"
mkdir -p "$(dirname "$STATE")"

# Record whether a task interval is currently active (so we know a break interrupted work).
if "$TIMEW" get dom.active >/dev/null 2>&1; then
    "$TIMEW" get dom.active.json 2>/dev/null > "$STATE" || echo '{}' > "$STATE"
else
    echo '{}' > "$STATE"
fi
# Start the break interval (timew tracks one interval at a time — this pauses any task).
"$TIMEW" start break >/dev/null 2>&1 || true
# Blank the monitor, then lock via logind (hypridle -> hyprlock; Stage-1 daemon logs Lock).
HIS=$(find /run/user/1001/hypr -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | head -1)
HYPRLAND_INSTANCE_SIGNATURE="$HIS" hyprctl dispatch dpms off >/dev/null 2>&1 || true
loginctl lock-session >/dev/null 2>&1 || true
