#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out" || { echo "LINT: render failed"; exit 1; }
pat='/home/devsupreme|/home/linuxbrew|/snap/|\.cargo/bin|/run/user/1001|/usr/bin/(task|timew|python3|kubectl|tmux|gh|kitty|swww)\b|kitty --|kitten|\.config/kitty|\bkitty\b *$|"kitty"|mako|\brofi\b|oh-my-zsh'
if grep -rIlE "$pat" "$out"; then echo "LINT: files above contain forbidden patterns"; exit 1; fi
grep -q "^keybind = clear" "$out/.config/ghostty/config" || { echo "LINT: ghostty config lacks keybind = clear"; exit 1; }
# non-NixOS PATH keeps the sbin dirs; NixOS PATH has the system profile + setuid wrappers (no /usr on NixOS)
for f in .config/environment.d/10-dots-path.conf .config/hypr/hyprland.lua; do
  grep -q '/usr/sbin' "$out/$f" || { echo "LINT: $f (nvidia render) PATH lacks /usr/sbin"; exit 1; }
done
nixos="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nixos-tmux.toml" "$nixos" || { echo "LINT: nixos render failed"; exit 1; }
if grep -rIlE "$pat" "$nixos"; then echo "LINT: files above (nixos render) contain forbidden patterns"; exit 1; fi
for f in .config/environment.d/10-dots-path.conf .config/hypr/hyprland.lua; do
  grep -q '/run/current-system/sw/bin' "$nixos/$f" || { echo "LINT: $f (nixos render) PATH lacks /run/current-system/sw/bin"; exit 1; }
  grep -q '/run/wrappers/bin' "$nixos/$f" || { echo "LINT: $f (nixos render) PATH lacks /run/wrappers/bin"; exit 1; }
done
# R28: everything uses ~/.nix-profile, NixOS included (home-manager.useUserPackages = false)
if grep -rIl '/etc/profiles/per-user' "$out" "$nixos"; then echo "LINT: files above use /etc/profiles/per-user (R28: use ~/.nix-profile)"; exit 1; fi
echo "lint ok"
