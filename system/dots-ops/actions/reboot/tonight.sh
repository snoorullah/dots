# reboot / tonight (approved root action): schedule a reboot at 03:00 (cancel with `shutdown -c`).
ops_run shutdown -r 03:00
rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"   # only once the command succeeded (set -e stops us otherwise)
ops_state reboot-needed warn "reboot scheduled for 03:00 (shutdown -c cancels)"
