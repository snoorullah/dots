# trim (root): make sure periodic TRIM is on; fall back to a one-off fstrim when the distro ships no fstrim.timer.
job_main() {
  if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
    ops_state trim ok "fstrim.timer enabled"
  elif systemctl list-unit-files fstrim.timer --no-legend 2>/dev/null | grep -q '^fstrim.timer'; then
    if ops_run systemctl enable --now fstrim.timer; then ops_state trim ok "enabled fstrim.timer"
    else ops_state trim warn "could not enable fstrim.timer"; fi
  else
    if ops_run fstrim -av; then ops_state trim ok "no fstrim.timer; ran fstrim -av"
    else ops_state trim warn "fstrim -av failed"; fi
  fi
}
