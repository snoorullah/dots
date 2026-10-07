# disk-clean-user: Nix GC for the user profile plus stale (>30 d) caches. Reports MB freed in the cleaned dirs.
OPS_HEAVY=1
_du_total() { [ $# -eq 0 ] && { echo 0; return; }; du -sm "$@" 2>/dev/null | awk '{s+=$1} END{print s+0}'; }
job_main() {
  local d dirs=() before after
  for d in pip uv npm yarn go-build thumbnails; do
    [ -d "$HOME/.cache/$d" ] && dirs+=("$HOME/.cache/$d")
  done
  before=$(_du_total "${dirs[@]}")
  if command -v nix-collect-garbage >/dev/null; then
    ops_run nix-collect-garbage --delete-older-than 14d \
      || ops_log disk-clean-user warn "nix-collect-garbage failed"
  fi
  for d in "${dirs[@]}"; do
    ops_run find "$d" -type f -mtime +30 -delete || ops_log disk-clean-user warn "cleaning $d failed"
  done
  after=$(_du_total "${dirs[@]}")
  ops_state disk-clean-user ok "freed $(( before > after ? before - after : 0 )) MB"
}
