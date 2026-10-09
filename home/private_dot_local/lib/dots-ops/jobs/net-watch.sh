# net-watch: every 5 min (also covers network changes; no NetworkManager hook, R7). DNS + connectivity, tailscale, kube tunnels.
# A tunnel whose unit condition is not met (secret not copied on this machine) or that does not exist is n/a: never restarted, never failed.
# An inactive tunnel is restarted once (restarted_at in net-watch-tunnels.json); still inactive on the next run -> fail.
_nw_tunnels="onprem-kube-tunnel ovh-k8s-tunnel"
job_main() {
  local dns=1 net=1 problems=() restarted=() failed=() u cond f="$OPS_STATE/net-watch-tunnels.json" js
  getent hosts one.one.one.one >/dev/null 2>&1 || dns=0
  curl -fsS --max-time 5 https://1.1.1.1/cdn-cgi/trace >/dev/null 2>&1 || net=0
  if [ "$dns" = 0 ] && [ "$net" = 0 ]; then ops_state net-watch warn "offline"; return 0; fi
  [ "$dns" = 1 ] || problems+=("DNS failing")
  [ "$net" = 1 ] || problems+=("no connectivity to 1.1.1.1")
  if command -v tailscale >/dev/null 2>&1; then
    local bs; bs=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null)
    [ "$bs" = Running ] || problems+=("tailscale ${bs:-unknown}")
  fi
  js=$(cat "$f" 2>/dev/null) || true; jq -e type >/dev/null 2>&1 <<< "$js" || js='{}'
  for u in $_nw_tunnels; do
    systemctl --user cat "$u.service" >/dev/null 2>&1 || continue
    cond=$(systemctl --user show -p ConditionResult --value "$u.service" 2>/dev/null)
    [ "$cond" = no ] && continue
    if systemctl --user is-active --quiet "$u.service"; then
      js=$(jq -c --arg u "$u" 'del(.[$u])' <<< "$js")
    elif [ -n "$(jq -r --arg u "$u" '.[$u].restarted_at // empty' <<< "$js")" ]; then
      failed+=("$u")
    else
      ops_run systemctl --user restart "$u.service" || ops_log net-watch warn "restart of $u failed"
      js=$(jq -c --arg u "$u" --argjson t "$(ops_now)" '.[$u]={restarted_at:$t}' <<< "$js")
      restarted+=("$u")
    fi
  done
  printf '%s\n' "$js" > "$f.tmp" && mv "$f.tmp" "$f"
  local IFS=,
  if [ ${#failed[@]} -gt 0 ]; then ops_state net-watch fail "tunnel still down after restart: ${failed[*]}"
  elif [ ${#restarted[@]} -gt 0 ] || [ ${#problems[@]} -gt 0 ]; then
    local m=""; [ ${#problems[@]} -eq 0 ] || m="${problems[*]}"
    [ ${#restarted[@]} -eq 0 ] || m+="${m:+; }restarted tunnel: ${restarted[*]}"
    ops_state net-watch warn "$m"
  else ops_state net-watch ok "online"; fi
}
