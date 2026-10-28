# overview-sync: hourly. The slow half of dots-overview -- GitHub + ERP read-only, then the
# completion detectors, then the invariants. It skips quietly when offline. It only ever
# READS the sources: completion is marked in local Taskwarrior and nowhere else.
# A failed source or a broken invariant turns the ops module amber instead of failing
# silently; the exit code of `doctor` is the whole signal.
job_main() {
  local out rc=0 sum
  command -v dots-overview >/dev/null 2>&1 || { ops_state overview-sync warn "dots-overview is not installed"; return 0; }
  if ! timeout 5 getent hosts api.github.com >/dev/null 2>&1; then
    ops_state overview-sync ok "offline; skipped"; return 0
  fi
  # ERP in mcp mode spends model tokens, so it rides along at most every ERP_EVERY seconds
  # rather than hourly. Token mode costs nothing and runs every time.
  local erp_flag="" stamp="${XDG_STATE_HOME:-$HOME/.local/state}/dots-overview/erp-mcp.stamp"
  if grep -qs '^ERP_MODE=mcp' "${XDG_CONFIG_HOME:-$HOME/.config}/dots-work/work.conf"; then
    local last; last=$(stat -c %Y "$stamp" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - last )) -ge "${ERP_EVERY:-14400}" ]; then
      erp_flag="--erp-mcp"; mkdir -p "${stamp%/*}"; : > "$stamp"
    fi
  fi
  out=$(timeout 600 dots-overview sync $erp_flag 2>&1) || rc=$?
  timeout 600 dots-overview detect >/dev/null 2>&1 || rc=$((rc + 1))
  timeout 120 dots-overview fast --apps all >/dev/null 2>&1 || rc=$((rc + 1))
  sum=$(dots-overview doctor 2>&1 | tail -n 1)
  if [ "$rc" -ne 0 ]; then ops_state overview-sync warn "${out##*$'\n'}; $sum"
  elif dots-overview doctor >/dev/null 2>&1; then ops_state overview-sync ok "${out##*$'\n'}"
  else ops_state overview-sync warn "$sum"; fi
  return 0
}
