# firewall (root): bring the host firewall to the ruleset in firewall.json (R39), never without the owner's say-so the
# first time. ufw on arch/debian, firewalld on fedora; NixOS uses networking.firewall (dots-ops.nix) -> ok n/a.
#   live state matches            -> ok (stale ask withdrawn)
#   differs, never applied here   -> ALWAYS ask with the diff (no /var/lib/dots-ops/firewall.applied)  [Review Focus 5]
#   differs, same rules hash      -> drift: warn naming what differs + ask; NEVER re-applied silently (R44: hand changes win)
#   differs, rules hash changed   -> ask again
# Every ask writes the rendered target's hash to firewall.pending-hash; the apply action refuses when the current
# firewall.json renders to another hash (R46: an approval covers exactly the ruleset that was shown).
# Additive by design (R41): rules the owner added by hand are kept; nothing is ever deleted, and allow rules always land
# before the default-deny/enable step, so an approved apply cannot cut off ssh or kdeconnect. A rule for the same
# port/proto narrowed to an interface or source (e.g. `22/tcp on tailscale0`, `22/tcp ALLOW IN 192.168.1.0/24`) counts
# as present (R44). The apply action (actions/firewall/apply.sh) sources this file and calls _fw_apply.
: "${OPS_SYS_DIR:=/usr/local/lib/dots-ops}"

# _fw_setup: tool + rules + rendered target + hash. 1 = nothing to do, with _fw_st (ok|warn) and _fw_msg set.
_fw_setup() {
  local fam rules line port proto why
  _fw_tool=""; _fw_rules=(); _fw_cmds=""; _fw_hash=""; _fw_zone=""; _fw_running=0; _fw_st=ok; _fw_msg=""
  fam=$(ops_family)
  case $fam in
    nixos)        _fw_msg="n/a: managed by networking.firewall"; return 1 ;;
    arch|debian)  _fw_tool=ufw ;;
    fedora)       _fw_tool=firewalld ;;
    *)            _fw_msg="n/a: unsupported distro"; return 1 ;;
  esac
  if [ "$_fw_tool" = ufw ]; then
    command -v ufw >/dev/null 2>&1 || { _fw_msg="n/a: ufw not installed"; return 1; }
    if systemctl is-active --quiet firewalld.service 2>/dev/null; then   # two managers fighting over netfilter = surprise lockouts
      _fw_msg="n/a: firewalld is active; not managing ufw alongside it"; return 1
    fi
  else
    command -v firewall-cmd >/dev/null 2>&1 || { _fw_msg="n/a: firewalld not installed"; return 1; }
  fi
  rules=$OPS_SYS_DIR/firewall.json
  # strict schema: root builds commands from this file, so only digits/ranges and tcp|udp get through
  if ! jq -e '.default_incoming == "deny" and (.allow | type == "array" and length > 0)
             and all(.allow[]; ((.port | tostring) | test("^[0-9]{1,5}(:[0-9]{1,5})?$")) and (.proto == "tcp" or .proto == "udp"))' \
       "$rules" >/dev/null 2>&1; then
    _fw_st=warn; _fw_msg="invalid or missing $rules (need default_incoming deny + allow[] of port/proto)"; return 1
  fi
  while IFS=$'\t' read -r port proto why; do _fw_rules+=("$port"$'\t'"$proto"$'\t'"$why"); done \
    < <(jq -r '.allow[] | [(.port | tostring), .proto, ((.why // "") | gsub("[^A-Za-z0-9 _.-]"; ""))] | @tsv' "$rules")
  if [ "$_fw_tool" = ufw ]; then
    for line in "${_fw_rules[@]}"; do IFS=$'\t' read -r port proto why <<< "$line"; _fw_cmds+="ufw allow $port/$proto"$'\n'; done
    _fw_cmds+="ufw default deny incoming"$'\n'"ufw --force enable"$'\n'   # after the allows: no window without ssh
    _fw_cmds+="systemctl enable ufw.service"$'\n'   # R45: Arch does not enable it; ufw would be off after every reboot
  else
    local fwc=(firewall-offline-cmd) dev
    if firewall-cmd --state >/dev/null 2>&1; then _fw_running=1; fwc=(firewall-cmd); fi
    # R47: the zone that filters the uplink = zone of the default-route interface; an unbound interface -> default zone
    dev=$(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}') || dev=""
    if [[ $dev =~ ^[A-Za-z0-9_.@:-]+$ ]]; then _fw_zone=$("${fwc[@]}" "--get-zone-of-interface=$dev" 2>/dev/null) || _fw_zone=""; fi
    [ -n "$_fw_zone" ] || { _fw_zone=$("${fwc[@]}" --get-default-zone 2>/dev/null) || _fw_zone=""; }
    [ -n "$_fw_zone" ] || _fw_zone=public
    [[ $_fw_zone =~ ^[A-Za-z0-9_-]+$ ]] || { _fw_st=warn; _fw_msg="unexpected firewalld zone '$_fw_zone'"; return 1; }
    for line in "${_fw_rules[@]}"; do
      IFS=$'\t' read -r port proto why <<< "$line"
      _fw_cmds+="firewall-cmd --permanent --zone=$_fw_zone --add-port=${port/:/-}/$proto"$'\n'
    done
    _fw_cmds+="firewall-cmd --reload"$'\n'
  fi
  _fw_hash=$(printf '%s' "$_fw_cmds" | sha256sum | cut -d' ' -f1)
}

# _fw_live: compare with the live state; fills _fw_items (one human-readable change per entry). 1 = could not read it.
_fw_live() {
  local out line port proto why spec q ports
  _fw_items=(); _fw_target=default
  if [ "$_fw_tool" = ufw ]; then
    out=$(ufw status verbose 2>&1) || { _fw_msg="ufw status failed: $(printf '%s\n' "$out" | tail -n 1)"; return 1; }
    for line in "${_fw_rules[@]}"; do   # inactive ufw lists no rules: everything counts as missing
      IFS=$'\t' read -r port proto why <<< "$line"; spec=$port/$proto
      # any v4 ALLOW/LIMIT for this port/proto counts, also when narrowed to an interface or a source (R44)
      grep -Eq "^${spec}( on [^[:space:]]+)?[[:space:]]+(ALLOW|LIMIT)( IN)?[[:space:]]+[^[:space:]]" <<< "$out" || _fw_items+=("allow $spec ($why)")
    done
    grep -Eq '^Default: (deny|reject) \(incoming\)' <<< "$out" || _fw_items+=("default deny incoming")
    grep -q '^Status: active' <<< "$out" || _fw_items+=("enable ufw")
    [ "$(systemctl is-enabled ufw.service 2>/dev/null)" = enabled ] || _fw_items+=("enable ufw.service at boot")
  else
    if [ "$_fw_running" = 1 ]; then q=(firewall-cmd --permanent "--zone=$_fw_zone"); else q=(firewall-offline-cmd "--zone=$_fw_zone"); fi
    ports=$("${q[@]}" --list-ports 2>/dev/null) || ports=""
    _fw_target=$("${q[@]}" --get-target 2>/dev/null) || _fw_target=default
    for line in "${_fw_rules[@]}"; do
      IFS=$'\t' read -r port proto why <<< "$line"; spec=${port/:/-}/$proto
      case " $ports " in *" $spec "*) ;; *) _fw_items+=("allow $spec ($why) in zone $_fw_zone") ;; esac
    done
    [ "$_fw_target" != ACCEPT ] || _fw_items+=("zone $_fw_zone target ACCEPT -> default (deny unlisted incoming)")
    [ "$_fw_running" = 1 ] || _fw_items+=("start + enable firewalld")
  fi
}

# _fw_apply <summary>: run the rendered target via ops_run; record the rules hash. 1 = a step failed (state fail).
_fw_apply() {
  local line w rc p
  _fw_step() {   # words...: one ops_run step; on failure record fail and stop
    local out rc=0
    out=$(ops_run "$@" 2>&1) || rc=$?
    [ -z "$out" ] || printf '%s\n' "$out"
    [ "$rc" = 0 ] && return 0
    ops_state firewall fail "'$*' failed (rc=$rc): $(printf '%s\n' "$out" | tail -n 2 | tr '\n' ' ')"; return 1
  }
  if [ "$_fw_tool" = ufw ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      read -ra w <<< "$line"; _fw_step "${w[@]}" || return 1
    done <<< "$_fw_cmds"
  elif [ "$_fw_running" = 1 ]; then
    while IFS= read -r line; do
      [[ $line == *--add-port=* ]] || continue
      read -ra w <<< "$line"; _fw_step "${w[@]}" || return 1
    done <<< "$_fw_cmds"
    if [ "$_fw_target" = ACCEPT ]; then _fw_step firewall-cmd --permanent "--zone=$_fw_zone" --set-target=default || return 1; fi
    _fw_step firewall-cmd --reload || return 1
  else   # stopped: write the rules offline first, so the daemon comes up with ssh/kdeconnect already open
    while IFS= read -r line; do
      [[ $line == *--add-port=* ]] || continue
      p=${line##*--add-port=}; _fw_step firewall-offline-cmd "--zone=$_fw_zone" "--add-port=$p" || return 1
    done <<< "$_fw_cmds"
    if [ "$_fw_target" = ACCEPT ]; then _fw_step firewall-offline-cmd "--zone=$_fw_zone" --set-target=default || return 1; fi
    _fw_step systemctl enable --now firewalld.service || return 1
  fi
  if [ "${DOTS_OPS_DRY_RUN:-0}" = 1 ]; then ops_log firewall info "dry run: nothing recorded"; return 0; fi
  mkdir -p "$OPS_ROOT_STATE"
  jq -cn --arg h "$_fw_hash" --arg tool "$_fw_tool" --argjson t "$(ops_now)" '{hash:$h,tool:$tool,applied:$t}' \
    > "$OPS_ROOT_STATE/firewall.applied.tmp" && mv "$OPS_ROOT_STATE/firewall.applied.tmp" "$OPS_ROOT_STATE/firewall.applied"
  rm -f "$OPS_ROOT_STATE/ask-firewall.json" "$OPS_ROOT_STATE/firewall.pending-hash"
  ops_state firewall ok "$1"
}

# _fw_ask <question>: ask for root:firewall apply and bind the approval to the hash being shown (R46)
_fw_ask() {
  mkdir -p "$OPS_ROOT_STATE"
  printf '%s\n' "$_fw_hash" > "$OPS_ROOT_STATE/firewall.pending-hash.tmp" \
    && mv "$OPS_ROOT_STATE/firewall.pending-hash.tmp" "$OPS_ROOT_STATE/firewall.pending-hash"
  ops_ask firewall "$1" "root:firewall apply"
}

job_main() {
  local prev diff note ask="$OPS_ROOT_STATE/ask-firewall.json"
  _fw_setup || { ops_state firewall "$_fw_st" "$_fw_msg"; return 0; }
  _fw_live || { ops_state firewall warn "$_fw_msg"; return 0; }
  if [ "${#_fw_items[@]}" -eq 0 ]; then
    rm -f "$ask" "$OPS_ROOT_STATE/firewall.pending-hash"; ops_state firewall ok "in sync ($_fw_tool)"; return 0
  fi
  diff=$(printf '%s; ' "${_fw_items[@]}"); diff=${diff%; }
  prev=$(jq -r '.hash // empty' "$OPS_ROOT_STATE/firewall.applied" 2>/dev/null) || prev=""
  if [ "$_fw_tool" = ufw ]; then note="Note: ufw does not filter Docker-published ports (Docker writes its own iptables rules)."
  else note="Note: Docker-published ports bypass firewalld zones."; fi
  if [ -z "$prev" ]; then
    _fw_ask "Firewall ($_fw_tool) first apply on this machine — will: $diff. Rules you added yourself are kept. $note Apply?"
    ops_state firewall warn "first apply awaits approval (${#_fw_items[@]} changes)"
  elif [ "$prev" = "$_fw_hash" ]; then   # R44: someone changed the live firewall; their change stands until the owner says otherwise
    _fw_ask "Firewall ($_fw_tool) drifted from the approved rules — re-apply will: $diff. Rules you added yourself are kept. $note Re-apply?"
    ops_state firewall warn "drift: $diff"
  else
    _fw_ask "Firewall ($_fw_tool) rules changed since the last apply — will: $diff. Rules you added yourself are kept. $note Apply?"
    ops_state firewall warn "changed rules await approval (${#_fw_items[@]} changes)"
  fi
}
