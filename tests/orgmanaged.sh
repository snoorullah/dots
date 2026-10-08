#!/usr/bin/env bash
# usage: tests/orgmanaged.sh — the orgManaged profile (company IT owns security/patching/backups):
#  - the dots-ops root installer renders to a removal-only script (no install, no sudoers write, no visudo),
#    while the personal render still installs everything
#  - the root-layer package list (DOTS_PKG_LIST=1) drops the packages that exist only for dots-ops
#  - the user timers/units/config for the org profile reference nothing that is not deployed
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
bad() { echo "ORG: $*"; fail=1; }
render() {   # <data.toml> <script.tmpl> <out>
  HOME="$work/home" chezmoi execute-template --source "$root/home" --config "$1" < "$root/home/.chezmoiscripts/$2" > "$3" \
    || { bad "render failed: $2 ($1)"; return 1; }
  bash -n "$3" || { bad "bash -n failed: $2 ($1)"; return 1; }
}
org="$root/tests/data-workpc-ubuntu.toml"; per="$root/tests/data-mesa-tmux.toml"

# ---- root installer ----
render "$org" run_onchange_after_26-dots-ops-system.sh.tmpl "$work/org-install.sh" && {
  f="$work/org-install.sh"
  grep -q visudo "$f" && bad "org installer mentions visudo"
  grep -qE 'install .*(/etc/sudoers\.d|/usr/local|/etc/systemd|/etc/udev|/etc/dots-ops)' "$f" && bad "org installer installs something"
  grep -qE 'groupadd|usermod|enable --now|apt-get|pacman|dnf' "$f" && bad "org installer adds a group/unit/package"
  grep -qF 'rm -f /etc/sudoers.d/dots-ops' "$f" || bad "org installer lacks the sudoers removal"
  for need in 'rm -rf /usr/local/lib/dots-ops /etc/dots-ops' 'rm -f /usr/local/bin/dots-ops-run /usr/local/bin/dots-ops-job' \
              'disable --now' '/etc/udev/rules.d/*dots-ops*' 'groupdel dots-ops'; do
    grep -qF -- "$need" "$f" || bad "org installer lacks removal step: $need"
  done
  grep -q '/var/lib/dots-ops' "$f" && ! grep -qE '^#.*/var/lib/dots-ops' "$f" && bad "org installer touches /var/lib/dots-ops outside a comment"
  grep -qE 'rm .*/var/lib/dots-ops' "$f" && bad "org installer deletes /var/lib/dots-ops (must be left alone)"
}
render "$per" run_onchange_after_26-dots-ops-system.sh.tmpl "$work/per-install.sh" && {
  for need in '/usr/local/bin/dots-ops-run' 'visudo -cf' '/etc/sudoers.d/dots-ops' 'groupadd --system dots-ops'; do
    grep -qF -- "$need" "$work/per-install.sh" || bad "personal installer lost: $need"
  done
}

# ---- root-layer packages (host distro; skipped when the host is not a supported family) ----
pkgs=(pacman-contrib fwupd lynis ufw arch-audit unattended-upgrades power-profiles-daemon dnf-plugins-core firewalld tuned-ppd)
if render "$org" run_once_before_00-system.sh.tmpl "$work/org-sys.sh" && render "$per" run_once_before_00-system.sh.tmpl "$work/per-sys.sh"; then
  if DOTS_PKG_LIST=1 bash "$work/org-sys.sh" > "$work/org-pkgs.txt" 2>/dev/null && DOTS_PKG_LIST=1 bash "$work/per-sys.sh" > "$work/per-pkgs.txt" 2>/dev/null; then
    for p in "${pkgs[@]}"; do
      grep -qE "(^| )$p( |$)" "$work/org-pkgs.txt" && bad "org package list contains dots-ops package $p"
    done
    found=0; for p in "${pkgs[@]}"; do grep -qE "(^| )$p( |$)" "$work/per-pkgs.txt" && found=1; done
    [ "$found" = 1 ] || bad "personal package list has none of the dots-ops packages (test is vacuous)"
    grep -qw tailscale "$work/org-pkgs.txt" && bad "org package list contains tailscale"
    grep -qE 'tailscale(d)?( |\.service|\.com)' "$work/org-sys.sh" && bad "org root script still installs/enables tailscale"
    grep -q 'pipewire' "$work/org-pkgs.txt" || bad "org package list lost the desktop packages"
    ! grep -qE 'opt_install (power-profiles-daemon|lynis)' "$work/org-sys.sh" || bad "org root script still installs power-profiles-daemon/lynis"
  else echo "ORG: host distro has no package lists; package assertions skipped"; fi
fi

# Tailscale is out of the dotfiles entirely (triage dots_out): no package, installer or enable on any profile
grep -qE 'tailscale(d)?( |\.service|\.com)' "$work/per-sys.sh" && bad "personal root script still installs/enables tailscale"
grep -qw tailscale "$root/nix/home.nix" "$root/nix/hosts/nixos-laptop/configuration.nix" && bad "tailscale is still in the Nix config"
# nix: personal-only packages gated by DOTS_ORG_MANAGED (read in nix/home.nix)
grep -q 'getEnv "DOTS_ORG_MANAGED"' "$root/nix/home.nix" || bad "nix/home.nix does not read DOTS_ORG_MANAGED"
# one gate, one list: personal-only packages live in `personalOnly` and nowhere else reads the variable
grep -q 'personalOnly = lib.optionals (builtins.getEnv "DOTS_ORG_MANAGED" != "1")' "$root/nix/home.nix" || bad "nix/home.nix lacks the personalOnly list"
[ "$(grep -c 'DOTS_ORG_MANAGED' "$root/nix/home.nix")" -le 2 ] || bad "nix/home.nix reads DOTS_ORG_MANAGED outside personalOnly"
grep -qE '\+\+ personalOnly' "$root/nix/home.nix" || bad "personalOnly is not added to home.packages"
render "$org" run_onchange_before_10-nix.sh.tmpl "$work/org-nix.sh" && { grep -q 'export DOTS_ORG_MANAGED=1' "$work/org-nix.sh" || bad "org nix script lacks DOTS_ORG_MANAGED=1"; }
render "$per" run_onchange_before_10-nix.sh.tmpl "$work/per-nix.sh" && { ! grep -q 'export DOTS_ORG_MANAGED=1' "$work/per-nix.sh" || bad "personal nix script exports DOTS_ORG_MANAGED"; }

# ---- user side of the org profile ----
out="$work/org-home"
bash "$root/tests/render.sh" "$org" "$out" >/dev/null || bad "org render failed"
tgt="$out/.config/systemd/user/dots-ops-idle.target"
if [ -f "$tgt" ]; then
  grep -qE 'backup|dots-update|pins-check' "$tgt" && bad "idle target wants a job that is not deployed on org machines"
  grep -q 'dots-ops@disk-clean-user.service' "$tgt" && grep -q 'dots-ops@containers-prune.service' "$tgt" || bad "idle target lost its kept jobs"
else bad "org render has no idle target"; fi
grep -q '^enabled = false' "$out/.config/dots-ops/config.toml" || bad "org config.toml lacks [root] enabled = false"
perout="$work/per-home"
bash "$root/tests/render.sh" "$per" "$perout" >/dev/null || bad "personal render failed"
grep -q '^enabled = true' "$perout/.config/dots-ops/config.toml" || bad "personal config.toml lacks [root] enabled = true"
for j in dots-ops@backup.service dots-ops@backup-check.service dots-ops@dots-update.service; do
  grep -q "$j" "$perout/.config/systemd/user/dots-ops-idle.target" || bad "personal idle target lost $j"
done
# every dots-ops user timer enabled by the systemd script exists in the render (org and personal)
for d in "$org:$out" "$per:$perout"; do
  render "${d%%:*}" run_onchange_after_24-systemd.sh.tmpl "$work/sysd.sh" || continue
  for t in $(grep -o 'dots-ops-[a-z0-9-]*\.\(timer\|path\)' "$work/sysd.sh" | sort -u); do
    [ -f "${d#*:}/.config/systemd/user/$t" ] || bad "systemd script enables $t, which is not deployed (${d%%:*})"
  done
done
# the personal OVH tunnel: not deployed, not enabled (and stopped if it was) on org machines; the company tunnel stays
render "$org" run_onchange_after_24-systemd.sh.tmpl "$work/org-sysd.sh" && {
  grep -qE 'enable .*ovh-k8s-tunnel' "$work/org-sysd.sh" && bad "org systemd script enables the OVH tunnel"
  grep -q 'disable --now ovh-k8s-tunnel.service' "$work/org-sysd.sh" || bad "org systemd script does not stop a previously enabled OVH tunnel"
  grep -q 'enable --now onprem-kube-tunnel.service' "$work/org-sysd.sh" || bad "org systemd script lost the company tunnel"
}
render "$per" run_onchange_after_24-systemd.sh.tmpl "$work/per-sysd.sh" && { grep -q 'enable --now onprem-kube-tunnel.service ovh-k8s-tunnel.service' "$work/per-sysd.sh" || bad "personal systemd script lost the OVH tunnel"; }
[ ! -e "$out/.config/systemd/user/ovh-k8s-tunnel.service" ] || bad "OVH tunnel unit deployed on org machine"
grep -qi ovh "$out/.config/dots-ops/config.toml" && bad "org config.toml names the ovh context"
grep -q 'contexts = \["admin@onprem-s2a", "ovh"\]' "$perout/.config/dots-ops/config.toml" || bad "personal config.toml lost the ovh context"
exit $fail
