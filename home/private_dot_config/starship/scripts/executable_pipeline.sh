#!/bin/bash
# Pipeline status for starship prompt
# Shows PR review status + CI check status
# Cached per branch for 60 seconds

CACHE_DIR="/tmp/starship-pipeline"
mkdir -p "$CACHE_DIR" 2>/dev/null

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
CACHE_FILE="$CACHE_DIR/${repo}-${branch//\//_}"

# Use cache if < 60s old
if [ -f "$CACHE_FILE" ]; then
  age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  if [ "$age" -lt 60 ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Fetch PR data from GitHub
json=$(gh pr view --json reviewDecision,statusCheckRollup 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$json" ]; then
  : > "$CACHE_FILE"
  exit 0
fi

# PR review status
review=$(echo "$json" | jq -r '.reviewDecision // "PENDING"')
case "$review" in
  APPROVED) r="✔";;
  CHANGES_REQUESTED) r="✘";;
  *) r="◯";;
esac

# CI check status
ci=$(echo "$json" | jq -r '
  .statusCheckRollup // [] |
  if length == 0 then "none"
  elif all(.conclusion == "SUCCESS") then "pass"
  elif any(.conclusion == "FAILURE") then "fail"
  else "pending" end
')
case "$ci" in
  pass) c=" ●";;
  fail) c=" ✘";;
  none) c="";;
  *) c=" ◌";;
esac

result="${r}${c}"
echo "$result" > "$CACHE_FILE"
echo "$result"
