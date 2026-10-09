# updates-security (root, heavy): apply security-only updates automatically where the distro has a security channel.
# Debian: unattended-upgrade (security origins configured by the root layer); Fedora/RHEL: dnf --security.
# Arch has no security channel (the full-update ask covers it) and NixOS updates via the repo -> ok n/a (Review Focus 4).
OPS_HEAVY=1
job_main() {
  local fam out rc=0
  fam=$(ops_family)
  case $fam in
    debian|fedora) ;;
    arch)   ops_state updates-security ok "n/a: no security channel; use full updates"; return 0 ;;
    nixos)  ops_state updates-security ok "n/a: nixos updates come from the repo"; return 0 ;;
    *)      ops_state updates-security ok "n/a: unsupported distro"; return 0 ;;
  esac
  # R56: shared package lock for the transaction (an approved full update may be running; reboots wait for us)
  if ! ops_pkg_lock; then
    ops_state updates-security warn "skipped: another package transaction is running (lock busy ${OPS_PKG_LOCK_WAIT:-1800}s)"; return 0
  fi
  case $fam in
    debian) out=$(ops_run unattended-upgrade -v 2>&1) || rc=$? ;;
    fedora) out=$(ops_run dnf upgrade --security -y 2>&1) || rc=$? ;;
  esac
  ops_pkg_unlock
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" = 0 ]; then
    ops_state updates-security ok "security updates applied ($fam)"
    ops_run systemctl start --no-block dots-ops@reboot-needed.service || true   # R35: security updates can need a reboot
  else ops_state updates-security fail "security update failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')"; fi
}
