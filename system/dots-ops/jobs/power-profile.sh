# power-profile (root): udev fires this when the AC adapter changes. Laptop on AC -> performance, on battery -> power-saver,
# no battery (desktop) -> balanced. The user's perf-mode toggle is user state root cannot see; it re-asserts itself on its next toggle.
job_main() {
  command -v powerprofilesctl >/dev/null || { ops_state power-profile ok "n/a: power-profiles-daemon not installed"; return 0; }
  local d bat=0 profile
  for d in "$OPS_POWER_DIR"/*; do
    [ -e "$d/type" ] || continue
    grep -q Device "$d/scope" 2>/dev/null && continue   # peripheral batteries (mouse, headset)
    [ "$(cat "$d/type")" = Battery ] && bat=1
  done
  if [ "$bat" = 0 ]; then profile=balanced
  elif ops_on_ac; then profile=performance
  else profile=power-saver; fi
  if ops_run powerprofilesctl set "$profile"; then ops_state power-profile ok "profile $profile"
  else ops_state power-profile warn "powerprofilesctl set $profile failed"; fi
}
