# containers: hourly. Unhealthy or restarting containers -> warn. No docker / daemon down -> ok n/a.
job_main() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    ops_state containers ok "n/a: docker unavailable"; return 0
  fi
  local bad
  bad=$( { docker ps --filter health=unhealthy --format '{{.Names}}'; docker ps --filter status=restarting --format '{{.Names}}'; } 2>/dev/null | sort -u | paste -sd, - | sed 's/,/, /g')
  if [ -n "$bad" ]; then ops_state containers warn "unhealthy/restarting: $bad"
  else ops_state containers ok "all containers healthy"; fi
}
