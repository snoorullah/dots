# backup-check: weekly integrity check of the restic repository (structure + a random 5% of the pack data).
OPS_HEAVY=1
job_main() {
  ops_restic_env || { ops_state backup-check ok "n/a: backups not configured"; return 0; }
  local out rc=0
  out=$(ops_run restic check --read-data-subset=5% 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" = 0 ]; then ops_state backup-check ok "repository check passed (5% of data read)"
  else ops_state backup-check fail "restic check failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 1)"; fi
}
