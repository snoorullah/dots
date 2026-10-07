# firewall / apply (approved root action, sourced by dots-ops-run with lib loaded, set -euo pipefail):
# apply the rendered firewall.json target (allows first, then default deny + enable) and record its hash in
# /var/lib/dots-ops/firewall.applied. R46: only the ruleset the owner was shown — the job wrote its hash to
# firewall.pending-hash when it asked; a different current hash (firewall.json or zone changed since) is refused.
# $P is the runner's root-owned prefix (/usr/local/lib/dots-ops, or the Nix store path on NixOS).
OPS_SYS_DIR=${P:?}
if [ "$EUID" = 0 ] && ! ops_file_trusted "$P/jobs" "$P/jobs/firewall.sh" "$P/firewall.json"; then   # R20
  ops_state firewall fail "refused: firewall job or rules not root-owned"; exit 1
fi
source "$P/jobs/firewall.sh"
if ! _fw_setup; then ops_state firewall "$_fw_st" "$_fw_msg"; [ "$_fw_st" = ok ] && return 0; exit 1; fi
_fw_pending=$(head -n 1 "$OPS_ROOT_STATE/firewall.pending-hash" 2>/dev/null) || _fw_pending=""
if [ "$_fw_pending" != "$_fw_hash" ]; then
  rm -f "$OPS_ROOT_STATE/ask-firewall.json" "$OPS_ROOT_STATE/firewall.pending-hash"
  ops_state firewall fail "rules changed since approval — re-asking"
  ops_run systemctl start --no-block dots-ops@firewall.service || true   # the job shows the current diff in a new ask
  exit 1
fi
_fw_live || { ops_state firewall fail "$_fw_msg"; exit 1; }
_fw_apply "applied ($_fw_tool, approved)" || exit 1
