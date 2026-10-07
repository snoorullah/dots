#!/usr/bin/env bash
# Writes nix/pkgs/tmux-plugins.json for every @plugin in tmux.conf
# (rev: plugins.lock, else the live checkout under ~/tmux-config/plugins, else upstream HEAD).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
cfg=home/private_dot_config/tmux; live="$HOME/tmux-config/plugins"; out=nix/pkgs/tmux-plugins.json
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
printf '[' > "$tmp"; sep=
while read -r slug; do
  owner=${slug%/*}; repo=${slug#*/}
  # tmux-thumbs needs a compiled binary: nix/pkgs/overlay.nix links the prebuilt nixpkgs package instead.
  [ "$repo" != tmux-thumbs ] || continue
  rev=$(awk -v r="$repo" '$1==r{print $2}' $cfg/plugins.lock)
  src=lock
  [ -n "$rev" ] || { rev=$(git -C "$live/$repo" rev-parse HEAD 2>/dev/null || true); src=live; }
  [ -n "$rev" ] || { rev=$(git ls-remote "https://github.com/$slug" HEAD | cut -f1); src=upstream-HEAD; }
  [ -n "$rev" ] || { echo "no rev for $slug" >&2; exit 1; }
  echo "$repo $rev ($src)" >&2
  hash=$(nix run nixpkgs#nix-prefetch-github -- --rev "$rev" "$owner" "$repo" | nix run nixpkgs#jq -- -r .hash)
  printf '%s{"dir":"%s","owner":"%s","repo":"%s","rev":"%s","hash":"%s"}' "$sep" "$repo" "$owner" "$repo" "$rev" "$hash" >> "$tmp"; sep=,
done < <(grep -oE "@plugin '[^']+'" $cfg/tmux.conf | sed -E "s/@plugin '([^']+)'/\1/")
printf ']\n' >> "$tmp"
nix run nixpkgs#jq -- . "$tmp" > $out
n=$(nix run nixpkgs#jq -- length $out)
echo "$n"
[ "$n" -eq 14 ] || { echo "expected 14 pinned plugins (15 @plugins minus tmux-thumbs), got $n" >&2; exit 1; }
