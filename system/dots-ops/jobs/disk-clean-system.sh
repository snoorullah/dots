# disk-clean-system (root): journal vacuum, package-cache clean per family, Nix GC.
# Heavy; disk-watch forces it via `dots-ops-run disk-clean-system run-now` (OPS_FORCE skips the idle gate).
OPS_HEAVY=1
job_main() {
  local fam rc=0
  fam=$(ops_family)
  ops_run journalctl --vacuum-time=2weeks || { rc=1; ops_log disk-clean-system warn "journal vacuum failed"; }
  case $fam in
    debian) ops_run apt-get clean || rc=1 ;;
    fedora) ops_run dnf clean packages || rc=1 ;;
    arch)   if command -v paccache >/dev/null; then ops_run paccache -rk2 || rc=1; fi ;;
  esac
  if [ -d /nix ] && command -v nix-collect-garbage >/dev/null; then
    ops_run nix-collect-garbage --delete-older-than 14d || rc=1
  fi
  if [ "$rc" = 0 ]; then ops_state disk-clean-system ok "cleaned ($fam)"
  else ops_state disk-clean-system warn "some cleanup steps failed ($fam); see log"; fi
}
