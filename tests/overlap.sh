#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out" || { echo "OVERLAP: render failed"; exit 1; }
act=$(USER=devsupreme HOME=/home/devsupreme nix build --impure --no-link --print-out-paths "$root/nix#homeConfigurations.nvidia.activationPackage") || { echo "OVERLAP: nix build failed"; exit 1; }
ov=$(comm -12 <(cd "$out" && find . \( -type f -o -type l \) | sort) <(cd "$act/home-files" && find -L . -type f | sort))
[ -z "$ov" ] || { echo "$ov"; echo "OVERLAP above"; exit 1; }
echo "no overlap"
