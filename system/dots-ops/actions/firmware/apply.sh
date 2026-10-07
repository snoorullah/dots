# firmware / apply (approved root action): install the pending firmware updates; the reboot itself stays the owner's call.
_fw_rc=0
_fw_out=$(ops_run fwupdmgr update -y --no-reboot-check 2>&1) || _fw_rc=$?
[ -z "$_fw_out" ] || printf '%s\n' "$_fw_out"
if [ "$_fw_rc" = 0 ]; then
  rm -f "$OPS_ROOT_STATE/ask-firmware.json"
  ops_state firmware ok "firmware updated (a reboot may finish it)"
else
  ops_state firmware fail "fwupdmgr update failed (rc=$_fw_rc): $(printf '%s\n' "$_fw_out" | tail -n 3 | tr '\n' ' ')"
  unset _fw_rc _fw_out; exit 1
fi
unset _fw_rc _fw_out
