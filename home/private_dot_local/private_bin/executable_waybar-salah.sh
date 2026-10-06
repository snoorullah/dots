#!/usr/bin/env bash
# waybar salah-runway: the "→ <Prayer> <HH:MM>" tail of adhd-focus.sh status;
# tooltip adds today's entries from ~/.local/share/adhd/salah.log (Super+Shift+; logs).
s="$("$HOME/.local/bin/adhd-focus.sh" status 2>/dev/null)"
runway="${s##*→ }"                       # "Dhuhr 13:30"
[ -n "$runway" ] && [ "$runway" != "$s" ] && runway="→ $runway" || runway="—"
today="$(awk -F'\t' -v d="$(date +%Y-%m-%d)" '$1==d{printf "%s%s: %s", (n++?"\\n":""), $2, $3}' "$HOME/.local/share/adhd/salah.log" 2>/dev/null)"
printf '{"text":"🕌 %s","tooltip":"%s\\n%s","class":"salah"}\n' "$runway" "${s:-no prayer times}" "${today:-nothing logged today}"
