# firewall / apply (approved root action, sourced by dots-ops-run with lib loaded, set -euo pipefail):
# apply the rendered firewall.json target (allows first, then default deny + enable) and record its hash in
# /var/lib/dots-ops/firewall.applied, which later lets the firewall job re-apply the same ruleset after drift.
# $P is the runner's root-owned prefix (/usr/local/lib/dots-ops, or the Nix store path on NixOS).
OPS_SYS_DIR=${P:?}
if [ "$EUID" = 0 ] && ! ops_file_trusted "$P/jobs" "$P/jobs/firewall.sh" "$P/firewall.json"; then   # R20
  ops_state firewall fail "refused: firewall job or rules not root-owned"; exit 1
fi
source "$P/jobs/firewall.sh"
if ! _fw_setup; then ops_state firewall "$_fw_st" "$_fw_msg"; [ "$_fw_st" = ok ] && return 0; exit 1; fi
_fw_live || { ops_state firewall fail "$_fw_msg"; exit 1; }
_fw_apply "applied ($_fw_tool, approved)" || exit 1
