# reboot / tonight (approved root action): schedule a reboot at 03:00 (cancel with `shutdown -c`).
rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"
ops_run shutdown -r 03:00
ops_state reboot-needed warn "reboot scheduled for 03:00 (shutdown -c cancels)"
