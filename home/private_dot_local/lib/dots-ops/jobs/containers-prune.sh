# containers-prune: heavy (idle target). Dangling images are pruned automatically; if more than 10 GB is reclaimable, ask before the
# root volumes prune (never offered when ops_root_enabled is false; anonymous volumes and unused data; named volumes survive on Docker >= 23).
OPS_HEAVY=1
_cp_bytes() {   # stdin: "Reclaimable" strings like "2.5GB (45%)"; prints the sum in bytes (decimal units, as Docker prints)
  awk '{ if (match($1, /^[0-9.]+/)) { n=substr($1, 1, RLENGTH); u=substr($1, RLENGTH+1);
         m=(u=="kB"||u=="KB")?1e3:(u=="MB")?1e6:(u=="GB")?1e9:(u=="TB")?1e12:(u=="B"||u=="")?1:0; s+=n*m } } END { printf "%.0f\n", s+0 }'
}
job_main() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    ops_state containers-prune ok "n/a: docker unavailable"; return 0
  fi
  local rc=0 bytes gb out
  out=$(ops_run docker image prune -f 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" != 0 ]; then ops_state containers-prune warn "docker image prune failed (rc=$rc)"; return 0; fi
  bytes=$(docker system df --format '{{json .}}' 2>/dev/null | jq -r '.Reclaimable // empty' 2>/dev/null | _cp_bytes)
  bytes=${bytes:-0}
  if [ "$bytes" -gt 10000000000 ] && ops_root_enabled; then   # the volumes prune is a root action: never offered when root is off
    gb=$(( (bytes + 500000000) / 1000000000 ))
    ops_ask containers-prune "Reclaim $gb GB (anonymous volumes and unused data; named volumes are kept on Docker ≥23)?" "root:containers-prune volumes"
    ops_state containers-prune ok "images pruned; $gb GB reclaimable, asked about volumes"
  else
    ops_state containers-prune ok "images pruned"
  fi
}
