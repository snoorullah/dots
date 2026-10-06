#!/usr/bin/env bash
# waybar-project.sh — project + branch of whatever terminal pane is focused.
#   kitty running tmux → that client's active pane cwd (tty match)
#   plain kitty        → cwd of the terminal's foreground process
#   path in ~/work/<p> → "<p>  <branch>"; tmux pane outside ~/work → session name
#   non-terminal focus → keep the last value (cache), so the bar doesn't blank
# The Super+P picker (otter-projects.sh) still seeds the cache.
cache="$HOME/.cache/adhd/active-project"
W="$HOME/work"
emit() { printf '{"text":"%s","class":"project","tooltip":"%s"}\n' "$1" "$2"; exit 0; }

path="" sess=""
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); export HYPRLAND_INSTANCE_SIGNATURE
fi
read -r cls pid < <(hyprctl activewindow -j 2>/dev/null | python3 -c 'import json,sys
try: c=json.load(sys.stdin); print(c.get("class","-"), c.get("pid",0))
except Exception: print("- 0")')

if [ "$cls" = kitty ] && [ "${pid:-0}" -gt 0 ]; then
  for child in $(ps --ppid "$pid" -o pid= 2>/dev/null); do
    tty=$(ps -o tty= -p "$child" | tr -d ' ')
    [ -n "$tty" ] && [ "$tty" != "?" ] || continue
    line=$(tmux list-clients -F '#{client_tty}	#{session_name}	#{pane_current_path}' 2>/dev/null | awk -F'\t' -v t="/dev/$tty" '$1==t{print; exit}')
    if [ -n "$line" ]; then
      sess=$(cut -f2 <<<"$line"); path=$(cut -f3 <<<"$line")
    else
      fg=$(awk '{print $8}' "/proc/$child/stat" 2>/dev/null)   # tpgid = foreground pgrp
      [ -n "$fg" ] && [ "$fg" -gt 0 ] && path=$(readlink "/proc/$fg/cwd" 2>/dev/null)
      [ -z "$path" ] && path=$(readlink "/proc/$child/cwd" 2>/dev/null)
    fi
    break
  done
fi

if [ -n "$path" ] || [ -n "$sess" ]; then
  case "$path/" in
    "$W"/?*/) proj=${path#"$W"/}; proj=${proj%%/*} ;;
    *) proj="" ;;
  esac
  mkdir -p "${cache%/*}"
  if [ -n "$proj" ]; then printf '%s' "$proj" > "$cache"
  elif [ -n "$sess" ]; then printf '@%s' "$sess" > "$cache"
  else : > "$cache"; fi
fi

val=$(cat "$cache" 2>/dev/null)
[ -z "$val" ] && emit "" ""
case "$val" in
  @*) emit " ${val#@}" "tmux session ${val#@}" ;;
esac
branch=$(git -C "$W/$val" branch --show-current 2>/dev/null)
emit " $val${branch:+  $branch}" "$W/$val"
