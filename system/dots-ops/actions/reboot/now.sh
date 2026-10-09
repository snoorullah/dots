# reboot / now (approved root action): reboot immediately — but never in the middle of a package transaction (R56).
# Refused: warn, exit non-zero, the ask stays; reboot-needed re-asks after the transaction (updates-full/-security start it).
if ops_pkg_busy; then
  ops_state reboot-needed warn "package transaction running — try again"
  exit 1
fi
ops_run systemctl reboot
rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"   # only once the command succeeded (set -e stops us otherwise)
