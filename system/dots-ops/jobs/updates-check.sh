# updates-check (root): count pending package updates per family; any pending -> ask for approval (updates-full apply).
# The ask text carries the count and a kernel/driver flag. Arch never runs `pacman -Sy` (partial upgrades); NixOS -> n/a.
job_main() {
  local fam list="" n kd rc=0 ask="$OPS_ROOT_STATE/ask-updates-full.json"
  fam=$(ops_family)
  case $fam in
    debian)
      ops_run apt-get update -qq || ops_log updates-check warn "apt-get update failed; counting from the old indexes"
      list=$(apt-get -s dist-upgrade 2>/dev/null | grep '^Inst' || true) ;;
    fedora)
      list=$(dnf -q check-update 2>/dev/null) || rc=$?
      case $rc in
        100) list=$(awk '/^Obsoleting/{exit} NF==3{print}' <<< "$list") ;;
        0)   list="" ;;
        *)   ops_state updates-check warn "dnf check-update failed (rc=$rc)"; return 0 ;;
      esac ;;
    arch)
      if ! command -v checkupdates >/dev/null; then
        ops_state updates-check warn "checkupdates not found: install pacman-contrib"; return 0
      fi
      list=$(checkupdates 2>/dev/null) || rc=$?
      case $rc in 0|2) ;; *) ops_state updates-check warn "checkupdates failed (rc=$rc)"; return 0 ;; esac ;;   # 2 = no updates
    nixos) ops_state updates-check ok "n/a: nixos-rebuild"; return 0 ;;
    *)     ops_state updates-check ok "n/a: unsupported distro"; return 0 ;;
  esac
  n=$(printf '%s\n' "$list" | grep -c . || true)
  if [ "${n:-0}" -gt 0 ]; then
    kd=no; grep -Eiq 'linux|kernel|nvidia' <<< "$list" && kd=yes
    ops_ask updates-full "Apply $n updates (kernel/driver: $kd)?" "root:updates-full apply"
    ops_state updates-check warn "$n pending"
  else
    rm -f "$ask"   # nothing pending any more: withdraw an old ask
    ops_state updates-check ok "up to date"
  fi
}
