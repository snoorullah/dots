# dots-update: pull the dots repo and apply it (its run_onchange scripts re-run the Nix switch). Heavy, daily.
# The daily timer and dots-ops-idle.target both start it (R59); it skips itself when it ran less than 1 day ago
# (dots-update.last in $OPS_STATE) unless forced (`dots-ops run dots-update --now`).
OPS_HEAVY=1
job_main() {
  ops_ran_within dots-update 86400 && return 0
  local out rc=0
  out=$(ops_run chezmoi update --apply --no-tty 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  ops_ran_mark dots-update
  if [ "$rc" = 0 ]; then ops_state dots-update ok "dots up to date"
  else ops_state dots-update fail "chezmoi update failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')- run 'chezmoi diff' to inspect"; fi
}
