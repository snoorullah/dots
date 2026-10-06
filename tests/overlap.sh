#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out"
act=$(USER=devsupreme HOME=/home/devsupreme nix build --impure --no-link --print-out-paths "$root/nix#homeConfigurations.nvidia.activationPackage")
comm -12 <(cd "$out" && find . -type f -o -type l | sort) <(cd "$act/home-files" && find -L . -type f | sort) | tee /dev/stderr | grep -q . && { echo "OVERLAP above"; exit 1; }
echo "no overlap"
