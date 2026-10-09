# disk-watch: hourly. Worst use of real (rw, block-backed, >= 1 GiB) filesystems -> ok/warn/fail;
# at >= warn it kicks off both cleaners with OPS_FORCE so the idle/AC gate cannot skip them while the disk fills (R27).
# Forced cleans back off for 6 h (R63).
job_main() {
  local warn crit worst=0 offenders="" fstype size cap mp pct sudo_cmd
  warn=$(ops_cfg disk.warn 85); crit=$(ops_cfg disk.crit 95)
  while read -r fstype size cap mp; do
    case $fstype in tmpfs|devtmpfs|squashfs|overlay|iso9660|efivarfs|ecryptfs|fuse*|proc|sysfs|cgroup*|ramfs|autofs) continue ;; esac
    [[ $size =~ ^[0-9]+$ ]] && [ "$size" -ge 1073741824 ] || continue   # < 1 GiB: boot/EFI/tiny mounts cry wolf
    pct=${cap%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue
    mp=$(printf '%b' "$mp")   # findmnt -r escapes spaces as \x20
    [ "$pct" -gt "$worst" ] && worst=$pct
    [ "$pct" -ge "$warn" ] && offenders+="${offenders:+, }$mp $pct%"
  done < <(findmnt -rn -b -O rw -o FSTYPE,SIZE,USE%,TARGET)
  if [ "$worst" -ge "$crit" ]; then ops_state disk-watch fail "$offenders"
  elif [ "$worst" -ge "$warn" ]; then ops_state disk-watch warn "$offenders"
  else ops_state disk-watch ok "worst $worst%"; return 0; fi
  # R63: forced cleaners at most every 6 h (disk-watch.forced); hourly re-runs on a disk they cannot free would churn
  local last now; now=$(ops_now); last=$(head -n 1 "$OPS_STATE/disk-watch.forced" 2>/dev/null) || last=0
  [[ $last =~ ^[0-9]+$ ]] || last=0
  if [ $((now - last)) -lt 21600 ]; then
    ops_log disk-watch info "cleaners started $(( (now - last) / 60 )) min ago; next forced clean after 6 h"; return 0
  fi
  [ "${DOTS_OPS_DRY_RUN:-0}" = 1 ] || echo "$now" > "$OPS_STATE/disk-watch.forced"
  ops_run systemd-run --user --no-block --collect --setenv=OPS_FORCE=1 \
    -p "ExecStopPost=$HOME/.local/bin/dots-ops-job --report-failure disk-clean-user" "$HOME/.local/bin/dots-ops-job" disk-clean-user \
    || ops_log disk-watch warn "could not start disk-clean-user"
  ops_root_enabled || return 0   # orgManaged: warn only, no root clean
  read -ra sudo_cmd <<< "$OPS_SUDO"
  ops_run "${sudo_cmd[@]}" "$OPS_RUNNER" disk-clean-system run-now \
    || ops_log disk-watch warn "sudo disk-clean-system run-now refused or failed; skipped"
  return 0
}
