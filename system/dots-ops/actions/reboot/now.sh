# reboot / now (approved root action): reboot immediately.
rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"
ops_run systemctl reboot
