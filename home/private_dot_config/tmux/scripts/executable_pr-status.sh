#!/usr/bin/env bash
# Open PR count via gh CLI
# Palette: orange=#ff9e3b fg=#f8f8f2

set -eu

if ! command -v gh >/dev/null 2>&1; then
  exit 0
fi

pane_path="${1:-$(tmux display-message -p '#{pane_current_path}')}"
cd "$pane_path" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cache_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-pr-cache-$(id -u)"
mkdir -p -m 700 "$cache_dir"
cache_file="$cache_dir/$(printf %s "$repo_root" | md5sum | cut -d' ' -f1)"

if [ -f "$cache_file" ]; then
  cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt 60 ]; then
    cat "$cache_file"
    exit 0
  fi
fi

count=$(gh pr list --state open --limit 20 2>/dev/null | wc -l) || count=0
count=$(printf %s "$count" | tr -d '[:space:]')

if [ "$count" -gt 0 ]; then
  result=" #[fg=#ff9e3b,bold] #[fg=#f8f8f2,nobold]${count} "
  printf %s "$result" > "$cache_file"
  printf %s "$result"
else
  rm -f "$cache_file"
fi
