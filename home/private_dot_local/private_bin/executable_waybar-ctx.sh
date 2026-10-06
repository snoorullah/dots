#!/usr/bin/env bash
TASK=/home/linuxbrew/.linuxbrew/bin/task
CTXS=(none work lab agents personal)
cur="$("$TASK" _get rc.context 2>/dev/null)"; cur="${cur:-none}"
if [ "${1:-}" = "cycle" ]; then
  i=0; for c in "${CTXS[@]}"; do [ "$c" = "$cur" ] && break; i=$((i+1)); done
  next="${CTXS[$(((i+1) % ${#CTXS[@]}))]}"
  "$TASK" context "$next" >/dev/null 2>&1
  pkill -RTMIN+8 waybar 2>/dev/null       # refresh the module
  exit 0
fi
printf '{"text":" %s","class":"ctx-%s"}\n' "$cur" "$cur"
