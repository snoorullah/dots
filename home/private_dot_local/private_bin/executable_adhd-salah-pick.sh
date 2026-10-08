#!/usr/bin/env bash
# adhd-salah-pick.sh [PrayerName] — log a salah's status with ONE key (Super+Shift+;).
# Plain-file log, no taskwarrior: appends "date<TAB>prayer<TAB>status<TAB>logged-at" to
# ~/.local/share/adhd/salah.log. Target: the named prayer, else today's earliest prayer whose
# iqamah (prayer-times.conf) has passed and isn't logged yet, else the next upcoming one.
set -uo pipefail
CONF="$HOME/.config/adhd/prayer-times.conf"
LOG="$HOME/.local/share/adhd/salah.log"
mkdir -p "${LOG%/*}"; touch "$LOG"
today="$(date +%Y-%m-%d)"; now="$(date +%H%M)"
want="${1:-}"

logged() { grep -q "^${today}	$1	" "$LOG"; }
target="" upcoming=""
while read -r name t _rest; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -z "${t:-}" ] && continue
    if [ -n "$want" ]; then [ "${name,,}" = "${want,,}" ] && target="$name"; continue; fi
    logged "$name" && continue
    if (( 10#${t/:/} <= 10#$now )); then target="$name"; break; fi
    [ -z "$upcoming" ] && upcoming="$name"
done < "$CONF"
target="${target:-$upcoming}"
[ -z "$target" ] && { notify-send "🕌 Salah" "All of today's prayers are logged." 2>/dev/null; exit 0; }

choice="$(printf 'jamaah\nalone\nqaza\nmissed\n' | fzf --prompt="  $target → " --height=100% --reverse --no-info \
    --color='bg:-1,bg+:-1,fg:-1,fg+:15,hl:5,hl+:13,pointer:5,prompt:5,marker:5,header:8' \
    2>/dev/null || true)"
[ -z "$choice" ] && exit 0
printf '%s\t%s\t%s\t%s\n' "$today" "$target" "$choice" "$(date +%Y-%m-%dT%H:%M)" >> "$LOG"
notify-send "🕌 $target" "logged: $choice" 2>/dev/null || true
