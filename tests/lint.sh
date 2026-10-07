#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out" || { echo "LINT: render failed"; exit 1; }
pat='/home/devsupreme|/home/linuxbrew|/snap/|\.cargo/bin|/run/user/1001|/usr/bin/(task|timew|python3|kubectl|tmux|gh|kitty|swww)\b|kitty --|kitten|\.config/kitty|\bkitty\b *$|"kitty"|mako|\brofi\b|oh-my-zsh'
if grep -rIlE "$pat" "$out"; then echo "LINT: files above contain forbidden patterns"; exit 1; fi
grep -q "^keybind = clear" "$out/.config/ghostty/config" || { echo "LINT: ghostty config lacks keybind = clear"; exit 1; }
echo "lint ok"
