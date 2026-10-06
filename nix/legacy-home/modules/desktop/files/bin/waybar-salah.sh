#!/usr/bin/env bash
# waybar salah-runway: the "→ <Prayer> <HH:MM>" tail of adhd-focus.sh status.
s="$("$HOME/.local/bin/adhd-focus.sh" status 2>/dev/null)"
runway="${s##*→ }"                       # "Dhuhr 13:30"
[ -n "$runway" ] && [ "$runway" != "$s" ] && runway="→ $runway" || runway="—"
printf '{"text":"🕌 %s","tooltip":"%s","class":"salah"}\n' "$runway" "${s:-no prayer times}"
