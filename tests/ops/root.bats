load helpers
bats_require_minimum_version 1.5.0
# Root side: dots-ops-run (the only privilege path), system units, sudoers, relay, installer.
# Everything runs unprivileged: dots-ops-run honours OPS_ROOT_PREFIX only with OPS_TEST=1 and prints systemctl calls.
R="$BATS_TEST_DIRNAME/../.."
setup() { P="$BATS_TEST_TMPDIR/p"; RUN="$BATS_TEST_DIRNAME/../../system/dots-ops/bin/dots-ops-run"; mkdir -p "$P/jobs" "$P/actions/updates-full"; cp "$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh" "$P/lib.sh"; }
trun() { run env OPS_TEST=1 OPS_ROOT_PREFIX="$P" OPS_STATE="$BATS_TEST_TMPDIR/st" OPS_ROOT_STATE="$BATS_TEST_TMPDIR/rs" bash "$RUN" "$@"; }

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
@test "runs an allow-listed action file" {
  mkdir -p "$P/actions/updates-full"
  printf 'touch %s/applied\n' "$BATS_TEST_TMPDIR" > "$P/actions/updates-full/apply.sh"
  run env OPS_TEST=1 OPS_ROOT_PREFIX="$P" OPS_STATE="$BATS_TEST_TMPDIR/st" OPS_ROOT_STATE="$BATS_TEST_TMPDIR/rs" bash "$RUN" updates-full apply
  [ "$status" -eq 0 ] && [ -e "$BATS_TEST_TMPDIR/applied" ]
  grep -q 'apply (approved)' "$BATS_TEST_TMPDIR/st/log.jsonl"
}
@test "run starts the system unit without blocking, only for an existing root job" {
  touch "$P/jobs/updates-full.sh"
  trun updates-full run; [ "$status" -eq 0 ]
  [[ $output == "systemctl start --no-block dots-ops@updates-full.service" ]]
  trun nope run; [ "$status" -eq 2 ]
}
@test "run-now (R4) runs the root job synchronously with OPS_FORCE=1, allow-listed like run" {
  touch "$P/jobs/disk-clean-system.sh"
  printf '#!/bin/sh\necho "job $1 force=$OPS_FORCE root=$OPS_IS_ROOT"\n' > "$P/dots-ops-job"; chmod +x "$P/dots-ops-job"
  trun disk-clean-system run-now; [ "$status" -eq 0 ]
  [[ $output == "job disk-clean-system force=1 root=1" ]]
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
  head -1 "$RUN" | grep -qx '#!/bin/bash'
  grep -q '^  P=/usr/local/lib/dots-ops;' "$RUN"
  grep -q 'JOB_BIN=/usr/local/bin/dots-ops-job' "$RUN"
  ! grep -nE '\$HOME|/home/|XDG_' "$RUN"
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
  ! grep -q '^User=' "$u"
  [ -f "$R/system/dots-ops/units/dots-ops-system-idle.target" ]
}
@test "sudoers file has exactly one rule" {
  [ "$(grep -cvE '^\s*(#|$)' "$R/system/dots-ops/sudoers")" -eq 1 ]
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
  jq -cn '{question:"Apply updates?",action:"root:updates-full apply",asked:5}' > "$OPS_ROOT_STATE/ask-updates-full.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  p="$OPS_STATE/pending/updates-full.json"
  [ "$(jq -r .action "$p")" = "root:updates-full apply" ] && [ "$(jq -r .question "$p")" = "Apply updates?" ]
  [ ! -e "$OPS_STATE/state/ask-updates-full.json" ]       # asks are not statuses
  rm -f "$p"                                               # user skipped it
  run bash "$CLI" relay; [ ! -e "$p" ]                     # same ask → not re-asked
  jq -cn '{question:"Apply updates?",action:"root:updates-full apply",asked:9}' > "$OPS_ROOT_STATE/ask-updates-full.json"
  run bash "$CLI" relay; [ -e "$p" ]                       # root asked again → re-asked
}
@test "relay ignores non-root actions, bad names and bad statuses" {
  relay_setup
  jq -cn '{question:"x",action:"user:touch /tmp/pwn"}' > "$OPS_ROOT_STATE/ask-evil.json"
  rootstate weird bogus "x" 5; cp "$OPS_ROOT_STATE/weird.json" "$OPS_ROOT_STATE/Bad_Name.json"
  run bash "$CLI" relay; [ "$status" -eq 0 ]
  [ ! -e "$OPS_STATE/pending/evil.json" ] && [ ! -e "$OPS_STATE/state/weird.json" ] && [ ! -e "$OPS_STATE/state/Bad_Name.json" ]
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
  grep -q 'install -m 755 .*/system/dots-ops/bin/dots-ops-run" /usr/local/bin/dots-ops-run' "$s"
  grep -qx 'L=/usr/local/lib/dots-ops' "$s"; grep -q 'chown -R root:root "$L"' "$s"; grep -q 'chmod -R go-w "$L"' "$s"
}
@test "installer is a no-op on NixOS (the Nix module installs it there)" {
  s=$(render_installer data-nixos-tmux.toml); bash -n "$s"
  ! grep -q sudo "$s"
}
