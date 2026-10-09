# backup-watch: fail when the newest dots-ops restic snapshot is older than backup.max_age_hours (or there is none).
job_main() {
  ops_restic_env || { ops_state backup-watch ok "n/a: backups not configured"; return 0; }
  local out err rc=0 max t ts newest=0 age
  err=$OPS_STATE/backup-watch.err
  out=$(ops_run restic snapshots --tag dots-ops --latest 1 --json 2>"$err") || rc=$?
  if [ "$rc" != 0 ]; then ops_state backup-watch warn "cannot read the repository (rc=$rc): $(tail -n 1 "$err")"; return 0; fi
  max=$(ops_cfg backup.max_age_hours 48)
  while read -r t; do
    ts=$(date -d "$t" +%s 2>/dev/null) || continue
    [ "$ts" -le "$newest" ] || newest=$ts
  done < <(printf '%s\n' "$out" | jq -r '.[]?.time // empty' 2>/dev/null)
  if [ "$newest" = 0 ]; then ops_state backup-watch fail "no dots-ops snapshot in the repository"; return 0; fi
  age=$(( ($(ops_now) - newest) / 3600 ))
  if [ "$age" -gt "$max" ]; then ops_state backup-watch fail "last backup ${age}h ago (max ${max}h)"
  else ops_state backup-watch ok "last backup ${age}h ago"; fi
}
