#!/usr/bin/env bash
# adhd-capture.sh — frictionless (<=2-step) capture into the Obsidian vault inbox.
# One rofi line -> POST to today's daily note `## Inbox` via Obsidian REST.
# If the text starts with `t:` / `task:`, also add a taskwarrior task in the
# current context.
set -euo pipefail

# Load secrets (OBSIDIAN_REST_TOKEN) if present.
TASK="${TASK_BIN:-/home/linuxbrew/.linuxbrew/bin/task}"  # taskwarrior (go-task shadows `task` in PATH)
[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"

# Current context (default: personal).
CTX=$(cat "$HOME/.cache/ctx" 2>/dev/null || echo personal)

# Theme is best-effort: only pass -theme if the file exists (rofi is mocked in tests).
theme="$HOME/.config/rofi/themes/simple.rasi"
if [ -f "$theme" ]; then
    text=$(printf '' | rofi -dmenu -p "Capture" -theme "$theme" 2>/dev/null) || exit 0
else
    text=$(printf '' | rofi -dmenu -p "Capture" 2>/dev/null) || exit 0
fi

[ -z "$text" ] && exit 0

note="journal/daily/$(date +%d-%m-%Y).md"
body="- $(date +%H:%M) $text"

curl -sk -X POST "https://127.0.0.1:27124/vault/$note" \
    -H "Authorization: Bearer ${OBSIDIAN_REST_TOKEN:-}" \
    -H "Content-Type: text/markdown" -H "Heading: Inbox" --data "$body" >/dev/null || true

case "$text" in
    t:*|task:*) "$TASK" add project:"$CTX" "${text#*:}" +next >/dev/null 2>&1 || true ;;
esac

notify-send "Captured" "$text" 2>/dev/null || true
