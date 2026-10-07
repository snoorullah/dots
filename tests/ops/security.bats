load helpers
bats_require_minimum_version 1.5.0
# Security domain: audit (lynis + arch-audit), firewall (ufw/firewalld from firewall.json), ssh-harden (sshd drop-in),
# their apply actions, timers, installer + root-layer packages, NixOS module. Review Focus 5: nothing here may lock the
# owner out — the first firewall run only asks, ssh-harden never touches sshd without authorized_keys.
# Every external tool is a stub in $BIN (first on PATH); homes, sshd_config and sshd_config.d are temp dirs.
R="$BATS_TEST_DIRNAME/../.."
SJ="$R/system/dots-ops/jobs"
SA="$R/system/dots-ops/actions"
SU="$R/system/dots-ops/units"
LIB="$R/home/private_dot_local/lib/dots-ops/lib.sh"

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }

setup() {
  setup_ops
  export BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export ORIG_PATH="$PATH" PATH="$BIN:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/root" OPS_STATE="$BATS_TEST_TMPDIR/rootlog"
  mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks" "$OPS_ROOT_STATE/root"
  export OPS_SYS_DIR="$R/system/dots-ops" P="$R/system/dots-ops"   # P = the runner's prefix when an action is sourced
  # ssh fixtures
  export OPS_SSHD_CONFIG="$BATS_TEST_TMPDIR/etc-ssh/sshd_config" OPS_SSHD_DIR="$BATS_TEST_TMPDIR/etc-ssh/sshd_config.d"
  mkdir -p "$OPS_SSHD_DIR"; printf 'Include /etc/ssh/sshd_config.d/*.conf\nUsePAM yes\n' > "$OPS_SSHD_CONFIG"
  export OPS_OWNER_FILE="$BATS_TEST_TMPDIR/owner"; echo alice > "$OPS_OWNER_FILE"
  umask 022   # sshd StrictModes semantics are tested explicitly; key files must not inherit a 002 umask by accident
  export OWNER_HOME="$BATS_TEST_TMPDIR/home-alice"; mkdir -p "$OWNER_HOME/.ssh"; chmod 755 "$OWNER_HOME"; chmod 700 "$OWNER_HOME/.ssh"
  # the owner's uid is the test runner's uid, so StrictModes ownership checks see "owned by the owner"
  mkstub getent '[ "$1" = passwd ] && [ "$2" = "${STUB_OWNER:-alice}" ] && { echo "$2:x:$(id -u):$(id -g)::$OWNER_HOME:/bin/bash"; exit 0; }; exit 2'
  # systemctl: STUB_ACTIVE / STUB_UNITS are space-separated unit names (is-active/is-enabled, cat);
  # is-enabled without --quiet prints enabled/disabled like the real one
  mkstub systemctl 'echo "systemctl $*" >> "$STUB_LOG"
for last; do :; done
has() { case " $1 " in *" $last "*) return 0 ;; esac; return 1; }
case " $* " in
  *" is-enabled "*) if has "${STUB_ACTIVE:-}"; then case " $* " in *" --quiet "*) ;; *) echo enabled ;; esac; exit 0; fi
                    case " $* " in *" --quiet "*) ;; *) echo disabled ;; esac; exit 1 ;;
  *" is-active "*) has "${STUB_ACTIVE:-}" && exit 0; exit 3 ;;
  *" cat "*) has "${STUB_UNITS:-}" && exit 0; exit 1 ;;
esac
[ -z "${STUB_SYSTEMCTL_FAIL:-}" ] || exit 1
exit 0'
  # sshd: -t rc from STUB_SSHD_T_RC; -T -C prints STUB_SSHD_TC (unset = fails, like sshd without host keys);
  # plain -T prints STUB_SSHD_EFFECTIVE; -V reports OpenSSH_$STUB_SSHD_VER on stderr
  mkstub sshd 'echo "sshd $*" >> "$STUB_LOG"
case "$1" in
  -t) exit ${STUB_SSHD_T_RC:-0} ;;
  -T) if [ "$2" = -C ]; then [ -n "${STUB_SSHD_TC:-}" ] || exit 1; printf "%b" "$STUB_SSHD_TC"; exit 0; fi
      printf "%b" "${STUB_SSHD_EFFECTIVE:-}"; exit 0 ;;
  -V) echo "OpenSSH_${STUB_SSHD_VER:-9.6}p1, OpenSSL 3.0.13" >&2; exit 0 ;;
esac; exit 0'
  mkstub ip '[ "${STUB_IP_DEV:-eth0}" = none ] && exit 0; echo "default via 192.168.1.1 dev ${STUB_IP_DEV:-eth0} proto dhcp metric 600"'
  # ufw: status verbose prints $STUB_UFW_STATUS
  mkstub ufw 'echo "ufw $*" >> "$STUB_LOG"
case "$*" in "status verbose") printf "%b" "${STUB_UFW_STATUS:-Status: inactive\n}"; exit ${STUB_UFW_RC:-0} ;; esac; exit 0'
  mkstub firewall-cmd 'echo "firewall-cmd $*" >> "$STUB_LOG"
case " $* " in
  *" --state "*) [ "${STUB_FWD_RUNNING:-1}" = 1 ] && { echo running; exit 0; }; echo "not running"; exit 252 ;;
  *" --get-zone-of-interface="*) [ -n "${STUB_FWD_IFZONE:-}" ] || { echo "no zone"; exit 2; }; echo "$STUB_FWD_IFZONE" ;;
  *" --get-default-zone "*) echo "${STUB_FWD_ZONE:-public}" ;;
  *" --list-ports "*) echo "${STUB_FWD_PORTS:-}" ;;
  *" --get-target "*) echo "${STUB_FWD_TARGET:-default}" ;;
esac; exit 0'
  mkstub firewall-offline-cmd 'echo "firewall-offline-cmd $*" >> "$STUB_LOG"
case " $* " in
  *" --get-zone-of-interface="*) [ -n "${STUB_FWD_IFZONE:-}" ] || { echo "no zone"; exit 2; }; echo "$STUB_FWD_IFZONE" ;;
  *" --get-default-zone "*) echo "${STUB_FWD_ZONE:-public}" ;;
  *" --list-ports "*) echo "${STUB_FWD_PORTS:-}" ;;
  *" --get-target "*) echo "${STUB_FWD_TARGET:-default}" ;;
esac; exit 0'
  # lynis writes $STUB_LYNIS_REPORT to the --report-file path
  mkstub lynis 'echo "lynis $*" >> "$STUB_LOG"
while [ $# -gt 0 ]; do [ "$1" = --report-file ] && { printf "%b" "${STUB_LYNIS_REPORT:-}" > "$2"; }; shift; done
exit ${STUB_LYNIS_RC:-0}'
  mkstub arch-audit 'echo "arch-audit $*" >> "$STUB_LOG"; printf "%b" "${STUB_ARCH_AUDIT:-}"'
}
os() { printf '%b' "$1" > "$BATS_TEST_TMPDIR/os"; export OPS_OS_RELEASE="$BATS_TEST_TMPDIR/os"; }
DEB='ID=ubuntu\nID_LIKE=debian\n'; ARCH='ID=arch\n'; FED='ID=fedora\n'; NIX='ID=nixos\n'
runjob() { source "$SJ/$1.sh"; job_main; }
rstate() { jq -r ".$2" "$OPS_ROOT_STATE/$1.json"; }
# runact <job> <action>: source the root action the way dots-ops-run does (lib loaded, set -euo pipefail)
runact() { bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/$1/$2.sh"; }
mutations() { grep -E '^(ufw (allow|default|--force|enable|deny|delete|reset)|firewall-cmd .*(--add|--set|--reload|--remove)|firewall-offline-cmd .*--add|systemctl (enable|reload|start|restart))' "$STUB_LOG" || true; }
UFW_OK='Status: active\nLogging: on (low)\nDefault: deny (incoming), allow (outgoing), disabled (routed)\nNew profiles: skip\n\nTo                         Action      From\n--                         ------      ----\n22/tcp                     ALLOW IN    Anywhere\n1714:1764/tcp              ALLOW IN    Anywhere\n1714:1764/udp              ALLOW IN    Anywhere\n22/tcp (v6)                ALLOW IN    Anywhere (v6)\n'
UFW_CMDS='ufw allow 22/tcp
ufw allow 1714:1764/tcp
ufw allow 1714:1764/udp
ufw default deny incoming
ufw --force enable
systemctl enable ufw.service'
fw_hash() {   # the hash the job records for the current rules (from its own render)
  ( source "$SJ/firewall.sh"; _fw_setup >/dev/null && printf '%s' "$_fw_hash" )
}
fw_rhash() {   # the state-independent ruleset hash recorded in firewall.applied
  ( source "$SJ/firewall.sh"; _fw_setup >/dev/null && printf '%s' "$_fw_rhash" )
}
pending() { fw_hash > "$OPS_ROOT_STATE/root/firewall.pending-hash"; }   # what the job writes when it asks (R46)
ufw_mut() { grep -E '^ufw |^systemctl enable ' "$STUB_LOG" | grep -v 'status verbose' || true; }
dryact() { env DOTS_OPS_DRY_RUN=1 bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/$1/$2.sh"; }
applied() { jq -cn --arg h "$1" '{hash:$h,applied:1,tool:"ufw"}' > "$OPS_ROOT_STATE/root/firewall.applied"; }

# ---- firewall.json ----
@test "firewall.json: default deny, ssh 22/tcp, kdeconnect 1714:1764 tcp+udp (R39)" {
  f="$R/system/dots-ops/firewall.json"
  [ "$(jq -r .default_incoming "$f")" = deny ]
  [ "$(jq -c '[.allow[] | "\(.port)/\(.proto)/\(.why)"]' "$f")" = '["22/tcp/ssh","1714:1764/tcp/kdeconnect","1714:1764/udp/kdeconnect"]' ]
}

# ---- firewall job ----
@test "firewall first run on this machine (ufw, inactive): asks with the diff + Docker note, never applies" {
  os "$DEB"; runjob firewall
  [ "$(rstate ask-firewall action)" = "root:firewall apply" ]
  q=$(rstate ask-firewall question)
  [[ $q == *"allow 22/tcp (ssh)"* && $q == *"allow 1714:1764/udp (kdeconnect)"* && $q == *"enable ufw"* ]]
  [[ $q == *"Docker"* && $q == *"first apply on this machine"* ]]
  [ "$(rstate firewall status)" = warn ]
  [ ! -e "$OPS_ROOT_STATE/root/firewall.applied" ]
  [ -z "$(mutations)" ]
}
@test "firewall ask binds the approval to the rules hash shown (R46: firewall.pending-hash)" {
  os "$DEB"; runjob firewall
  [ "$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")" = "$(fw_hash)" ]
}
@test "firewall first run even with only one rule missing still asks (no applied file)" {
  os "$ARCH"; export STUB_ACTIVE="ufw.service" STUB_UFW_STATUS="${UFW_OK/1714:1764\/udp              ALLOW IN    Anywhere\\n/}"
  runjob firewall
  [ -e "$OPS_ROOT_STATE/ask-firewall.json" ]
  q=$(rstate ask-firewall question); [[ $q == *"1714:1764/udp"* && $q != *"22/tcp (ssh)"* && $q != *"at boot"* ]]
  [ -z "$(mutations)" ]
}
@test "firewall: live state already matches (ufw.service enabled) -> ok, no ask, stale ask withdrawn" {
  os "$DEB"; export STUB_ACTIVE="ufw.service" STUB_UFW_STATUS="$UFW_OK"; echo '{}' > "$OPS_ROOT_STATE/ask-firewall.json"
  runjob firewall
  [ "$(rstate firewall status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]
  [ -z "$(mutations)" ]
}
@test "firewall (R45): ufw active but ufw.service not enabled at boot (Arch) -> a difference" {
  os "$ARCH"; export STUB_UFW_STATUS="$UFW_OK"
  runjob firewall
  [[ $(rstate ask-firewall question) == *"enable ufw.service at boot"* ]]
  [ -z "$(mutations)" ]
}
@test "firewall: LIMIT on ssh and reject default count as satisfied (never loosened)" {
  os "$DEB"; export STUB_ACTIVE="ufw.service"; s="${UFW_OK/22\/tcp                     ALLOW IN/22/tcp                     LIMIT IN}"
  export STUB_UFW_STATUS="${s/Default: deny/Default: reject}"
  runjob firewall
  [ "$(rstate firewall status)" = ok ]
}
@test "firewall (R44): ssh narrowed by hand to an interface or a source counts as present -> in sync" {
  os "$DEB"; export STUB_ACTIVE="ufw.service"
  export STUB_UFW_STATUS="${UFW_OK/22\/tcp                     ALLOW IN    Anywhere/22/tcp on tailscale0          ALLOW IN    Anywhere}"
  runjob firewall
  [ "$(rstate firewall status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]
  export STUB_UFW_STATUS="${UFW_OK/22\/tcp                     ALLOW IN    Anywhere/22/tcp                     ALLOW IN    192.168.1.0/24}"
  runjob firewall
  [ "$(rstate firewall status)" = ok ]; [ -z "$(mutations)" ]
}
@test "firewall (R44) drift with the same rules hash -> warn naming the drift + ask, NEVER re-applied" {
  os "$DEB"; applied "$(fw_rhash)"
  export STUB_UFW_STATUS='Status: inactive\n'
  runjob firewall
  [ -z "$(mutations)" ]
  [ "$(rstate firewall status)" = warn ]; [[ $(rstate firewall summary) == "drift: "*"enable ufw"* ]]
  [[ $(rstate ask-firewall question) == *"drifted from the approved rules"* ]]
  [ "$(rstate ask-firewall action)" = "root:firewall apply" ]
  [ "$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")" = "$(fw_hash)" ]
}
@test "firewall drift, rules changed since the last apply -> ask again, never applies" {
  os "$ARCH"; applied "0000deadbeef"
  export STUB_UFW_STATUS='Status: inactive\n'
  runjob firewall
  [ -e "$OPS_ROOT_STATE/ask-firewall.json" ]; [[ $(rstate ask-firewall question) == *"rules changed"* ]]
  [ -z "$(mutations)" ]; [ "$(jq -r .hash "$OPS_ROOT_STATE/root/firewall.applied")" = 0000deadbeef ]
}
@test "firewall nixos -> ok n/a managed by networking.firewall; no ufw/firewalld -> ok n/a" {
  os "$NIX"; runjob firewall
  [ "$(rstate firewall summary)" = "n/a: managed by networking.firewall" ]
  os "$DEB"; rm -f "$BIN/ufw"
  PATH="$BIN:/usr/bin:/bin" runjob firewall   # hermetic enough: ufw is not installed on the dev box either
  [ "$(rstate firewall status)" = ok ]; [[ $(rstate firewall summary) == "n/a: ufw not installed"* ]]
  [ -z "$(mutations)" ]
}
@test "firewall ufw family: firewalld already active -> ok n/a, ufw untouched" {
  os "$DEB"; export STUB_ACTIVE="firewalld.service"
  runjob firewall
  [ "$(rstate firewall status)" = ok ]; [[ $(rstate firewall summary) == *"firewalld is active"* ]]
  [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]
}
@test "firewall: malformed rules file -> warn, no ask, no commands" {
  os "$DEB"; mkdir -p "$BATS_TEST_TMPDIR/sys"; echo '{"default_incoming":"deny","allow":[{"port":"22;rm","proto":"tcp"}]}' > "$BATS_TEST_TMPDIR/sys/firewall.json"
  OPS_SYS_DIR="$BATS_TEST_TMPDIR/sys" runjob firewall
  [ "$(rstate firewall status)" = warn ]; [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]; [ -z "$(mutations)" ]
}
@test "firewall fedora first run: firewalld asks with the --permanent diff, never applies" {
  os "$FED"; export STUB_FWD_PORTS="22/tcp"
  runjob firewall
  q=$(rstate ask-firewall question)
  [[ $q == *"firewalld"* && $q == *"1714-1764/tcp"* && $q != *"allow 22/tcp"* ]]
  [ -z "$(mutations)" ]
}
@test "firewall fedora (R47): zone of the default-route interface, not the default zone" {
  os "$FED"; export STUB_IP_DEV=wlp2s0 STUB_FWD_IFZONE=home STUB_FWD_ZONE=public
  runjob firewall
  grep -qx 'firewall-cmd --get-zone-of-interface=wlp2s0' "$STUB_LOG"
  [[ $(rstate ask-firewall question) == *"in zone home"* ]]
  pending; run dryact firewall apply; [ "$status" -eq 0 ]
  [[ $output == *"+ firewall-cmd --permanent --zone=home --add-port=22/tcp"* ]]
}
@test "firewall fedora (R47): interface bound to no zone, or no default route -> default zone" {
  os "$FED"; export STUB_IP_DEV=eth0 STUB_FWD_ZONE=FedoraWorkstation
  runjob firewall; [[ $(rstate ask-firewall question) == *"in zone FedoraWorkstation"* ]]
  export STUB_IP_DEV=none; runjob firewall; [[ $(rstate ask-firewall question) == *"in zone FedoraWorkstation"* ]]
}

@test "firewall: ALLOW OUT / ALLOW FWD / LIMIT OUT lines never count as an incoming allow" {
  os "$DEB"; export STUB_ACTIVE="ufw.service"
  s="${UFW_OK/22\/tcp                     ALLOW IN    Anywhere/22/tcp                     ALLOW OUT   Anywhere}"
  s="${s/1714:1764\/tcp              ALLOW IN    Anywhere/1714:1764/tcp              ALLOW FWD   Anywhere}"
  export STUB_UFW_STATUS="${s/1714:1764\/udp              ALLOW IN    Anywhere/1714:1764/udp              LIMIT OUT   Anywhere}"
  runjob firewall
  q=$(rstate ask-firewall question)
  [[ $q == *"allow 22/tcp (ssh)"* && $q == *"allow 1714:1764/tcp (kdeconnect)"* && $q == *"allow 1714:1764/udp (kdeconnect)"* ]]
}
@test "firewalld (R49): target change and daemon start are in the rendered, hashed, shown list" {
  os "$FED"; export STUB_FWD_TARGET=default
  h_default=$(fw_hash)
  export STUB_FWD_TARGET=ACCEPT; h_accept=$(fw_hash); [ "$h_default" != "$h_accept" ]
  runjob firewall
  [[ $(rstate ask-firewall question) == *"Runs: firewall-cmd --permanent --zone=public --add-port=22/tcp; "*"firewall-cmd --permanent --zone=public --set-target=default; firewall-cmd --reload" ]]
  [ "$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")" = "$h_accept" ]
  rm -f "$OPS_ROOT_STATE/root/firewall.pending-hash"; export STUB_FWD_RUNNING=0
  [ "$(fw_hash)" != "$h_accept" ]
  runjob firewall
  [[ $(rstate ask-firewall question) == *"firewall-offline-cmd --zone=public --set-target=default; systemctl enable --now firewalld.service" ]]
  [ -z "$(mutations)" ]
}
@test "firewall (R48): render changes while an approval is pending -> withdrawn, not overwritten" {
  os "$DEB"; runjob firewall; h1=$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")
  echo "$h1" | sed 's/^./x/' > "$OPS_ROOT_STATE/root/firewall.pending-hash"   # pretend the pending ask showed another render
  runjob firewall
  [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]; [ ! -e "$OPS_ROOT_STATE/root/firewall.pending-hash" ]
  [ "$(rstate firewall status)" = warn ]
  [ "$(rstate firewall summary)" = "rules changed while an approval was pending — re-asking" ]
  runjob firewall   # next run asks fresh, bound to the current render
  [ -e "$OPS_ROOT_STATE/ask-firewall.json" ]; [ "$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")" = "$(fw_hash)" ]
  [ -z "$(mutations)" ]
}
@test "firewall (R48) end to end: ask A relayed -> rules change -> job run -> owner approves A -> nothing applied, fresh ask shown" {
  os "$DEB"
  export U="$BATS_TEST_TMPDIR/user" ROOTLOG="$OPS_STATE" LIB CLI="$R/home/private_dot_local/private_bin/executable_dots-ops"
  mkdir -p "$U/jobs"
  cat > "$BIN/runner" <<'RUN'
#!/bin/sh
# stands in for `sudo -n dots-ops-run <job> <action>`: source the root action as root context would
exec env OPS_IS_ROOT=1 OPS_STATE="$ROOTLOG" bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$P/actions/$1/$2.sh"
RUN
  chmod +x "$BIN/runner"
  asuser() { env OPS_IS_ROOT=0 OPS_STATE="$U" OPS_ASK_UI=0 OPS_LIB="$LIB" OPS_JOBS_DIR="$U/jobs" OPS_SUDO=env OPS_RUNNER="$BIN/runner" bash "$CLI" "$@"; }
  runjob firewall                                              # ask A (render H1)
  asuser relay; qa=$(jq -r .question "$U/pending/firewall.json"); [[ $qa != *8080* ]]
  # firewall.json changes (installer update): a second rule set under a new root-owned prefix
  cp -r "$R/system/dots-ops" "$BATS_TEST_TMPDIR/sys2"
  jq '.allow += [{"port":8080,"proto":"tcp","why":"dev"}]' "$R/system/dots-ops/firewall.json" > "$BATS_TEST_TMPDIR/sys2/firewall.json"
  export OPS_SYS_DIR="$BATS_TEST_TMPDIR/sys2" P="$BATS_TEST_TMPDIR/sys2"
  runjob firewall                                              # H2 != H1 -> withdraw
  [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]
  run asuser answer firewall approve                           # the owner clicks the OLD question before the relay ran
  [ -z "$(ufw_mut)" ]; [ ! -e "$OPS_ROOT_STATE/root/firewall.applied" ]
  [ "$(rstate firewall summary)" = "rules changed since approval — re-asking" ]
  grep -qx 'systemctl start --no-block dots-ops@firewall.service' "$STUB_LOG"
  runjob firewall                                              # what that restart runs: a fresh ask for H2
  asuser relay
  qb=$(jq -r .question "$U/pending/firewall.json"); [[ $qb == *"allow 8080/tcp (dev)"* ]]
  [ "$(cat "$OPS_ROOT_STATE/root/firewall.pending-hash")" = "$(fw_hash)" ]
  [ -z "$(ufw_mut)" ]
}

# ---- firewall apply (action) ----
@test "firewall apply dry-run (ufw, arch + debian): prints the exact commands, allows before deny+enable, records nothing" {
  for o in "$ARCH" "$DEB"; do
    os "$o"; pending; run dryact firewall apply
    [ "$status" -eq 0 ]
    [ "$(grep '^+ ' <<< "$output")" = "$(sed 's/^/+ /' <<< "$UFW_CMDS")" ]
  done
  [ ! -e "$OPS_ROOT_STATE/root/firewall.applied" ]; [ -z "$(mutations)" ]
}
@test "firewall apply dry-run (fedora, running): exact firewall-cmd --permanent commands then reload" {
  os "$FED"; pending; run dryact firewall apply
  [ "$status" -eq 0 ]
  [ "$(grep '^+ ' <<< "$output")" = "+ firewall-cmd --permanent --zone=public --add-port=22/tcp
+ firewall-cmd --permanent --zone=public --add-port=1714-1764/tcp
+ firewall-cmd --permanent --zone=public --add-port=1714-1764/udp
+ firewall-cmd --reload" ]
}
@test "firewall apply dry-run (fedora, stopped): rules land offline BEFORE firewalld starts; ACCEPT target tightened" {
  os "$FED"; export STUB_FWD_RUNNING=0 STUB_FWD_TARGET=ACCEPT STUB_FWD_ZONE=FedoraWorkstation
  pending; run dryact firewall apply
  [ "$status" -eq 0 ]
  [ "$(grep '^+ ' <<< "$output")" = "+ firewall-offline-cmd --zone=FedoraWorkstation --add-port=22/tcp
+ firewall-offline-cmd --zone=FedoraWorkstation --add-port=1714-1764/tcp
+ firewall-offline-cmd --zone=FedoraWorkstation --add-port=1714-1764/udp
+ firewall-offline-cmd --zone=FedoraWorkstation --set-target=default
+ systemctl enable --now firewalld.service" ]
}
@test "firewall apply (real, stubbed ufw): runs the commands, records the rules hash, withdraws the ask" {
  os "$DEB"; echo '{}' > "$OPS_ROOT_STATE/ask-firewall.json"; pending
  run runact firewall apply; [ "$status" -eq 0 ]
  [ "$(jq -r .hash "$OPS_ROOT_STATE/root/firewall.applied")" = "$(fw_rhash)" ]
  [ "$(rstate firewall status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-firewall.json" ]; [ ! -e "$OPS_ROOT_STATE/root/firewall.pending-hash" ]
  [ "$(ufw_mut)" = "$UFW_CMDS" ]
}
@test "firewall apply (R46): rules changed since the approval -> fail 're-asking', exit 1, nothing applied" {
  os "$DEB"; echo '{}' > "$OPS_ROOT_STATE/ask-firewall.json"; echo 0000deadbeef > "$OPS_ROOT_STATE/root/firewall.pending-hash"
  run runact firewall apply; [ "$status" -ne 0 ]
  [ "$(rstate firewall status)" = fail ]; [ "$(rstate firewall summary)" = "rules changed since approval — re-asking" ]
  [ -z "$(ufw_mut)" ]; [ ! -e "$OPS_ROOT_STATE/root/firewall.applied" ]
  grep -qx 'systemctl start --no-block dots-ops@firewall.service' "$STUB_LOG"   # the job re-asks with the current diff
  rm -f "$OPS_ROOT_STATE/root/firewall.pending-hash"; : > "$STUB_LOG"   # no pending hash at all (approval of an old ask) -> same
  run runact firewall apply; [ "$status" -ne 0 ]; [ -z "$(ufw_mut)" ]
}
@test "firewall apply: a failing command -> fail, nothing recorded, exit 1" {
  os "$DEB"; pending; mkstub ufw 'echo "ufw $*" >> "$STUB_LOG"; case "$*" in "status verbose") echo "Status: inactive";; "default"*) exit 1;; esac; exit 0'
  run runact firewall apply; [ "$status" -eq 1 ]
  [ "$(rstate firewall status)" = fail ]; [ ! -e "$OPS_ROOT_STATE/root/firewall.applied" ]
  run ! grep -q 'ufw --force enable' "$STUB_LOG"   # never enabled after a failed step
}

# ---- ssh-harden job ----
@test "ssh-harden: sshd active + EMPTY authorized_keys -> warn skip, no ask, nothing installed" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; : > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]
  [ "$(rstate ssh-harden summary)" = "skipped: no authorized_keys — would lock you out" ]
  [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]; [ ! -e "$OPS_SSHD_DIR/50-dots.conf" ]; [ -z "$(mutations)" ]
}
@test "ssh-harden: sshd enabled via socket + MISSING authorized_keys (or comment-only) -> warn skip" {
  os "$ARCH"; export STUB_ACTIVE="sshd.socket"
  runjob ssh-harden
  [ "$(rstate ssh-harden summary)" = "skipped: no authorized_keys — would lock you out" ]
  printf '# nothing\n\n' > "$OWNER_HOME/.ssh/authorized_keys"; runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]; [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: owner unresolvable (no owner file) + sshd active -> warn skip (R40 fallback)" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  rm -f "$OPS_OWNER_FILE"; HOME="$OWNER_HOME" runjob ssh-harden   # never falls back to $HOME
  [ "$(rstate ssh-harden status)" = warn ]; [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: keys present + sshd active -> first apply asks, installs nothing" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden
  [ "$(rstate ask-ssh-harden action)" = "root:ssh-harden apply" ]
  [[ $(rstate ask-ssh-harden question) == *"PasswordAuthentication no"* ]]
  [ ! -e "$OPS_SSHD_DIR/50-dots.conf" ]; [ -z "$(mutations)" ]
}
@test "ssh-harden: sshd installed but not enabled, no keys -> asks (no lockout possible)" {
  os "$ARCH"; runjob ssh-harden
  [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: sshd_config without the sshd_config.d Include -> warn explaining, no ask" {
  os "$DEB"; printf 'PermitRootLogin yes\n' > "$OPS_SSHD_CONFIG"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]; [[ $(rstate ssh-harden summary) == *"Include"*"ignored"* ]]
  [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: AuthenticationMethods needing keyboard-interactive (2FA) -> warn skip; relative Include accepted" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  printf 'Include sshd_config.d/*.conf\n' > "$OPS_SSHD_CONFIG"
  echo 'AuthenticationMethods publickey,keyboard-interactive' > "$OPS_SSHD_DIR/20-2fa.conf"
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]; [[ $(rstate ssh-harden summary) == *AuthenticationMethods* ]]
  [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
  rm "$OPS_SSHD_DIR/20-2fa.conf"; runjob ssh-harden; [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: no sshd -> ok n/a; nixos -> ok n/a" {
  os "$DEB"; rm -f "$BIN/sshd"
  PATH="$BIN:/usr/bin:/bin" runjob ssh-harden
  [ "$(rstate ssh-harden status)" = ok ]; [[ $(rstate ssh-harden summary) == "n/a: sshd not installed"* ]]
  os "$NIX"; runjob ssh-harden; [[ $(rstate ssh-harden summary) == "n/a: "*"services.openssh"* ]]
}
@test "ssh-harden: drop-in already identical -> ok, stale ask withdrawn" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  cp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_SSHD_DIR/"; echo '{}' > "$OPS_ROOT_STATE/ask-ssh-harden.json"
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden: drop-in in place but overridden by an earlier file (sshd -T) -> warn" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  cp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_SSHD_DIR/"
  export STUB_SSHD_EFFECTIVE='permitrootlogin no\npasswordauthentication yes\nkbdinteractiveauthentication no\n'
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]; [[ $(rstate ssh-harden summary) == *passwordauthentication* ]]
}
@test "ssh-harden (R47): key file from sshd -T -C (authorizedkeysfile %u, absolute) is the one checked" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; mkdir -p "$BATS_TEST_TMPDIR/keys"
  export STUB_SSHD_TC="authorizedkeysfile $BATS_TEST_TMPDIR/keys/%u\nstrictmodes no\n"
  echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"   # not read by this sshd
  runjob ssh-harden
  grep -qx 'sshd -T -C user=alice,host=localhost,addr=127.0.0.1' "$STUB_LOG"
  [ "$(rstate ssh-harden summary)" = "skipped: no authorized_keys — would lock you out" ]
  echo 'ssh-ed25519 AAAA k' > "$BATS_TEST_TMPDIR/keys/alice"; runjob ssh-harden
  [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden (R47): relative authorizedkeysfile tokens are under home; %h/%% expanded; 'none' ignored" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; mkdir -p "$OWNER_HOME/.config/ssh%keys"
  export STUB_SSHD_TC="authorizedkeysfile none .ssh/authorized_keys %h/.config/ssh%%keys/%u\nstrictmodes yes\n"
  echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.config/ssh%keys/alice"
  runjob ssh-harden; [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
  rm "$OWNER_HOME/.config/ssh%keys/alice"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden; [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]; [ "$(rstate ssh-harden status)" = warn ]
  [ "$(rstate ssh-harden summary)" = "hardening awaits approval" ]
}
@test "ssh-harden (R47): StrictModes yes + group-writable home or ~/.ssh -> keys unusable, warn skip; StrictModes no -> asks" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  chmod 775 "$OWNER_HOME"
  export STUB_SSHD_TC='authorizedkeysfile .ssh/authorized_keys\nstrictmodes yes\n'
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]
  [[ $(rstate ssh-harden summary) == "skipped: no authorized_keys — would lock you out (StrictModes rejects $OWNER_HOME)" ]]
  [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
  chmod 755 "$OWNER_HOME"; chmod 777 "$OWNER_HOME/.ssh"; runjob ssh-harden
  [[ $(rstate ssh-harden summary) == *"StrictModes rejects $OWNER_HOME/.ssh)" ]]
  export STUB_SSHD_TC='authorizedkeysfile .ssh/authorized_keys\nstrictmodes no\n'; runjob ssh-harden
  [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
  chmod 700 "$OWNER_HOME/.ssh"
}
@test "ssh-harden (R47): sshd -T -C failing -> falls back to ~/.ssh/authorized_keys with StrictModes assumed" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; unset STUB_SSHD_TC; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden; [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
  chmod 666 "$OWNER_HOME/.ssh/authorized_keys"; runjob ssh-harden
  [[ $(rstate ssh-harden summary) == *"StrictModes rejects $OWNER_HOME/.ssh/authorized_keys)" ]]
}
@test "ssh-harden (R47): hardening installed and the keys vanished -> warn 'hardening active, no authorized_keys'" {
  os "$DEB"; export STUB_ACTIVE="ssh.service"; cp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_SSHD_DIR/"
  runjob ssh-harden
  [ "$(rstate ssh-harden status)" = warn ]
  [ "$(rstate ssh-harden summary)" = "hardening active, no authorized_keys: remote login impossible" ]
}
@test "ssh-harden (R49): OpenSSH < 8.7 -> ChallengeResponseAuthentication no instead (ask, apply, in-sync check)" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_UNITS="ssh.service" STUB_SSHD_VER=8.4; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  runjob ssh-harden
  q=$(rstate ask-ssh-harden question)
  [[ $q == *"PasswordAuthentication no"* && $q == *"ChallengeResponseAuthentication no"* && $q != *KbdInteractive* ]]
  run runact ssh-harden apply; [ "$status" -eq 0 ]
  run ! grep -q KbdInteractiveAuthentication "$OPS_SSHD_DIR/50-dots.conf"
  grep -qx 'PasswordAuthentication no' "$OPS_SSHD_DIR/50-dots.conf"; grep -qx 'ChallengeResponseAuthentication no' "$OPS_SSHD_DIR/50-dots.conf"
  export STUB_SSHD_EFFECTIVE='permitrootlogin no\npasswordauthentication no\nchallengeresponseauthentication no\n'
  runjob ssh-harden; [ "$(rstate ssh-harden status)" = ok ]
  export STUB_SSHD_EFFECTIVE='permitrootlogin no\npasswordauthentication no\nchallengeresponseauthentication yes\n'
  runjob ssh-harden; [ "$(rstate ssh-harden status)" = warn ]; [[ $(rstate ssh-harden summary) == *"challengeresponseauthentication yes"* ]]
  export STUB_SSHD_VER=8.7; runjob ssh-harden; [ -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]   # 8.7 knows Kbd...: wants that line
}
@test "ssh-harden (R49): OpenSSH >= 8.7 effective check verifies kbdinteractiveauthentication no" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_SSHD_VER=9.6; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  cp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_SSHD_DIR/"
  export STUB_SSHD_EFFECTIVE='permitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication yes\n'
  runjob ssh-harden; [ "$(rstate ssh-harden status)" = warn ]; [[ $(rstate ssh-harden summary) == *"kbdinteractiveauthentication yes"* ]]
  export STUB_SSHD_EFFECTIVE='permitrootlogin no\npasswordauthentication no\nkbdinteractiveauthentication no\n'
  runjob ssh-harden; [ "$(rstate ssh-harden status)" = ok ]
}
@test "50-dots.conf carries exactly the three hardening settings" {
  [ "$(grep -vE '^\s*(#|$)' "$R/system/dots-ops/sshd/50-dots.conf")" = "PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no" ]
}

# ---- ssh-harden apply (action) ----
@test "ssh-harden apply: installs the drop-in, sshd -t, reloads the existing unit" {
  os "$ARCH"; export STUB_ACTIVE="sshd.service" STUB_UNITS="sshd.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  echo '{}' > "$OPS_ROOT_STATE/ask-ssh-harden.json"
  run runact ssh-harden apply; [ "$status" -eq 0 ]
  cmp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_SSHD_DIR/50-dots.conf"
  grep -qx 'sshd -t' "$STUB_LOG"; grep -qx 'systemctl reload sshd.service' "$STUB_LOG"
  [ "$(rstate ssh-harden status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-ssh-harden.json" ]
}
@test "ssh-harden apply: Debian's ssh.service is reloaded when sshd.service does not exist" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_UNITS="ssh.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  run runact ssh-harden apply; [ "$status" -eq 0 ]
  grep -qx 'systemctl reload ssh.service' "$STUB_LOG"
}
@test "ssh-harden apply: sshd -t fails -> drop-in removed, fail, exit 1, no reload" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_UNITS="ssh.service" STUB_SSHD_T_RC=255
  echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  run runact ssh-harden apply; [ "$status" -eq 1 ]
  [ ! -e "$OPS_SSHD_DIR/50-dots.conf" ]
  [ "$(rstate ssh-harden status)" = fail ]; [[ $(rstate ssh-harden summary) == *"sshd -t"* ]]
  run ! grep -q 'systemctl reload' "$STUB_LOG"
}
@test "ssh-harden apply: sshd -t fails with an older drop-in in place -> the older one is restored" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_UNITS="ssh.service" STUB_SSHD_T_RC=255
  echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"; echo 'PermitRootLogin no' > "$OPS_SSHD_DIR/50-dots.conf"
  run runact ssh-harden apply; [ "$status" -eq 1 ]
  [ "$(cat "$OPS_SSHD_DIR/50-dots.conf")" = 'PermitRootLogin no' ]
}
@test "ssh-harden apply re-checks the lockout guard: keys removed after the ask -> nothing installed" {
  os "$DEB"; export STUB_ACTIVE="ssh.service" STUB_UNITS="ssh.service"; : > "$OWNER_HOME/.ssh/authorized_keys"
  run runact ssh-harden apply; [ "$status" -eq 0 ]
  [ ! -e "$OPS_SSHD_DIR/50-dots.conf" ]; run ! grep -q '^sshd -t' "$STUB_LOG"
  [ "$(rstate ssh-harden summary)" = "skipped: no authorized_keys — would lock you out" ]
}
@test "ssh-harden apply dry-run prints install, sshd -t and reload" {
  os "$ARCH"; export STUB_ACTIVE="sshd.service" STUB_UNITS="sshd.service"; echo 'ssh-ed25519 AAAA k' > "$OWNER_HOME/.ssh/authorized_keys"
  run env DOTS_OPS_DRY_RUN=1 bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/ssh-harden/apply.sh"
  [ "$status" -eq 0 ]
  [[ $output == *"+ install -m 644 $OPS_ROOT_STATE/root/ssh-harden.desired.conf $OPS_SSHD_DIR/50-dots.conf"* ]]
  cmp "$R/system/dots-ops/sshd/50-dots.conf" "$OPS_ROOT_STATE/root/ssh-harden.desired.conf"   # OpenSSH 9.6: unchanged
  [[ $output == *"+ sshd -t"* && $output == *"+ systemctl reload sshd.service"* ]]
  [ ! -e "$OPS_SSHD_DIR/50-dots.conf" ]
}

# ---- audit ----
LYN1='hardening_index=70\nwarning[]=SSH-7408|weak|\n'
@test "audit is heavy; lynis via ops_run with the exact flags; first run = baseline ok" {
  source "$SJ/audit.sh"; [ "$OPS_HEAVY" = 1 ]
  os "$DEB"; export STUB_LYNIS_REPORT="$LYN1"; runjob audit
  grep -qx "lynis audit system --quick --no-colors --report-file $OPS_ROOT_STATE/root/lynis-report.dat" "$STUB_LOG"
  [ "$(rstate audit status)" = ok ]; [[ $(rstate audit summary) == *"index 70"*"1 warning"* ]]
  [ "$(jq -r .hardening_index "$OPS_ROOT_STATE/root/audit-last.json")" = 70 ]
}
@test "audit: hardening score drop -> warn" {
  os "$DEB"; echo '{"hardening_index":75,"warnings":["SSH-7408"],"t":1}' > "$OPS_ROOT_STATE/root/audit-last.json"
  export STUB_LYNIS_REPORT="$LYN1"; OPS_FORCE=1 runjob audit
  [ "$(rstate audit status)" = warn ]; [[ $(rstate audit summary) == *"75 -> 70"* ]]
}
@test "audit: new warning id -> warn; unchanged -> ok" {
  os "$DEB"; echo '{"hardening_index":70,"warnings":[],"t":1}' > "$OPS_ROOT_STATE/root/audit-last.json"
  export STUB_LYNIS_REPORT="$LYN1"; OPS_FORCE=1 runjob audit
  [ "$(rstate audit status)" = warn ]; [[ $(rstate audit summary) == *"new warning"*"SSH-7408"* ]]
  OPS_FORCE=1 runjob audit; [ "$(rstate audit status)" = ok ]
}
@test "audit arch: arch-audit -q vulnerable packages -> warn with count" {
  os "$ARCH"; export STUB_LYNIS_REPORT="$LYN1" STUB_ARCH_AUDIT='openssl\nlibxml2\n'; runjob audit
  grep -qx 'arch-audit -q' "$STUB_LOG"
  [ "$(rstate audit status)" = warn ]; [[ $(rstate audit summary) == *"2 vulnerable packages"* ]]
}
@test "audit: lynis missing -> ok n/a; dry run prints lynis and parses nothing" {
  os "$DEB"; rm -f "$BIN/lynis"; PATH="$BIN:/usr/bin:/bin" runjob audit
  [ "$(rstate audit status)" = ok ]; [[ $(rstate audit summary) == "n/a: lynis not installed"* ]]
  mkstub lynis 'echo "lynis $*" >> "$STUB_LOG"'
  run env DOTS_OPS_DRY_RUN=1 bash -c 'source "$1"; source "$2"; job_main' _ "$LIB" "$SJ/audit.sh"
  [[ $output == *"+ lynis audit system --quick --no-colors --report-file $OPS_ROOT_STATE/root/lynis-report.dat"* ]]
  run ! grep -q '^lynis' "$STUB_LOG"
}
@test "audit: ran less than 6 days ago -> skipped unless forced (it is also pulled by the idle target)" {
  os "$DEB"; jq -cn --argjson t "$(date +%s)" '{hardening_index:70,warnings:[],t:$t}' > "$OPS_ROOT_STATE/root/audit-last.json"
  runjob audit; run ! grep -q '^lynis' "$STUB_LOG"
  export STUB_LYNIS_REPORT="$LYN1"; OPS_FORCE=1 runjob audit; grep -q '^lynis' "$STUB_LOG"
}

# ---- timers, idle target ----
@test "security timers: audit weekly persistent; firewall + ssh-harden daily + 5 min after boot" {
  g() { grep -qx "$2" "$SU/$1"; }
  g dots-ops-audit.timer 'OnCalendar=weekly'; g dots-ops-audit.timer 'Persistent=true'; g dots-ops-audit.timer 'Unit=dots-ops@audit.service'
  for j in firewall ssh-harden; do
    g dots-ops-$j.timer 'OnCalendar=daily'; g dots-ops-$j.timer 'OnBootSec=5min'; g dots-ops-$j.timer 'Persistent=true'
    g dots-ops-$j.timer "Unit=dots-ops@$j.service"
  done
  for j in audit firewall ssh-harden; do g dots-ops-$j.timer 'WantedBy=timers.target'; done
  grep -q 'dots-ops@audit.service' "$SU/dots-ops-system-idle.target"
}

# ---- installer + root layer ----
@test "installer copies firewall.json + the sshd drop-in, writes /etc/dots-ops/owner 0644 root, starts firewall/ssh-harden" {
  s="$R/home/.chezmoiscripts/run_onchange_after_26-dots-ops-system.sh.tmpl"
  grep -q 'firewall.json" "$L/firewall.json"' "$s"
  grep -q 'sshd/50-dots.conf" "$L/sshd/50-dots.conf"' "$s"
  grep -q 'install -m 644 -o root -g root /dev/stdin /etc/dots-ops/owner' "$s"
  grep -q 'start --no-block dots-ops@firewall.service dots-ops@ssh-harden.service' "$s"
}
render_pkgs() {   # render_pkgs <osRelease id> [idLike]: DOTS_PKG_LIST output of the rendered root script
  local out="$BATS_TEST_TMPDIR/sys.sh" real
  real=$(PATH="$ORIG_PATH" command -v chezmoi) || skip "no chezmoi"
  "$real" execute-template --override-data "{\"gpu\":\"mesa\",\"multiplexer\":\"tmux\",\"chezmoi\":{\"homeDir\":\"/h\",\"workingTree\":\"/w\",\"osRelease\":{\"id\":\"$1\",\"idLike\":\"${2:-}\"}}}" \
    < "$R/home/.chezmoiscripts/run_once_before_00-system.sh.tmpl" > "$out"
  bash -n "$out"
  DOTS_PKG_LIST=1 bash "$out"
}
@test "root layer: lynis everywhere, ufw on arch/debian, firewalld on fedora, arch-audit on arch" {
  run render_pkgs arch;          [ "$status" -eq 0 ]; [[ $output == *" lynis"* && $output == *" ufw"* && $output == *arch-audit* && $output != *firewalld* ]]
  run render_pkgs ubuntu debian; [ "$status" -eq 0 ]; [[ $output == *" lynis"* && $output == *" ufw"* && $output != *arch-audit* && $output != *firewalld* ]]
  run render_pkgs fedora;        [ "$status" -eq 0 ]; [[ $output == *" lynis"* && $output == *firewalld* && $output != *" ufw"* ]]
}

# ---- NixOS module ----
@test "NixOS module: firewall ports from firewall.json, owner file, openssh hardening behind a keys guard" {
  n="$R/nix/hosts/nixos-laptop/dots-ops.nix"
  grep -q 'builtins.fromJSON (builtins.readFile (sys + "/firewall.json"))' "$n"
  grep -q 'allowedTCPPortRanges' "$n"; grep -q 'allowedUDPPortRanges' "$n"
  grep -q 'environment.etc."dots-ops/owner"' "$n"
  grep -q 'PasswordAuthentication = lib.mkDefault false' "$n"; grep -q 'KbdInteractiveAuthentication = lib.mkDefault false' "$n"; grep -q 'PermitRootLogin = lib.mkDefault "no"' "$n"
  grep -q 'services.openssh.settings = lib.mkIf ownerHasKeys' "$n"
  grep -q 'authorizedKeys' "$n"
}
