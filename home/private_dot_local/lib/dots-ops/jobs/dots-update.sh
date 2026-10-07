# dots-update: pull the dots repo and apply it (its run_onchange scripts re-run the Nix switch). Heavy, daily.
OPS_HEAVY=1
job_main() {
  local out rc=0
  out=$(ops_run chezmoi update --apply --no-tty 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" = 0 ]; then ops_state dots-update ok "dots up to date"
  else ops_state dots-update fail "chezmoi update failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')- run 'chezmoi diff' to inspect"; fi
}
