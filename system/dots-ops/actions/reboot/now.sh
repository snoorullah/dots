# reboot / now (approved root action): reboot immediately.
ops_run systemctl reboot
rm -f "$OPS_ROOT_STATE/ask-reboot-needed.json"   # only once the command succeeded (set -e stops us otherwise)
