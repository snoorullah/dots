# reboot-scheduled (root): fired at 03:00 by the transient timer that the approved `reboot tonight` action creates (R56).
# Reboots only when armed ($OPS_ROOT_DATA/reboot-scheduled.json, written by that action) and no package transaction
# holds the pkg lock. Lock held -> re-arm +15 min (transient unit dots-ops-reboot-scheduled-<n>), at most 8 times,
# then give up with warn. Not armed -> nothing (running it by hand, or the daily timer firing again, never reboots).
# Reports under reboot-needed (the job the owner sees).
job_main() {
  local f="$OPS_ROOT_DATA/reboot-scheduled.json" tries jb=${JOB_BIN:-/usr/local/bin/dots-ops-job}
  [ -f "$f" ] || { ops_log reboot-scheduled info "no reboot armed; nothing to do"; return 0; }
  tries=$(jq -r '.tries // 0' "$f" 2>/dev/null) || tries=0
  [[ $tries =~ ^[0-9]+$ ]] || tries=0
  if ops_pkg_busy; then
    if [ "$tries" -ge 8 ]; then
      rm -f "$f"; ops_run systemctl stop dots-ops-reboot-scheduled.timer 2>/dev/null || true
      ops_state reboot-needed warn "scheduled reboot gave up: a package transaction was still running after 8 retries — reboot by hand"
      return 0
    fi
    tries=$((tries + 1))
    jq -c --argjson n "$tries" '.tries = $n' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    if ops_run systemd-run --no-block --collect --unit="dots-ops-reboot-scheduled-$tries" --on-active=15min \
         --setenv="PATH=$PATH" --setenv=OPS_IS_ROOT=1 -p "ExecStopPost=$jb --report-failure reboot-scheduled" "$jb" reboot-scheduled; then
      ops_state reboot-needed warn "package transaction running at reboot time — retry $tries/8 in 15 min"
    else
      rm -f "$f"; ops_state reboot-needed warn "scheduled reboot could not re-arm (systemd-run failed) — reboot by hand"
    fi
    return 0
  fi
  rm -f "$f"
  ops_log reboot-scheduled info "rebooting (scheduled)"
  ops_run systemctl reboot
}
