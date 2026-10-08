#!/usr/bin/env bash
# adhd-block-pick.sh — fzf picker that starts a deep-focus block (Super+A).
# Replaces the quickshell block picker: +today tasks first, then the rest by urgency.
# Enter on a task → adhd-focus.sh start <id>; type text that matches nothing → adds it
# as a new +today task and starts on it. A running block is stopped first.
set -uo pipefail
TASK=task

list="$($TASK rc.verbose=nothing +PENDING export 2>/dev/null | python3 -c '
import json, sys
ts = json.load(sys.stdin)
ts.sort(key=lambda t: ("today" not in t.get("tags", []), -t.get("urgency", 0)))
for t in ts:
    mark = "★" if "today" in t.get("tags", []) else " "
    p, i, d = t.get("project"), t.get("id"), t.get("description")
    proj = f"  [{p}]" if p else ""
    print(f"{i:>4} {mark} {d}{proj}")
')"

out="$(printf '%s\n' "$list" | fzf --print-query --prompt='  focus → ' --height=100% --reverse --no-info \
    --header='enter: start block · no match: add as new +today task' \
    --color='bg:-1,bg+:-1,fg:-1,fg+:15,hl:5,hl+:13,pointer:5,prompt:5,marker:5,header:8' \
    2>/dev/null)"
query="$(sed -n 1p <<<"$out")"; pick="$(sed -n 2p <<<"$out")"

if [ -n "$pick" ]; then
    id="$(awk '{print $1}' <<<"$pick")"
elif [ -n "$query" ]; then
    id="$($TASK add +today "$query" 2>&1 | grep -oE 'Created task [0-9]+' | grep -oE '[0-9]+')"
else
    exit 0
fi
[ -z "${id:-}" ] && { notify-send "Focus" "Could not resolve a task." 2>/dev/null; exit 1; }

[ -f "$HOME/.cache/focus" ] && adhd-focus.sh stop
adhd-focus.sh start "$id"
