# backup: restic snapshot of $HOME (+ the dots repo when it lives outside $HOME), then forget/prune per the [backup] policy.
# Credentials come from RESTIC_REPOSITORY / RESTIC_PASSWORD(_FILE), usually via ~/.secrets. Never fails when unconfigured.
OPS_HEAVY=1
job_main() {
  ops_restic_env || { ops_state backup warn "not configured: set RESTIC_REPOSITORY and RESTIC_PASSWORD in ~/.secrets"; return 0; }
  local src=("$HOME") dots out err rc=0 partial=0 line sid size dry=${DOTS_OPS_DRY_RUN:-0}
  dots=$(chezmoi source-path 2>/dev/null) || dots=""
  case $dots in ""|"$HOME"|"$HOME"/*) ;; *) src+=("$dots") ;; esac   # inside $HOME is already covered
  err=$OPS_STATE/backup.err
  out=$(ops_run restic backup "${src[@]}" --exclude-caches --exclude-file "$HOME/.config/dots-ops/backup-excludes" --tag dots-ops --json 2>"$err") || rc=$?
  [ "$dry" != 1 ] || printf '%s\n' "$out"
  line=$(tail -n 1 "$err")
  if [ "$rc" = 11 ]; then ops_state backup warn "repository locked: $line"; return 0; fi
  if [ "$rc" = 3 ]; then partial=1   # snapshot was made, some files were unreadable
  elif [ "$rc" != 0 ]; then ops_state backup fail "restic backup failed (rc=$rc): $line"; return 0; fi
  sid=$(printf '%s\n' "$out" | jq -rs 'map(select(.message_type? == "summary")) | last | .snapshot_id // empty | .[0:8]' 2>/dev/null)
  size=$(printf '%s\n' "$out" | jq -rs 'map(select(.message_type? == "summary")) | last | .data_added // empty' 2>/dev/null)
  rc=0
  out=$(ops_run restic forget --tag dots-ops --keep-daily "$(ops_cfg backup.keep_daily 7)" --keep-weekly "$(ops_cfg backup.keep_weekly 4)" \
    --keep-monthly "$(ops_cfg backup.keep_monthly 6)" --prune 2>"$err") || rc=$?
  [ "$dry" != 1 ] || printf '%s\n' "$out"
  line=$(tail -n 1 "$err")
  if [ "$rc" = 11 ]; then ops_state backup warn "repository locked during forget: $line"; return 0; fi
  if [ "$rc" != 0 ]; then ops_state backup fail "restic forget failed (rc=$rc): $line"; return 0; fi
  if [ "$dry" = 1 ]; then ops_state backup ok "dry run"; return 0; fi
  local msg="snapshot ${sid:-?}, added $(( ${size:-0} / 1048576 )) MiB"
  if [ "$partial" = 1 ]; then ops_state backup warn "$msg; some files were unreadable"
  else ops_state backup ok "$msg"; fi
}
