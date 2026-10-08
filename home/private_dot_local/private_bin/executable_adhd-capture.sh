#!/usr/bin/env bash
# adhd-capture.sh — frictionless (<=2-step) capture into the Obsidian vault inbox.
# One fzf line -> POST to today's daily note `## Inbox` via Obsidian REST.
# If the text starts with `t:` / `task:`, also add a taskwarrior task in the
# current context.
set -euo pipefail

# Load secrets (OBSIDIAN_REST_TOKEN) if present.
TASK=task  # taskwarrior (go-task shadows `task` in PATH)
[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"

# Current context (default: personal).
CTX=$(cat "$HOME/.cache/ctx" 2>/dev/null || echo personal)

text=$(fzf --print-query --prompt='  capture › ' --height=100% --reverse --no-info < /dev/null | head -1) || true
[ -n "$text" ] || exit 0

note="journal/daily/$(date +%d-%m-%Y).md"
body="- $(date +%H:%M) $text"

curl -sk -X POST "https://127.0.0.1:27124/vault/$note" \
    -H "Authorization: Bearer ${OBSIDIAN_REST_TOKEN:-}" \
    -H "Content-Type: text/markdown" -H "Heading: Inbox" --data "$body" >/dev/null || true

case "$text" in
    t:*|task:*) "$TASK" add project:"$CTX" "${text#*:}" +next >/dev/null 2>&1 || true ;;
esac

notify-send "Captured" "$text" 2>/dev/null || true
