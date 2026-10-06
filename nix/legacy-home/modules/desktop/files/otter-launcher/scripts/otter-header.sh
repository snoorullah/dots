#!/usr/bin/env bash
# otter-header.sh — bluetuith-style header bar: title (left) + system stats
# (right-aligned) + a full-width divider underneath. Printed by otter header_cmd.
set -uo pipefail
export PATH="/usr/bin:/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin${PATH:+:$PATH}"
e=$'\e'
purple="${e}[38;2;189;147;249m"; pink="${e}[38;2;255;121;198m"
fg="${e}[38;2;248;248;242m"; dim="${e}[38;2;98;114;164m"; rst="${e}[0m"; bold="${e}[1m"
i_load=$'\xef\x80\x84'   # U+F004 heart
i_mem=$'\xef\x8b\x9b'    # U+F2DB microchip
i_up=$'\xef\x80\x97'     # U+F017 clock
host="$(hostname -s 2>/dev/null || echo dev)"
cores="$(nproc 2>/dev/null || echo 1)"
load="$(awk -v c="$cores" '{printf "%.0f", ($1/c)*100}' /proc/loadavg 2>/dev/null)"
mem="$(free -h --si 2>/dev/null | awk 'NR==2{print $3}')"
up="$(uptime -p 2>/dev/null | sed 's/up //; s/ weeks*/w/; s/ days*/d/; s/ hours*/h/; s/ minutes*/m/; s/,//g' | awk '{print $1}')"
cols="$(tput cols 2>/dev/null || echo 60)"

# plain (un-styled) strings, only for width measurement
lp="  ${USER}@${host}"
rp="${i_load} ${load}%  ${i_mem} ${mem}  ${i_up} ${up}  hypr"
pad=$(( cols - ${#lp} - ${#rp} - 1 )); [ "$pad" -lt 1 ] && pad=1

# header bar: user@host on the left, stats pushed to the right
printf '  %s%s%s%s%s@%s%s%s%*s%s%s %s%s%%  %s%s %s%s  %s%s %s%s  %shypr%s\n' \
  "$bold" "$purple" "$USER" "$rst" "$dim" "$fg" "$host" "$rst" \
  "$pad" "" \
  "$pink" "$i_load" "$dim" "$load" \
  "$purple" "$i_mem" "$dim" "$mem" \
  "$purple" "$i_up" "$dim" "$up" \
  "$purple" "$rst"

# full-width divider underneath
dash="$(printf '\xe2\x94\x80')"
div="$(printf '%*s' "$((cols - 2))" '' | sed "s/ /$dash/g")"
printf '  %s%s%s\n' "$dim" "$div" "$rst"
