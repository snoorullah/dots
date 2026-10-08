# backup-check: weekly integrity check of the restic repository (structure + a random 5% of the pack data).
# Heavy: the weekly timer and dots-ops-idle.target both start it (R59); it skips itself when the last check ran less
# than 7 days ago (backup-check.last in $OPS_STATE) unless forced (`dots-ops run backup-check --now`).
OPS_HEAVY=1
job_main() {
  ops_restic_env || { ops_state backup-check ok "n/a: backups not configured"; return 0; }
  ops_ran_within backup-check 604800 && return 0
  local out rc=0
  out=$(ops_run restic check --read-data-subset=5% 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" = 11 ]; then   # R65: repo locked (usually a backup/prune running) — not a failure, not a run; retry next idle
    ops_log backup-check info "repository locked; check skipped, retrying next idle"; return 0
  fi
  ops_ran_mark backup-check   # a failed check counts as a run too: its fail stays red (and reminds) until fixed
  if [ "$rc" = 0 ]; then ops_state backup-check ok "repository check passed (5% of data read)"
  else ops_state backup-check fail "restic check failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 1)"; fi
}
