# timetrack-live: every 5 minutes. Only the ActivityWatch refresh of today, nothing else.
#
# Worked (the overview's Today) is today's AW session, and timetrack-capture refreshes it
# hourly, so the figure lagged the day by up to an hour: at 17:58 it still read the 20m
# the 17:00 run had seen. ingest-aw alone takes a fraction of a second; the slow half of
# capture (web, term, vault, doctor) stays hourly.
#
# Both jobs rewrite today's AW session, so they share one lock and never run it at once.
job_main() {
  local tt out rc lk
  tt=$(command -v timetrack 2>/dev/null) || return 0   # capture reports the missing binary
  exec {lk}>"$OPS_STATE/locks/timetrack-aw.lock"
  flock -w 60 "$lk" || { ops_log timetrack-live info "AW refresh busy; skipped"; return 0; }
  out=$("$tt" ingest-aw 2>&1); rc=$?
  exec {lk}>&-
  if [ "$rc" -ne 0 ]; then
    ops_state timetrack-live warn "ingest-aw failed: $(printf '%s' "$out" | tail -1)"
    return 0
  fi
  ops_state timetrack-live ok "today refreshed"
  return 0
}
