#!/usr/bin/env bash
# adhd-salah-tasks.sh — create today's 5 salah tasks (tag salah, project:salah, due=iqamah)
# from ~/.config/adhd/prayer-times.conf. Idempotent: skips a prayer already created today.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
TASK="${TASK_BIN:-task}"   # taskwarrior3 (nixpkgs)
CONF="$HOME/.config/adhd/prayer-times.conf"
[ -f "$CONF" ] || { echo "no prayer-times.conf"; exit 0; }
today="$(date +%Y-%m-%d)"
while read -r name t _rest; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -z "${t:-}" ] && continue
    # Already have this prayer for today? (match tag salah + description + due date)
    existing="$($TASK rc.verbose=nothing +salah description:"$name" due.after:"${today}T00:00" due.before:"${today}T23:59" ids 2>/dev/null | tr -d '[:space:]')"
    [ -n "$existing" ] && continue
    $TASK add "$name" +salah project:salah due:"${today}T${t}" >/dev/null 2>&1 || true
done < "$CONF"
echo "salah tasks ensured for $today"
