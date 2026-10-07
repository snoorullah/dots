# audit (root, heavy): lynis hardening index + warnings, compared with the previous run (audit-last.json);
# score drop or new warning ids -> warn. Arch also runs arch-audit -q (vulnerable packages -> warn). No lynis -> ok n/a.
# Weekly timer, and also pulled by dots-ops-system-idle.target like every heavy root job; it skips itself when the
# last audit is younger than 6 days unless forced (`dots-ops run audit --now`), so idle periods don't rerun lynis.
OPS_HEAVY=1
job_main() {
  local rep="$OPS_ROOT_DATA/lynis-report.dat" last="$OPS_ROOT_DATA/audit-last.json" now t rc=0 out
  local idx nw prev_idx new n vul issues=() base
  now=$(ops_now)
  command -v lynis >/dev/null 2>&1 || { ops_state audit ok "n/a: lynis not installed"; return 0; }
  t=$(jq -r '.t // 0' "$last" 2>/dev/null) || t=0
  [[ $t =~ ^[0-9]+$ ]] || t=0
  if [ "${OPS_FORCE:-0}" != 1 ] && [ $((now - t)) -lt 518400 ]; then
    ops_log audit info "skipped: last audit $(( (now - t) / 3600 ))h ago (weekly)"; return 0
  fi
  if [ "${DOTS_OPS_DRY_RUN:-0}" = 1 ]; then
    ops_run lynis audit system --quick --no-colors --report-file "$rep"; return 0
  fi
  mkdir -p "$OPS_ROOT_DATA"; rm -f "$rep"   # never parse a stale report
  out=$(ops_run lynis audit system --quick --no-colors --report-file "$rep" 2>&1) || rc=$?
  idx=$(sed -n 's/^hardening_index=\([0-9][0-9]*\)$/\1/p' "$rep" 2>/dev/null | tail -n 1) || idx=""
  if [ -z "$idx" ]; then
    ops_state audit warn "lynis produced no hardening index (rc=$rc): $(printf '%s\n' "$out" | tail -n 1)"; return 0
  fi
  nw=$(grep -c '^warning\[\]=' "$rep" 2>/dev/null) || nw=0
  local cur; cur=$(sed -n 's/^warning\[\]=\([^|]*\)|.*/\1/p' "$rep" | sort -u | jq -Rsc 'split("\n") | map(select(length > 0))')
  base="index $idx, $nw warning(s)"
  if [ -f "$last" ] && prev_idx=$(jq -er '.hardening_index' "$last" 2>/dev/null); then
    [ "$idx" -ge "$prev_idx" ] || issues+=("hardening index $prev_idx -> $idx")
    new=$(jq -r --argjson cur "$cur" '($cur - (.warnings // [])) | join(" ")' "$last" 2>/dev/null) || new=""
    if [ -n "$new" ]; then n=$(wc -w <<< "$new"); issues+=("$n new warning(s): $new"); fi
  else
    base="baseline: $base"
  fi
  jq -cn --argjson i "$idx" --argjson w "$cur" --argjson t "$now" '{hardening_index:$i,warnings:$w,t:$t}' > "$last.tmp" && mv "$last.tmp" "$last"
  if [ "$(ops_family)" = arch ] && command -v arch-audit >/dev/null 2>&1; then
    vul=$(arch-audit -q 2>/dev/null) || vul=""
    n=$(printf '%s\n' "$vul" | grep -c . || true)
    [ "$n" = 0 ] || issues+=("$n vulnerable packages (arch-audit)")
  fi
  if [ "${#issues[@]}" -gt 0 ]; then
    ops_state audit warn "$(printf '%s; ' "${issues[@]}" | sed 's/; $//') [$base]"
  else
    ops_state audit ok "$base"
  fi
}
