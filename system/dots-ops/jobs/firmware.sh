# firmware (root): refresh LVFS metadata, ask before installing any firmware update. fwupd absent -> ok n/a.
job_main() {
  local rc=0 json n ask="$OPS_ROOT_STATE/ask-firmware.json"
  command -v fwupdmgr >/dev/null || { ops_state firmware ok "n/a: fwupd not installed"; return 0; }
  ops_run fwupdmgr refresh --force -y || rc=$?
  case $rc in 0|2) ;; *) ops_state firmware warn "fwupdmgr refresh failed (rc=$rc)"; return 0 ;; esac   # 2 = nothing to do
  json=$(fwupdmgr get-updates --json 2>/dev/null) || true   # exit 2 = no updates
  n=$(jq -r '[.Devices[]? | select((.Releases // []) | length > 0)] | length' <<< "$json" 2>/dev/null) || n=0
  [[ ${n:-0} =~ ^[0-9]+$ ]] || n=0
  if [ "$n" -gt 0 ]; then
    ops_ask firmware "Install firmware updates for $n device(s)?" "root:firmware apply"
    ops_state firmware warn "$n firmware update(s) pending"
  else
    rm -f "$ask"
    ops_state firmware ok "firmware up to date"
  fi
}
