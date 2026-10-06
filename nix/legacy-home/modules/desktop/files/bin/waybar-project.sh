#!/usr/bin/env bash
f="$HOME/.cache/adhd/active-project"
[ -s "$f" ] || { printf '{"text":"","class":"project"}\n'; exit 0; }
proj="$(cat "$f")"
branch=""
[ -d "$HOME/work/$proj/.git" ] && branch="$(git -C "$HOME/work/$proj" branch --show-current 2>/dev/null)"
printf '{"text":" %s%s","class":"project"}\n' "$proj" "${branch:+  $branch}"
