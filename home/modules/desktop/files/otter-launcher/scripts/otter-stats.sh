#!/usr/bin/env bash
# One-line otter-launcher system-info bar (Dracula truecolor + nerd-font icons).
set -uo pipefail
export PATH="/usr/bin:/bin:$HOME/.local/bin${PATH:+:$PATH}"
PUR='[38;2;189;147;249m'; PINK='[38;2;255;121;198m'; FG='[38;2;248;248;242m'; DIM='[38;2;98;114;164m'; RST='[0m'
I_LOAD=''; I_MEM=''; I_UP=''
host="$(hostname -s 2>/dev/null || echo dev)"
cores="$(nproc 2>/dev/null || echo 1)"
load="$(awk -v c="$cores" '{printf "%.0f", ($1/c)*100}' /proc/loadavg 2>/dev/null)"
mem="$(free -h --si 2>/dev/null | awk 'NR==2{print $3}')"
up="$(uptime -p 2>/dev/null | sed 's/up //; s/ weeks*/w/; s/ days*/d/; s/ hours*/h/; s/ minutes*/m/; s/,//g' | awk '{print $1}')"
printf '  %s%s%s@%s%s   %s%s %s%s%%   %s%s %s%s   %s%s %s%s   %shypr%s\n' \
  "$PUR" "$USER" "$FG" "$host" "$RST" \
  "$PINK" "$I_LOAD" "$DIM" "$load" \
  "$PUR" "$I_MEM" "$DIM" "$mem" \
  "$PUR" "$I_UP" "$DIM" "$up" \
  "$PUR" "$RST"
