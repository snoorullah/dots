# disk-watch: hourly. Worst filesystem use -> ok/warn/fail; at >= warn it kicks off both cleaners.
job_main() {
  local warn crit worst=0 offenders="" cap mp pct sudo_cmd
  warn=$(ops_cfg disk.warn 85); crit=$(ops_cfg disk.crit 95)
  while read -r _ _ _ _ cap mp; do
    pct=${cap%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue
    [ "$pct" -gt "$worst" ] && worst=$pct
    [ "$pct" -ge "$warn" ] && offenders+="${offenders:+, }$mp $pct%"
  done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay | tail -n +2)
  if [ "$worst" -ge "$crit" ]; then ops_state disk-watch fail "$offenders"
  elif [ "$worst" -ge "$warn" ]; then ops_state disk-watch warn "$offenders"
  else ops_state disk-watch ok "worst $worst%"; return 0; fi
  ops_run systemctl --user start --no-block dots-ops@disk-clean-user.service \
    || ops_log disk-watch warn "could not start disk-clean-user"
  read -ra sudo_cmd <<< "$OPS_SUDO"
  ops_run "${sudo_cmd[@]}" "$OPS_RUNNER" disk-clean-system run-now \
    || ops_log disk-watch warn "sudo disk-clean-system run-now refused or failed; skipped"
  return 0
}
