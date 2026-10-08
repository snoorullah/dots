#!/usr/bin/env bash
# usage: tests/render.sh <data.toml> <out-dir>  — renders chezmoi source into out-dir (no scripts, no secrets)
set -euo pipefail
root="$(git rev-parse --show-toplevel)"; data="$1"; out="$2"
mkdir -p "$out"
cfg="$(mktemp --suffix=.toml)"; trap 'rm -f "$cfg"' EXIT; cat "$data" > "$cfg"
HOME="$out" chezmoi apply --source "$root/home" --destination "$out" --config "$cfg" \
  --exclude=scripts,encrypted --force --no-tty
