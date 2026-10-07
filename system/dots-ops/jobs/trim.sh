# trim (root): make sure periodic TRIM is on; fall back to a one-off fstrim when the distro ships no fstrim.timer.
job_main() {
  local out rc=0
  if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
    ops_state trim ok "fstrim.timer enabled"
  elif systemctl list-unit-files fstrim.timer --no-legend 2>/dev/null | grep -q '^fstrim.timer'; then
    if ops_run systemctl enable --now fstrim.timer; then ops_state trim ok "enabled fstrim.timer"
    else ops_state trim warn "could not enable fstrim.timer"; fi
  else
    out=$(ops_run fstrim -av 2>&1) || rc=$?
    printf '%s\n' "$out"
    if [ "$rc" = 0 ]; then ops_state trim ok "no fstrim.timer; ran fstrim -av"
    elif grep -qiE 'not supported|discard' <<< "$out"; then ops_state trim ok "n/a: discard unsupported"   # R30: nothing to trim
    else ops_state trim warn "fstrim -av failed (rc=$rc)"; fi
  fi
}
