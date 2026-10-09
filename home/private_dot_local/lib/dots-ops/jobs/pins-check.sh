# pins-check: weekly; compares extra-tools.yaml pins and the nixpkgs lock age with upstream.
: "${OPS_DOTS_REPO:=$(git -C "$(chezmoi source-path 2>/dev/null)" rev-parse --show-toplevel 2>/dev/null)}"
pins_latest() {   # kind name -> latest version on stdout, non-zero on failure
  local enc
  case $1 in
    npm)   enc=${2//\//%2F}   # the registry takes @scope%2Fname
           curl -fsS --max-time 15 "https://registry.npmjs.org/$enc/latest" | jq -er .version ;;
    cargo) curl -fsS --max-time 15 -A "dots-ops pins-check" "https://crates.io/api/v1/crates/$2" | jq -er .crate.max_stable_version ;;
    pipx|uv) curl -fsS --max-time 15 "https://pypi.org/pypi/$2/json" | jq -er .info.version ;;
    *) return 1 ;;
  esac
}
job_main() {
  local y="$OPS_DOTS_REPO/home/.chezmoidata/extra-tools.yaml" out="[]" failed=0 kind name from to auto
  [ -n "$OPS_DOTS_REPO" ] && [ -f "$y" ] || { ops_state pins-check ok "n/a: no dots repo"; return 0; }
  while IFS=$'\t' read -r kind name from; do
    to=$(pins_latest "$kind" "$name" 2>/dev/null) || { failed=1; continue; }
    [[ $to =~ ^[A-Za-z0-9._+-]+$ ]] || { failed=1; continue; }   # same charset pins-bump accepts
    [ "$to" = "$from" ] && continue
    auto=true; [ "$kind" = uv ] && auto=false
    out=$(jq -c --arg k "$kind" --arg n "$name" --arg f "$from" --arg t "$to" --argjson a "$auto" \
      '. + [{kind:$k,name:$n,from:$f,to:$t,auto:$a}]' <<<"$out")
  done < <(yq -o=tsv '[((.extraTools.npm // [])[] | ["npm", .name, .version]),
                       ((.extraTools.cargo // [])[] | ["cargo", .crate, .version]),
                       ((.extraTools.pipx // [])[] | ["pipx", .name, .version]),
                       ((.extraTools.uv // [])[] | ["uv", .name, .version])] | .[]' "$y")
  printf '%s\n' "$out" > "$OPS_STATE/pins-candidates.json"
  local n age days max sum=""
  n=$(jq length <<<"$out")
  age=$(jq -r '.nodes.nixpkgs.locked.lastModified // 0' "$OPS_DOTS_REPO/nix/flake.lock" 2>/dev/null || echo 0)
  [[ $age =~ ^[0-9]+$ ]] || age=0
  days=$(( ( $(date +%s) - age ) / 86400 )); max=${OPS_LOCK_MAX_DAYS:-$(ops_cfg pins.lock_max_days 30)}
  [ "$age" -eq 0 ] && days=0   # no lock / no timestamp: nothing to age
  [ "$n" -gt 0 ] && sum="$n pins behind: $(jq -r 'map("\(.name) \(.from)→\(.to)\(if .auto then "" else " (manual)" end)")|join(", ")' <<<"$out")"
  [ "$days" -gt "$max" ] && sum="${sum:+$sum; }nixpkgs lock $days days old"
  [ "$failed" = 1 ] && sum="${sum:+$sum; }check failed for some registries"
  if [ -z "$sum" ]; then ops_state pins-check ok "all pins current"; return 0; fi
  ops_state pins-check warn "$sum"
  if [ "$(jq '[.[]|select(.auto)]|length' <<<"$out")" -gt 0 ] || [ "$days" -gt "$max" ]; then
    ops_ask pins-check "$sum — open a bump PR?" "user:dots-ops pins-bump"
  fi
}
