# reboot / tonight (approved root action): arm a reboot for 03:00 (R56). Not a bare `shutdown -r 03:00`: a transient
# timer starts the root job reboot-scheduled at 03:00, which reboots only if no package transaction holds the pkg lock
# (else it re-arms itself +15 min, at most 8 times). $JOB_BIN is the runner's root-owned job runner.
# Cancel: systemctl stop dots-ops-reboot-scheduled.timer (or remove /var/lib/dots-ops/root/reboot-scheduled.json).
_rt_job=${JOB_BIN:-/usr/local/bin/dots-ops-job}
ops_run systemctl stop dots-ops-reboot-scheduled.timer 2>/dev/null || true   # re-approval replaces an earlier schedule
ops_run systemd-run --no-block --collect --unit=dots-ops-reboot-scheduled --on-calendar='*-*-* 03:00:00' \
  --setenv="PATH=$PATH" --setenv=OPS_IS_ROOT=1 -p "ExecStopPost=$_rt_job --report-failure reboot-scheduled" "$_rt_job" reboot-scheduled
if [ "${DOTS_OPS_DRY_RUN:-0}" != 1 ]; then   # only once the timer exists (set -e stops us otherwise)
  mkdir -p "$OPS_ROOT_DATA"
  jq -cn --argjson t "$(ops_now)" '{tries:0,armed:$t}' > "$OPS_ROOT_DATA/reboot-scheduled.json"
  rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"
  ops_state reboot-needed warn "reboot scheduled for 03:00 (cancel: sudo systemctl stop dots-ops-reboot-scheduled.timer)"
fi
unset _rt_job
