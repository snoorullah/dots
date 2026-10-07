#!/usr/bin/env bash
# Runs as root in a fresh distro container (repo mounted read-only at /src). Ruling R26: tests the chezmoi
# side only (no Nix build, no systemd, no sudo semantics): stale pre-existing file, no age key, gpu=mesa.
set -euo pipefail
. /etc/os-release
case " $ID ${ID_LIKE:-} " in
  *" arch "*)                pacman -Sy --noconfirm curl git sudo bash jq ;;
  *" debian "*|*" ubuntu "*) export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq curl ca-certificates git sudo bash jq ;;
  *)                         dnf install -y curl git sudo bash shadow-utils jq --allowerasing ;;
esac
id tester >/dev/null 2>&1 || useradd -m tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
rm -rf /home/tester/dots; cp -r /src /home/tester/dots; chown -R tester /home/tester/dots
su tester -c 'bash -s' <<'EOS'
set -euo pipefail
cd ~
git config --global --add safe.directory '*'
mkdir -p ~/.local/bin ~/.config/waybar; echo stale > ~/.config/waybar/config.jsonc
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
# Containers share the host's /sys/bus/pci, so a dev box with an NVIDIA GPU would render gpu=nvidia.
# Shim lspci so the container deterministically looks GPU-less (what GitHub runners are anyway).
mkdir -p ~/shim; printf '#!/bin/sh\necho "00:02.0 VGA compatible controller: Intel Corporation Generic"\n' > ~/shim/lspci; chmod +x ~/shim/lspci
# repo root carries .chezmoiroot=home, so --source is the repo root; the prompt key is the prompt text
PATH="$HOME/shim:$PATH" chezmoi init --apply --force --no-tty --source ~/dots --exclude=scripts --promptChoice Multiplexer=tmux
! grep -q stale ~/.config/waybar/config.jsonc || { echo "FAIL stale waybar config survived"; exit 1; }
test ! -e ~/.secrets || { echo "FAIL ~/.secrets exists without an age key"; exit 1; }
test -f ~/.config/hypr/hyprland.lua || { echo "FAIL hyprland.lua not rendered"; exit 1; }
! grep -q LIBVA_DRIVER_NAME ~/.config/hypr/hyprland.lua || { echo "FAIL nvidia env in a container render (want gpu=mesa)"; exit 1; }
# render (never execute) the run scripts for this distro
for f in ~/dots/home/.chezmoiscripts/*.tmpl; do
  chezmoi execute-template < "$f" > /tmp/rendered.sh
  bash -n /tmp/rendered.sh || { echo "FAIL bash -n $f"; exit 1; }
  echo "script ok: $(basename "$f")"
done
bash ~/dots/tests/in-home.sh --sentinel
echo "distro-matrix: PASS"
EOS
