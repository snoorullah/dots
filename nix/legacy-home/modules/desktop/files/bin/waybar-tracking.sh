#!/usr/bin/env bash
# TIMEW path patched Phase 5 (dotfiles/NixOS port): timewarrior provides bare
# `timew` on PATH via home.packages (modules/timetrack.nix) — was hardcoded to
# /usr/bin/timew on the live (non-Nix) box.
TIMEW=timew
if [ "$("$TIMEW" get dom.active 2>/dev/null)" = "1" ]; then
  n="$("$TIMEW" get dom.active.tag.count 2>/dev/null)"; tag=""
  [ "${n:-0}" -ge 1 ] 2>/dev/null && tag="$("$TIMEW" get dom.active.tag.1 2>/dev/null)"
  printf '{"text":"▶ %s","class":"tracking-on"}\n' "${tag:-tracking}"
else
  printf '{"text":"◦ idle","class":"tracking-off"}\n'
fi
