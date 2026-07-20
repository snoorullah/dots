#!/usr/bin/env bash
# adhd-salah-pick.sh [PrayerName] — mark a salah's status with ONE key and complete it.
# Picks the target task: the named prayer's pending task today, else the nearest-due pending salah.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
TASK="${TASK_BIN:-task}"   # taskwarrior3 (nixpkgs) — data lives in ~/.task/taskchampion.sqlite3
today="$(date +%Y-%m-%d)"
want="${1:-}"
# NOTE: uses `_ids` (one-id-per-line), not `ids` (which compresses matches into ranges like
# "3-12" that the tr/grep parser below can't split) — verified 2026-07-18: with the real
# backlog of 10 pending salah tasks, `ids` returned "3-12" and this pipeline silently returned
# empty, so the fallback ("nearest-due pending salah") never found anything to log.
sel_id() { $TASK rc.verbose=nothing +salah +PENDING "$@" _ids 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' | head -1; }
id=""
[ -n "$want" ] && id="$(sel_id description:"$want" due.after:"${today}T00:00" due.before:"${today}T23:59")"
[ -z "$id" ] && id="$(sel_id due.before:"${today}T23:59")"
[ -z "$id" ] && { notify-send "🕌 Salah" "No pending prayer to log." 2>/dev/null; exit 0; }
desc="$($TASK _get "${id}.description" 2>/dev/null)"
choice="$(printf 'jamaah\nalone\nqaza\nmissed\n' | fzf --prompt="  $desc → " --height=100% --reverse --no-info \
    --color='bg:-1,bg+:-1,fg:-1,fg+:15,hl:5,hl+:13,pointer:5,prompt:5,marker:5,header:8' \
    2>/dev/null || true)"
[ -z "$choice" ] && exit 0
if [ "$choice" = "missed" ]; then
    $TASK "$id" modify salah_status:missed >/dev/null 2>&1
    $TASK "$id" done >/dev/null 2>&1
else
    $TASK "$id" modify salah_status:"$choice" >/dev/null 2>&1
    $TASK "$id" done >/dev/null 2>&1
fi
notify-send "🕌 $desc" "logged: $choice" 2>/dev/null || true
