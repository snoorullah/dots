# k8s-health: every 15 min, per [k8s] contexts. Issues are keys ctx/kind/ns/name/reason ("-" = cluster-scoped) kept in k8s-issues.json.
# Notification policy: ops_state notifies on the status transition (ok -> warn: first issue; warn -> ok: recovered). While already
# warn, ops_notify is called directly once for each NEW key only, so the same issue never notifies twice. The summary is count + first 3 keys.
# An unreachable context only warns "<ctx> unreachable" (a down tunnel is net-watch's job) and keeps that context's previous keys.
_kh() { kubectl --context "$_kh_ctx" --request-timeout=10s "$@"; }
_kh_ctx_issues() {   # ctx -> keys on stdout; rc 1 = unreachable
  local ctx=$1 nodes now; _kh_ctx=$ctx
  nodes=$(_kh get nodes -o json 2>/dev/null) || return 1
  now=$(ops_now)
  jq -r --arg c "$ctx" '.items[]? | select(any(.status.conditions[]?; .type=="Ready" and .status!="True")) | "\($c)/node/-/\(.metadata.name)/NotReady"' <<< "$nodes"
  _kh get pods -A -o json 2>/dev/null | jq -r --arg c "$ctx" '.items[]? | . as $p
    | [(.status.containerStatuses[]?, .status.initContainerStatuses[]?) | .state.waiting.reason // empty
       | select(. == "CrashLoopBackOff" or . == "ImagePullBackOff")] | unique[]
    | "\($c)/pod/\($p.metadata.namespace)/\($p.metadata.name)/\(.)"'
  if _kh get crd certificates.cert-manager.io >/dev/null 2>&1; then
    _kh get certificates.cert-manager.io -A -o json 2>/dev/null | jq -r --arg c "$ctx" --argjson n "$now" '.items[]?
      | select(.status.notAfter and ((.status.notAfter | fromdateiso8601) < ($n + 14*86400)))
      | "\($c)/certificate/\(.metadata.namespace)/\(.metadata.name)/expiring"'
  fi
  if _kh get crd applications.argoproj.io >/dev/null 2>&1; then
    _kh get applications.argoproj.io -A -o json 2>/dev/null | jq -r --arg c "$ctx" '.items[]?
      | select((.status.sync.status // "Unknown") != "Synced" or (.status.health.status // "Unknown") != "Healthy")
      | "\($c)/application/\(.metadata.namespace)/\(.metadata.name)/\(if (.status.sync.status // "Unknown") != "Synced" then (.status.sync.status // "Unknown") else (.status.health.status // "Unknown") end)"'
  fi
  return 0
}
job_main() {
  local raw contexts=() ctx f="$OPS_STATE/k8s-issues.json" prev_keys keys="" unreachable=() out k prev_status new=() all n sum
  command -v kubectl >/dev/null 2>&1 || { ops_state k8s-health ok "n/a: kubectl not installed"; return 0; }
  raw=$(ops_cfg k8s.contexts "")   # yq prints a YAML list ("- a")
  while IFS= read -r ctx; do
    ctx=$(sed -E 's/^[[:space:]]*-?[[:space:]]*//; s/^["'\'']//; s/["'\'',]*[[:space:]]*$//' <<< "$ctx")
    if [ -n "$ctx" ] && [ "$ctx" != '[]' ]; then contexts+=("$ctx"); fi
  done <<< "$raw"
  [ ${#contexts[@]} -gt 0 ] || { ops_state k8s-health ok "n/a: no k8s contexts configured"; return 0; }
  prev_keys=$(jq -r '.keys[]?' "$f" 2>/dev/null || true)
  prev_status=$(jq -r '.status // "none"' "$OPS_STATE/state/k8s-health.json" 2>/dev/null || echo none)
  for ctx in "${contexts[@]}"; do
    if out=$(_kh_ctx_issues "$ctx"); then
      keys+="${out:+$out$'\n'}"
    else
      unreachable+=("$ctx")
      keys+="$(grep -F -- "$ctx/" <<< "$prev_keys" | grep -F -- "$ctx/" || true)"$'\n'   # keep what we knew about it
    fi
  done
  all=$(grep . <<< "$keys" | sort -u || true)
  while IFS= read -r k; do
    if [ -n "$k" ] && ! grep -qxF -- "$k" <<< "$prev_keys"; then new+=("$k"); fi
  done <<< "$all"
  jq -Rn '[inputs | select(length>0)]' <<< "$all" | jq -c '{keys:.}' > "$f.tmp" && mv "$f.tmp" "$f"
  n=$(grep -c . <<< "$all" || true)
  sum=""
  [ "$n" -eq 0 ] || sum="$n issue(s): $(head -n 3 <<< "$all" | paste -sd, - | sed 's/,/, /g')"
  [ ${#unreachable[@]} -eq 0 ] || sum+="${sum:+; }$(printf '%s, ' "${unreachable[@]}" | sed 's/, $//') unreachable"
  if [ -n "$sum" ]; then
    ops_state k8s-health warn "$sum"
    # already warn before this run: ops_state stays quiet, so announce just the new keys
    if [ "$prev_status" = warn ] && [ ${#new[@]} -gt 0 ]; then
      ops_notify normal "dots-ops: k8s-health" "new: $(printf '%s, ' "${new[@]}" | sed 's/, $//')"
    fi
  else ops_state k8s-health ok "${#contexts[@]} context(s) healthy"; fi
}
