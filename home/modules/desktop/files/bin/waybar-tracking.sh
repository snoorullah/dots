#!/usr/bin/env bash
TIMEW=/usr/bin/timew
if [ "$("$TIMEW" get dom.active 2>/dev/null)" = "1" ]; then
  n="$("$TIMEW" get dom.active.tag.count 2>/dev/null)"; tag=""
  [ "${n:-0}" -ge 1 ] 2>/dev/null && tag="$("$TIMEW" get dom.active.tag.1 2>/dev/null)"
  printf '{"text":"▶ %s","class":"tracking-on"}\n' "${tag:-tracking}"
else
  printf '{"text":"◦ idle","class":"tracking-off"}\n'
fi
