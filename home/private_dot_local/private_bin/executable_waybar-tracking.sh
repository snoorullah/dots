#!/usr/bin/env bash
# waybar tracking module — shows the active timew task, truncated, with the full
# text in the tooltip. JSON built via jq so tags with quotes/specials can't break it.
TIMEW=timew
MAX=30
if [ "$("$TIMEW" get dom.active 2>/dev/null)" = "1" ]; then
  n="$("$TIMEW" get dom.active.tag.count 2>/dev/null)"; tag=""
  [ "${n:-0}" -ge 1 ] 2>/dev/null && tag="$("$TIMEW" get dom.active.tag.1 2>/dev/null)"
  tag="${tag:-tracking}"
  short="$tag"
  [ "${#tag}" -gt "$MAX" ] && short="${tag:0:$MAX}…"
  jq -cn --arg t "▶ $short" --arg tip "$tag" \
    '{text:$t, tooltip:$tip, class:"tracking-on"}'
else
  jq -cn '{text:"◦ idle", tooltip:"not tracking", class:"tracking-off"}'
fi
