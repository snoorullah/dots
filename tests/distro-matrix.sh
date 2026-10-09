#!/usr/bin/env bash
# Runs as root in a fresh distro container (repo mounted read-only at /src). Ruling R26: tests the chezmoi
# side only (no Nix build, no systemd, no sudo semantics): stale pre-existing file, no secrets, gpu=mesa.
# The root script is never executed: only its DOTS_PKG_LIST=1 mode, whose "required" packages are then resolved
# by the distro's package manager in a dry run (apt-get -s / dnf --assumeno / pacman -Sp). Unavailable = FAIL.
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
PATH="$HOME/shim:$PATH" chezmoi init --apply --force --no-tty --source ~/dots --exclude=scripts --promptChoice Multiplexer=tmux --promptBool "Org-managed machine (Intune/company IT owns security, patching, backups)?=false"
! grep -q stale ~/.config/waybar/config.jsonc || { echo "FAIL stale waybar config survived"; exit 1; }
test ! -e ~/.secrets || { echo "FAIL ~/.secrets created by the repo (secrets are hand-copied, never in it)"; exit 1; }
test -f ~/.config/hypr/hyprland.lua || { echo "FAIL hyprland.lua not rendered"; exit 1; }
! grep -q LIBVA_DRIVER_NAME ~/.config/hypr/hyprland.lua || { echo "FAIL nvidia env in a container render (want gpu=mesa)"; exit 1; }
# render (never execute) the run scripts for this distro
for f in ~/dots/home/.chezmoiscripts/*.tmpl; do
  chezmoi execute-template < "$f" > /tmp/rendered.sh
  bash -n /tmp/rendered.sh || { echo "FAIL bash -n $f"; exit 1; }
  echo "script ok: $(basename "$f")"
done
# dots-ops root installer (never executed): must render for this family (gpu=mesa, so the non-NixOS branch), parse,
# carry a real content hash (find|sha256sum ran in this distro) and still install the runner, units and sudoers rule.
chezmoi execute-template < ~/dots/home/.chezmoiscripts/run_onchange_after_26-dots-ops-system.sh.tmpl > /tmp/dots-ops-install.sh
bash -n /tmp/dots-ops-install.sh || { echo "FAIL bash -n dots-ops installer"; exit 1; }
grep -qE '^# dots-ops system install hash: [0-9a-f]{64}( +-)?$' /tmp/dots-ops-install.sh || { echo "FAIL dots-ops installer: no content hash rendered"; exit 1; }
for needle in '/usr/local/bin/dots-ops-run' 'visudo -cf' '/etc/sudoers.d/dots-ops' 'groupadd --system dots-ops'; do
  grep -qF -- "$needle" /tmp/dots-ops-install.sh || { echo "FAIL dots-ops installer: missing '$needle'"; exit 1; }
done
echo "dots-ops installer ok (rendered + bash -n)"
chezmoi execute-template < ~/dots/home/.chezmoiscripts/run_once_before_00-system.sh.tmpl > /tmp/root-system.sh
DOTS_PKG_LIST=1 bash /tmp/root-system.sh > /tmp/dots-pkgs.txt || { echo "FAIL root script DOTS_PKG_LIST mode"; exit 1; }
# sshd: never enabled directly; the baseline helper (drop-in, sshd -t, authorized_keys guard) does it
grep -qF "bash \"$HOME/dots/system/sshd/baseline.sh\"" /tmp/root-system.sh || { echo "FAIL root script does not run system/sshd/baseline.sh"; exit 1; }
grep -qF 'AUTH_KEYS="$HOME/.ssh/authorized_keys"' /tmp/root-system.sh || { echo "FAIL root script: no authorized_keys guard input"; exit 1; }
! grep -qE 'enable --now "?\$u"?|enable --now (ssh|sshd)\.' /tmp/root-system.sh || { echo "FAIL root script enables sshd outside the baseline helper"; exit 1; }
for needle in '40-dots-baseline.conf' '-t -f "$SSHD_CONFIG"' 'has_key' 'stop_sshd' 'sshd_config\.d/\*\.conf'; do
  grep -qF -- "$needle" ~/dots/system/sshd/baseline.sh || { echo "FAIL sshd baseline helper lacks '$needle'"; exit 1; }
done
echo "sshd baseline wired (drop-in + sshd -t + authorized_keys guard)"
cat /tmp/dots-pkgs.txt
bash ~/dots/tests/in-home.sh --sentinel
echo "distro-matrix (chezmoi side): PASS"
EOS

# ---- package dry run (as root: dnf refuses non-root) ----
read -r -a req <<<"$(sed -n 's/^required: //p' /tmp/dots-pkgs.txt)"
read -r -a opt <<<"$(sed -n 's/^optional: //p' /tmp/dots-pkgs.txt)"
[ "${#req[@]}" -gt 0 ] || { echo "FAIL no required packages listed"; exit 1; }
case " $ID ${ID_LIKE:-} " in
  *" arch "*)
    rc=0; out="$(pacman -Sp "${req[@]}" 2>&1)" || rc=$?
    [ $rc = 0 ] || { echo "$out" | grep -iE 'error|not found' ; echo "FAIL pacman -Sp: required package(s) unavailable"; exit 1; }
    have() { pacman -Si "$1" >/dev/null 2>&1; } ;;
  *" debian "*|*" ubuntu "*)
    rc=0; out="$(apt-get install -s "${req[@]}" 2>&1)" || rc=$?
    [ $rc = 0 ] || { echo "$out" | grep -E '^E:|Unable to locate|has no installation candidate'; echo "FAIL apt-get -s: required package(s) unavailable"; exit 1; }
    have() { [ -n "$(apt-cache madison "$1" 2>/dev/null)" ]; } ;;
  *)
    rc=0; out="$(dnf install --assumeno "${req[@]}" 2>&1)" || rc=$?
    if grep -qE 'No match for argument|Unable to find a match|Failed to resolve|nothing provides|^Problem' <<<"$out"; then
      echo "$out" | grep -E 'No match for argument|Unable to find a match|Failed to resolve|nothing provides|Problem'
      echo "FAIL dnf --assumeno: required package(s) unavailable"; exit 1
    fi
    grep -qiE 'Operation aborted|Nothing to do|is already installed' <<<"$out" || { echo "$out" | tail -20; echo "FAIL dnf --assumeno rc=$rc"; exit 1; }
    have() { dnf info "$1" >/dev/null 2>&1; } ;;
esac
echo "package dry run: all ${#req[@]} required packages resolve (${req[*]})"
# optional packages are installed only when present, so absence is reported, not failed
for p in "${opt[@]}"; do if have "$p"; then echo "optional available: $p"; else echo "optional absent (script skips/builds): $p"; fi; done
echo "distro-matrix: PASS"
