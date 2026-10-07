#!/usr/bin/env bash
# Replaces each "pin:PIN" with the current HEAD commit of that repo (re-run to bump all pins).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
f=home/dot_zsh_plugins.txt; tmp=$(mktemp)
while read -r repo rest; do
  [ -z "$repo" ] && continue
  sha=$(git ls-remote "https://github.com/$repo" HEAD | cut -f1)
  printf '%-42s pin:%s\n' "$repo" "$sha"
done < <(sed -E 's/ +pin:[^ ]*//' "$f") > "$tmp"
mv "$tmp" "$f"; grep -c 'pin:[0-9a-f]\{40\}' "$f"
