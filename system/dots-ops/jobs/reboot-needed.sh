# reboot-needed (root): is a reboot pending? Triggered by dots-ops-reboot.path and after updates-full apply.
# Needed -> two-button ask (R5): Approve = reboot now, alt = tonight 03:00.
job_main() {
  local fam needed=0 rel rr="${OPS_REBOOT_REQUIRED:-/var/run/reboot-required}" ask="$OPS_ROOT_STATE/ask-reboot-needed.json"
  fam=$(ops_family)
  case $fam in
    debian) [ -e "$rr" ] && needed=1 ;;
    fedora) command -v needs-restarting >/dev/null || { ops_state reboot-needed ok "n/a: needs-restarting missing (dnf-plugins-core)"; return 0; }
            needs-restarting -r >/dev/null 2>&1 || needed=1 ;;   # exit 1 = reboot needed
    arch)   rel=${OPS_KERNEL_RELEASE:-$(uname -r)}
            [ -d "${OPS_MODULES_DIR:-/usr/lib/modules}/$rel" ] || needed=1 ;;   # the running kernel's modules were replaced
    nixos)  ops_state reboot-needed ok "n/a: nixos switch handles kernels"; return 0 ;;
    *)      ops_state reboot-needed ok "n/a: unsupported distro"; return 0 ;;
  esac
  if [ "$needed" = 1 ]; then
    ops_ask reboot-needed "Reboot now or tonight 03:00?" "root:reboot now" "root:reboot tonight" "Tonight 03:00"
    ops_state reboot-needed warn "reboot required"
  else
    rm -f "$ask"
    ops_state reboot-needed ok "no reboot needed"
  fi
}
