# power-profile (root): udev fires this when the AC adapter changes. Laptop on AC -> performance, on battery -> power-saver,
# no battery (desktop) -> balanced. The user's perf-mode toggle is user state root cannot see; it re-asserts itself on its next toggle.
job_main() {
  command -v powerprofilesctl >/dev/null || { ops_state power-profile ok "n/a: power-profiles-daemon not installed"; return 0; }
  local profile; profile=$(ops_default_profile)   # the same rule perf-mode off uses (R63)
  if ops_run powerprofilesctl set "$profile"; then ops_state power-profile ok "profile $profile"
  else ops_state power-profile warn "powerprofilesctl set $profile failed"; fi
}
