load helpers
bats_require_minimum_version 1.5.0
# Root side: dots-ops-run (the only privilege path), system units, sudoers, relay, installer.
# Everything runs unprivileged: dots-ops-run honours OPS_ROOT_PREFIX only with OPS_TEST=1 and prints systemctl calls.
R="$BATS_TEST_DIRNAME/../.."
setup() { unset INVOCATION_ID; P="$BATS_TEST_TMPDIR/p"; RUN="$BATS_TEST_DIRNAME/../../system/dots-ops/bin/dots-ops-run"; mkdir -p "$P/jobs" "$P/actions/updates-full"; cp "$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh" "$P/lib.sh"; }
trun() { run env -u INVOCATION_ID OPS_TEST=1 OPS_ROOT_PREFIX="$P" OPS_STATE="$BATS_TEST_TMPDIR/st" OPS_ROOT_STATE="$BATS_TEST_TMPDIR/rs" bash "$RUN" "$@"; }

# ---- dots-ops-run: allow-list (Review Focus 1) ----
@test "rejects path traversal and unknown names" {
  for a in "../x run" "updates-full ../../bin/sh" "nope run" "updates-full nope"; do
    run env OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" $a; [ "$status" -eq 2 ]
  done
}
@test "rejects empty, extra, dotted, slashed and uppercase arguments" {
  touch "$P/jobs/updates-full.sh"; printf 'true\n' > "$P/actions/updates-full/apply.sh"
  for a in "" "updates-full" "updates-full apply extra" "updates-full apply.sh" "Updates-full apply" "updates-full/ apply" "-x run" "system idle-nope" "system run"; do
    run env OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" $a; [ "$status" -eq 2 ]
  done
  run env OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" "updates-full" $'apply\nrun'; [ "$status" -eq 2 ]
}
@test "traversal to an existing file outside actions/ is still refused" {
  printf 'touch %s/pwned\n' "$BATS_TEST_TMPDIR" > "$P/evil.sh"; touch "$P/jobs/updates-full.sh"
  trun updates-full ../../evil; [ "$status" -eq 2 ]
  trun ../evil run; [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}
@test "R34: an action starts a transient unit (systemd-run argv), nothing is sourced in the caller's tree" {
  printf 'touch %s/applied\n' "$BATS_TEST_TMPDIR" > "$P/actions/updates-full/apply.sh"
  trun updates-full apply; [ "$status" -eq 0 ]
  [ "$output" = "systemd-run --no-block --collect --unit=dots-ops-act-updates-full-apply $RUN updates-full apply inline" ]
  [ ! -e "$BATS_TEST_TMPDIR/applied" ]
}
@test "R34: inline without INVOCATION_ID is rejected; a bogus third argument is rejected" {
  printf 'touch %s/applied\n' "$BATS_TEST_TMPDIR" > "$P/actions/updates-full/apply.sh"; touch "$P/jobs/updates-full.sh"
  trun updates-full apply inline; [ "$status" -eq 2 ]
  run env -u INVOCATION_ID OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full apply inline; [ "$status" -eq 2 ]
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full apply bogus; [ "$status" -eq 2 ]
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full run inline; [ "$status" -eq 2 ]
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" system idle-end inline; [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/applied" ]
}
@test "R34: inline with INVOCATION_ID runs the allow-listed action file and logs it; validation is repeated" {
  printf 'touch %s/applied\n' "$BATS_TEST_TMPDIR" > "$P/actions/updates-full/apply.sh"
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" OPS_STATE="$BATS_TEST_TMPDIR/st" OPS_ROOT_STATE="$BATS_TEST_TMPDIR/rs" bash "$RUN" updates-full apply inline
  [ "$status" -eq 0 ] && [ -e "$BATS_TEST_TMPDIR/applied" ]
  grep -q 'apply (approved)' "$BATS_TEST_TMPDIR/st/log.jsonl"
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full ../../evil inline; [ "$status" -eq 2 ]
  run env INVOCATION_ID=abc OPS_TEST=1 OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full nope inline; [ "$status" -eq 2 ]
}
@test "run starts the system unit without blocking, only for an existing root job" {
  touch "$P/jobs/updates-full.sh"
  trun updates-full run; [ "$status" -eq 0 ]
  [[ $output == "systemctl start --no-block dots-ops@updates-full.service" ]]
  trun nope run; [ "$status" -eq 2 ]
}
@test "run-now (R4/R26) starts a transient unit asynchronously with OPS_FORCE=1, allow-listed like run" {
  touch "$P/jobs/disk-clean-system.sh"
  printf '#!/bin/sh\n' > "$P/dots-ops-job"; chmod +x "$P/dots-ops-job"
  trun disk-clean-system run-now; [ "$status" -eq 0 ]
  [[ $output == "systemd-run --no-block --collect --unit=dots-ops-now-disk-clean-system --setenv=OPS_FORCE=1 --setenv=OPS_IS_ROOT=1 $P/dots-ops-job disk-clean-system" ]]
  trun nope run-now; [ "$status" -eq 2 ]
}
@test "system idle-run (R3/R14) sets the root idle flag and restarts the system idle target" {
  trun system idle-run; [ "$status" -eq 0 ]
  [ -e "$P/run/idle" ]
  [[ $output == "systemctl restart --no-block dots-ops-system-idle.target" ]]
}
@test "system idle-end (R3) removes the flag and stops the target" {
  mkdir -p "$P/run"; touch "$P/run/idle"
  trun system idle-end; [ "$status" -eq 0 ]
  [ ! -e "$P/run/idle" ]
  [[ $output == "systemctl stop --no-block dots-ops-system-idle.target" ]]
}
@test "without OPS_TEST the prefix override is ignored and non-root is refused" {
  printf 'touch %s/applied\n' "$BATS_TEST_TMPDIR" > "$P/actions/updates-full/apply.sh"
  run env OPS_ROOT_PREFIX="$P" bash "$RUN" updates-full apply
  [ "$status" -ne 0 ]; [ ! -e "$BATS_TEST_TMPDIR/applied" ]
}
@test "runner shebang is absolute (sudo may keep the caller's PATH) and production paths are root-owned" {
  head -1 "$RUN" | grep -qx '#!/bin/bash -p'
  grep -q '^  P=/usr/local/lib/dots-ops;' "$RUN"
  grep -q 'JOB_BIN=/usr/local/bin/dots-ops-job' "$RUN"
  run ! grep -nE '\$HOME|/home/|XDG_' "$RUN"
}

# ---- units + sudoers (Review Focus 1) ----
@test "every system unit and the sudoers rule reference only root-owned paths" {
  run ! grep -rnE '%h|/home/|\$HOME|~/|XDG_|\.local/' system/dots-ops/units system/dots-ops/sudoers
  [ -z "$output" ] && [ -d system/dots-ops/units ]   # `! grep` mid-test asserts nothing in bats; `run !` does
  grep -q '^%dots-ops ALL=(root) NOPASSWD: /usr/local/bin/dots-ops-run$' system/dots-ops/sudoers
}
@test "system job unit runs the root-owned job runner as root" {
  u="$R/system/dots-ops/units/dots-ops@.service"
  grep -qx 'ExecStart=/usr/local/bin/dots-ops-job %i' "$u"
  grep -qx 'Environment=OPS_IS_ROOT=1' "$u"
  run ! grep -q '^User=' "$u"
  [ -f "$R/system/dots-ops/units/dots-ops-system-idle.target" ]
}
@test "sudoers file has exactly one rule" {
  s="$R/system/dots-ops/sudoers"
  [ "$(grep -cvE '^\s*(#|$|Defaults)' "$s")" -eq 1 ]
  # R19: the runner never sees the caller's environment or PATH, even on distros without a global secure_path
  grep -qx 'Defaults!/usr/local/bin/dots-ops-run env_reset' "$s"
  grep -qx 'Defaults!/usr/local/bin/dots-ops-run secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' "$s"
  [ "$(grep -c '^Defaults' "$s")" -eq 2 ]
  if command -v visudo >/dev/null; then cp "$s" "$BATS_TEST_TMPDIR/sudoers"; visudo -cf "$BATS_TEST_TMPDIR/sudoers"; fi
}

# ---- R19: the production prologue runs nothing from the caller's PATH/env ----
fakebin() {   # id/stat/systemctl/jq/env/bash that leave a marker if anything executes them
  mkdir -p "$BATS_TEST_TMPDIR/evil"; local c
  for c in id stat systemctl jq env bash mkdir touch date compgen sudo; do
    printf '#!/bin/sh\n: > %s/marker-%s\n' "$BATS_TEST_TMPDIR" "$c" > "$BATS_TEST_TMPDIR/evil/$c"
  done
  chmod +x "$BATS_TEST_TMPDIR"/evil/*
}
@test "non-root without OPS_TEST: refuses before running anything from the caller's PATH" {
  fakebin; touch "$P/jobs/updates-full.sh"
  for a in "updates-full run" "updates-full run-now" "system idle-run" "updates-full apply" "../x run"; do
    run env PATH="$BATS_TEST_TMPDIR/evil:$PATH" OPS_ROOT_PREFIX="$P" "$RUN" $a
    [ "$status" -ne 0 ]
  done
  run ls "$BATS_TEST_TMPDIR"; [[ $output != *marker-* ]]
}
@test "OPS_TEST mode also ignores the caller's PATH (fixed PATH is the first statement)" {
  fakebin; touch "$P/jobs/updates-full.sh"
  run env PATH="$BATS_TEST_TMPDIR/evil:$PATH" OPS_TEST=1 OPS_ROOT_PREFIX="$P" "$RUN" updates-full run
  [ "$status" -eq 0 ]
  run ls "$BATS_TEST_TMPDIR"; [[ $output != *marker-* ]]
  run grep -nE '^(export PATH=|unset BASH_ENV)' "$RUN"; [[ ${lines[0]} == *"export PATH=/run/wrappers/bin:"* ]]
  first_cmd=$(grep -vnE '^\s*(#|$)' "$RUN" | head -1); [[ $first_cmd == *"export PATH="* ]]
}
@test "an exported BASH_ENV / function does not run in the runner (bash -p)" {
  printf 'touch %s/bashenv-ran\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/benv.sh"
  run env BASH_ENV="$BATS_TEST_TMPDIR/benv.sh" ENV="$BATS_TEST_TMPDIR/benv.sh" "$RUN" updates-full run
  [ "$status" -ne 0 ]; [ ! -e "$BATS_TEST_TMPDIR/bashenv-ran" ]
  run env BASH_ENV="$BATS_TEST_TMPDIR/benv.sh" OPS_TEST=1 OPS_ROOT_PREFIX="$P" "$RUN" system idle-end
  [ "$status" -eq 0 ]; [ ! -e "$BATS_TEST_TMPDIR/bashenv-ran" ]
  # control: plain bash does honour BASH_ENV, so the assertion above is meaningful
  env BASH_ENV="$BATS_TEST_TMPDIR/benv.sh" bash -c true; [ -e "$BATS_TEST_TMPDIR/bashenv-ran" ]
}
@test "R22: job names starting with ask- are reserved" {
  touch "$P/jobs/ask-x.sh"; mkdir -p "$P/actions/ask-x"; printf 'true\n' > "$P/actions/ask-x/apply.sh"
  trun ask-x run; [ "$status" -eq 2 ]
  trun ask-x apply; [ "$status" -eq 2 ]
}

# ---- R20: root only runs root-owned, non-writable job files ----
@test "ops_file_trusted accepts root-owned 0755/0644 files and rejects user-owned or world-writable ones" {
  setup_ops
  ops_file_trusted /usr /etc/passwd
  touch "$BATS_TEST_TMPDIR/mine"
  run ops_file_trusted "$BATS_TEST_TMPDIR/mine"; [ "$status" -ne 0 ]        # not root-owned
  run ops_file_trusted /tmp; [ "$status" -ne 0 ]                            # root-owned but 1777
  run ops_file_trusted /etc/passwd /nonexistent; [ "$status" -ne 0 ]
}
@test "dots-ops-job (as root) refuses untrusted job files via ops_file_trusted" {
  # the guard only runs at EUID 0; assert it is wired before the job is sourced
  j="$R/home/private_dot_local/private_bin/executable_dots-ops-job"
  guard=$(grep -n 'EUID" = 0 \] && ! ops_file_trusted "\$OPS_JOBS_DIR" "\$OPS_JOBS_DIR/\$job.sh"' "$j" | cut -d: -f1)
  src=$(grep -n 'source "\$OPS_JOBS_DIR/\$job.sh"' "$j" | cut -d: -f1)
  [ -n "$guard" ] && [ -n "$src" ] && [ "$guard" -lt "$src" ]
  sed -n "$((guard+1))p" "$j" | grep -q 'exit 2'
}

# ---- lib: root defaults ----
@test "root lib defaults keep state under /var/lib/dots-ops, never HOME" {
  run env -u HOME -u XDG_STATE_HOME -u OPS_STATE OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/rs" \
    bash -uc 'source "$1"; echo "$OPS_STATE"' _ "$R/home/private_dot_local/lib/dots-ops/lib.sh"
  [ "$status" -eq 0 ]; [ "$output" = "$BATS_TEST_TMPDIR/rs/root" ]
}
@test "root ops_ask writes ask-<job>.json for the relay instead of a local pending/UI" {
  setup_ops
  OPS_IS_ROOT=1 ops_ask reboot "Reboot for kernel?" "root:reboot apply"
  f="$OPS_ROOT_STATE/ask-reboot.json"
  [ "$(jq -r .question "$f")" = "Reboot for kernel?" ] && [ "$(jq -r .action "$f")" = "root:reboot apply" ]
  [ ! -e "$OPS_STATE/pending/reboot.json" ]
  OPS_IS_ROOT=1 ops_ask reboot "q" "root:reboot apply" "root:reboot tonight"
  [ "$(jq -r .alt_action "$f")" = "root:reboot tonight" ]
}

# ---- relay: root state → user state ----
relay_setup() {
  setup_ops; export OPS_ASK_UI=0 OPS_IS_ROOT=0 OPS_LIB="$R/home/private_dot_local/lib/dots-ops/lib.sh"
  export OPS_JOBS_DIR="$BATS_TEST_TMPDIR/userjobs"; mkdir -p "$OPS_JOBS_DIR"
  mkdir -p "$OPS_ROOT_STATE"; CLI="$R/home/private_dot_local/private_bin/executable_dots-ops"
}
rootstate() { jq -cn --arg j "$1" --arg s "$2" --arg m "$3" --argjson t "$4" '{job:$j,status:$s,summary:$m,changed:$t,notified:0}' > "$OPS_ROOT_STATE/$1.json"; }
@test "relay copies a changed root status into user state once, notifying" {
  relay_setup; rootstate smart fail "disk sda failing" 100
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$OPS_STATE/state/smart.json")" = fail ]
  [ "$(jq -r .summary "$OPS_STATE/state/smart.json")" = "disk sda failing" ]
  [ "$(notified)" -eq 1 ]
  run bash "$CLI" relay; [ "$(notified)" -eq 1 ]          # unchanged → not relayed again
  rootstate smart ok "healthy" 200
  run bash "$CLI" relay
  [ "$(jq -r .status "$OPS_STATE/state/smart.json")" = ok ]; grep -q recovered "$NOTIFY_LOG"
}
@test "relay turns a root ask file into a user pending approval, once per ask" {
  relay_setup
  jq -cn '{question:"Apply updates?",action:"root:updates-full apply",asked:$t}' --argjson t "$(date +%s)" > "$OPS_ROOT_STATE/ask-updates-full.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  p="$OPS_STATE/pending/updates-full.json"
  [ "$(jq -r .action "$p")" = "root:updates-full apply" ] && [ "$(jq -r .question "$p")" = "Apply updates?" ]
  [ ! -e "$OPS_STATE/state/ask-updates-full.json" ]       # asks are not statuses
  rm -f "$p"                                               # user skipped it
  run bash "$CLI" relay; [ ! -e "$p" ]                     # same ask → not re-asked
  jq -cn '{question:"Apply updates?",action:"root:updates-full apply",asked:($t+1)}' --argjson t "$(date +%s)" > "$OPS_ROOT_STATE/ask-updates-full.json"
  run bash "$CLI" relay; [ -e "$p" ]                       # root asked again → re-asked
}
@test "R48 relay: a changed root ask replaces the user's live pending; an unchanged one keeps it" {
  relay_setup; t=$(date +%s)
  jq -cn --argjson t "$t" '{question:"Apply A?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; p="$OPS_STATE/pending/firewall.json"; [ "$(jq -r .question "$p")" = "Apply A?" ]
  jq '.snooze_until = 1' "$p" > "$p.x" && mv "$p.x" "$p"   # marker: proves the same pending survives
  jq -cn --argjson t "$((t + 1))" '{question:"Apply A?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; [ "$(jq -r .snooze_until "$p")" = 1 ]          # same question re-asked by root: pending kept
  jq -cn --argjson t "$((t + 2))" '{question:"Apply B?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ "$(jq -r .question "$p")" = "Apply B?" ]; [ "$(jq -r .snooze_until "$p")" = 0 ]
  grep -q 'pending replaced by a changed root ask' "$OPS_STATE/log.jsonl"
}
@test "R48 relay: a root ask that disappears withdraws the user's pending (root actions only)" {
  relay_setup
  jq -cn --argjson t "$(date +%s)" '{question:"Apply?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; [ -e "$OPS_STATE/pending/firewall.json" ]
  rm "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ ! -e "$OPS_STATE/pending/firewall.json" ]; [ ! -e "$OPS_STATE/relayed/ask-firewall" ]
  grep -q 'root ask withdrawn; pending removed' "$OPS_STATE/log.jsonl"
  # a user job's own pending (user: action) under a name that once had a root ask is never touched
  echo x > "$OPS_STATE/relayed/ask-backup"; OPS_IS_ROOT=0 OPS_ASK_UI=0 ops_ask backup "Prune?" "user:true"
  run bash "$CLI" relay; [ -e "$OPS_STATE/pending/backup.json" ]
}
@test "R54 relay: replacing or withdrawing a root ask closes the superseded toast (gdbus CloseNotification <id>)" {
  relay_setup; t=$(date +%s); mkdir -p "$BATS_TEST_TMPDIR/gb"
  printf '#!/bin/sh\necho "gdbus $*" >> %s/gdbus.log\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/gb/gdbus"; chmod +x "$BATS_TEST_TMPDIR/gb/gdbus"
  export PATH="$BATS_TEST_TMPDIR/gb:$PATH"
  jq -cn --argjson t "$t" '{question:"Apply A?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; echo 4711 > "$OPS_STATE/pending/firewall.nid"   # the toast for A is up (dots-ops-ask wrote its id)
  jq -cn --argjson t "$((t + 1))" '{question:"Apply B?",action:"root:firewall apply",asked:$t}' > "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  grep -q 'gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification 4711' "$BATS_TEST_TMPDIR/gdbus.log"
  [ ! -e "$OPS_STATE/pending/firewall.nid" ]
  echo 4712 > "$OPS_STATE/pending/firewall.nid"; rm "$OPS_ROOT_STATE/ask-firewall.json"
  run bash "$CLI" relay; grep -q 'CloseNotification 4712' "$BATS_TEST_TMPDIR/gdbus.log"
}
@test "R55 end to end: approved containers-prune volumes (fake root) -> relay shows containers-prune-volumes, never skipped" {
  relay_setup; cp "$R/home/private_dot_local/lib/dots-ops/jobs/"*.sh "$OPS_JOBS_DIR/"   # the real user job names
  mkdir -p "$BATS_TEST_TMPDIR/dk"; export PATH="$BATS_TEST_TMPDIR/dk:$PATH"
  printf '#!/bin/sh\n[ -z "$DK_FAIL" ] || { echo "Error: daemon down"; exit 1; }\necho "Total reclaimed space: 12GB"\n' > "$BATS_TEST_TMPDIR/dk/docker"; chmod +x "$BATS_TEST_TMPDIR/dk/docker"
  asroot() { env OPS_IS_ROOT=1 OPS_STATE="$BATS_TEST_TMPDIR/rootlog" "$@" bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$OPS_LIB" "$R/system/dots-ops/actions/containers-prune/volumes.sh"; }
  run asroot DK_FAIL=1; [ "$status" -eq 0 ]
  [ -f "$OPS_ROOT_STATE/containers-prune-volumes.json" ]; [ ! -e "$OPS_ROOT_STATE/containers-prune.json" ]
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$OPS_STATE/state/containers-prune-volumes.json")" = warn ]
  grep -q 'dots-ops: containers-prune-volumes' "$NOTIFY_LOG"
  run ! grep -q 'collides with user job' "$OPS_STATE/log.jsonl"
  sleep 1; run asroot; [ "$status" -eq 0 ]
  run bash "$CLI" relay
  [ "$(jq -r .status "$OPS_STATE/state/containers-prune-volumes.json")" = ok ]
  [[ $(jq -r .summary "$OPS_STATE/state/containers-prune-volumes.json") == *"12GB"* ]]
  grep -q 'containers-prune-volumes recovered' "$NOTIFY_LOG"
}
@test "R55 no root job or action reports a state under a user job's name (the relay would skip it)" {
  names=$(grep -rhoE 'ops_state [a-z0-9-]+' "$R/system/dots-ops" | awk '{print $2}' | sort -u)
  [ -n "$names" ]
  for n in $names; do [ ! -e "$R/home/private_dot_local/lib/dots-ops/jobs/$n.sh" ] || { echo "root state name $n collides with a user job"; return 1; }; done
}
@test "relay ignores non-root actions, bad names and bad statuses" {
  relay_setup
  jq -cn '{question:"x",action:"user:touch /tmp/pwn",asked:$t}' --argjson t "$(date +%s)" > "$OPS_ROOT_STATE/ask-evil.json"
  rootstate weird bogus "x" 5; cp "$OPS_ROOT_STATE/weird.json" "$OPS_ROOT_STATE/Bad_Name.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ ! -e "$OPS_STATE/pending/evil.json" ] && [ ! -e "$OPS_STATE/state/weird.json" ] && [ ! -e "$OPS_STATE/state/Bad_Name.json" ]
}
@test "R21: relay drops a root ask older than 24h (logged once, not asked)" {
  relay_setup
  jq -cn --argjson t $(( $(date +%s) - 86401 )) '{question:"old?",action:"root:reboot apply",asked:$t}' > "$OPS_ROOT_STATE/ask-reboot.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ ! -e "$OPS_STATE/pending/reboot.json" ]
  [ "$(grep -c 'dropped stale root ask' "$OPS_STATE/log.jsonl")" -eq 1 ]
  run bash "$CLI" relay
  [ "$(grep -c 'dropped stale root ask' "$OPS_STATE/log.jsonl")" -eq 1 ]
  jq -cn '{question:"no time",action:"root:reboot apply"}' > "$OPS_ROOT_STATE/ask-reboot.json"   # no asked = stale
  run bash "$CLI" relay; [ ! -e "$OPS_STATE/pending/reboot.json" ]
}
@test "R22: relay skips a root status whose name belongs to a user job (logged)" {
  relay_setup; touch "$OPS_JOBS_DIR/backup.sh"
  jq -cn '{job:"backup",status:"fail",summary:"root says",changed:100,notified:0}' > "$OPS_ROOT_STATE/backup.json"
  ops_state backup ok "user backup fine"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ "$(jq -r .summary "$OPS_STATE/state/backup.json")" = "user backup fine" ]
  grep -q 'collides with user job' "$OPS_STATE/log.jsonl"
}
@test "relay with no root state dir is a no-op" {
  relay_setup; OPS_ROOT_STATE="$BATS_TEST_TMPDIR/none" run bash "$CLI" relay; [ "$status" -eq 0 ]
}
@test "user relay units: path watches /var/lib/dots-ops, service runs dots-ops relay, both enabled" {
  d="$R/home/private_dot_config/systemd/private_user"
  grep -qx 'PathChanged=/var/lib/dots-ops' "$d/dots-ops-relay.path"
  grep -qx 'ExecStart=%h/.local/bin/dots-ops relay' "$d/dots-ops-relay.service"
  grep -q 'enable --now dots-ops-relay.path dots-ops-relay.service' "$R/home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl"
}

# ---- installer (non-NixOS) ----
render_installer() {   # data-file → rendered script path
  command -v chezmoi >/dev/null || skip "chezmoi not installed"
  local cfg="$BATS_TEST_TMPDIR/cfg.toml" out="$BATS_TEST_TMPDIR/inst-$(basename "$1" .toml).sh"
  cat "$R/tests/$1" > "$cfg"
  HOME="$BATS_TEST_TMPDIR/h" chezmoi execute-template --source "$R/home" --config "$cfg" \
    < "$R/home/.chezmoiscripts/run_onchange_after_26-dots-ops-system.sh.tmpl" > "$out"
  echo "$out"
}
@test "installer renders, parses, carries a content hash and installs root-owned copies" {
  s=$(render_installer data-nvidia-tmux.toml); bash -n "$s"
  grep -qE '^# dots-ops system install hash: [0-9a-f]{64}  -$' "$s"
  grep -q 'visudo -cf' "$s"; grep -q '/etc/sudoers.d/dots-ops' "$s"
  # R20: symlink check comes before anything is copied
  sl=$(grep -n 'find "$W/system/dots-ops" -type l' "$s" | head -1 | cut -d: -f1)
  cp1=$(grep -n 'sudo install' "$s" | head -1 | cut -d: -f1)
  [ -n "$sl" ] && [ "$sl" -lt "$cp1" ]
  grep -q 'install -m 755 .*/system/dots-ops/bin/dots-ops-run" /usr/local/bin/dots-ops-run' "$s"
  grep -qx 'L=/usr/local/lib/dots-ops' "$s"; grep -q 'chown -R root:root "$L"' "$s"; grep -q 'chmod -R go-w "$L"' "$s"
}
@test "installer is a no-op on NixOS (the Nix module installs it there)" {
  s=$(render_installer data-nixos-tmux.toml); bash -n "$s"
  run ! grep -q sudo "$s"
}

@test "R38 every /usr/local dots-ops path in the runner, job runner and lib is rewritten by the NixOS module" {
  nix="$R/nix/hosts/nixos-laptop/dots-ops.nix"
  toks=$(grep -ohE '/usr/local/(bin/dots-ops[a-z-]*|lib/dots-ops)' "$R/system/dots-ops/bin/dots-ops-run" \
    "$R/home/private_dot_local/private_bin/executable_dots-ops-job" "$R/home/private_dot_local/lib/dots-ops/lib.sh" | sort -u)
  [[ $toks == *"/usr/local/bin/dots-ops-run"* && $toks == *"/usr/local/bin/dots-ops-job"* && $toks == *"/usr/local/lib/dots-ops"* ]]
  for t in $toks; do grep -qE -- "--replace-(fail|quiet) $t( |$)" "$nix" || { echo "not substituted in dots-ops.nix: $t"; return 1; }; done
}
