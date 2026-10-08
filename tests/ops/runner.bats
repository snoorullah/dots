load helpers
bats_require_minimum_version 1.5.0
setup() {
  setup_ops; export OPS_ASK_UI=0 OPS_JOBS_DIR="$BATS_TEST_TMPDIR/jobs" OPS_CONFIG="$BATS_TEST_TMPDIR/config.toml"
  export OPS_LIB="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh"
  mkdir -p "$OPS_JOBS_DIR"; BIN="$BATS_TEST_DIRNAME/../../home/private_dot_local/private_bin"
  printf 'job_main(){ touch %s/ran; ops_state t ok done; }\n' "$BATS_TEST_TMPDIR" > "$OPS_JOBS_DIR/t.sh"
  printf 'OPS_HEAVY=1\njob_main(){ touch %s/heavy; }\n' "$BATS_TEST_TMPDIR" > "$OPS_JOBS_DIR/h.sh"
  printf '[disk]\nwarn = 70\n[jobs.off]\nenabled = false\n' > "$OPS_CONFIG"
  printf 'job_main(){ touch %s/off; }\n' "$BATS_TEST_TMPDIR" > "$OPS_JOBS_DIR/off.sh"
}
@test "runs a job" { bash "$BIN/executable_dots-ops-job" t; [ -e "$BATS_TEST_TMPDIR/ran" ]; }
@test "heavy job skipped when not idle" {
  mkdir -p "$BATS_TEST_TMPDIR/ac"; echo Mains > "$BATS_TEST_TMPDIR/ac/type"; echo 1 > "$BATS_TEST_TMPDIR/ac/online"
  OPS_IDLE_FLAG=/nonexistent OPS_POWER_DIR="$BATS_TEST_TMPDIR" bash "$BIN/executable_dots-ops-job" h
  [ ! -e "$BATS_TEST_TMPDIR/heavy" ]; grep -q 'not idle' "$OPS_STATE/log.jsonl"
}
@test "heavy job runs when idle flag set on AC" {
  mkdir -p "$BATS_TEST_TMPDIR/ps"; touch "$BATS_TEST_TMPDIR/flag"
  OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/flag" OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" bash "$BIN/executable_dots-ops-job" h
  [ -e "$BATS_TEST_TMPDIR/heavy" ]
}
@test "disabled job skipped" { bash "$BIN/executable_dots-ops-job" off; [ ! -e "$BATS_TEST_TMPDIR/off" ]; }
@test "bad job name rejected" { run bash "$BIN/executable_dots-ops-job" '../x'; [ "$status" -eq 2 ]; }
@test "ops_cfg reads value and default" {
  source "$BIN/executable_dots-ops-job" --lib-only
  [ "$(ops_cfg disk.warn 85)" = 70 ] && [ "$(ops_cfg disk.crit 95)" = 95 ]
}
@test "dots-ops answer delegates to ops_answer" {
  ops_ask j "q?" "user:touch $BATS_TEST_TMPDIR/approved"
  bash "$BIN/executable_dots-ops" answer j approve
  [ -e "$BATS_TEST_TMPDIR/approved" ] && [ ! -e "$OPS_STATE/pending/j.json" ]
}
@test "dots-ops unknown subcommand exits 2 with usage" {
  run bash "$BIN/executable_dots-ops" bogus; [ "$status" -eq 2 ]; [[ $output == *usage* ]]
}
stubs() {   # fake systemctl/systemd-run/pgrep/loginctl recording argv; sudo stub is OPS_SUDO
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"; : > "$BATS_TEST_TMPDIR/calls.log"
  local c; for c in systemctl systemd-run busctl; do
    printf '#!/bin/sh\necho "%s $*" >> %s/calls.log\n' "$c" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fakebin/$c"
  done
  printf '#!/bin/sh\n[ -n "$STUB_LOCKED" ]\n' > "$BATS_TEST_TMPDIR/fakebin/pgrep"
  # loginctl: list-sessions (STUB_SESSION), show-user -> IdleHint (STUB_IDLE_HINT, default yes) + IdleSinceHint in µs
  # (STUB_IDLE_MIN minutes ago, default 20); show-user args are recorded so the test can check the uid asked about
  cat > "$BATS_TEST_TMPDIR/fakebin/loginctl" <<'EOF'
#!/bin/sh
case "$1" in
  show-user) echo "$*" >> "$STUB_LOGIND_LOG"
             echo "IdleHint=${STUB_IDLE_HINT:-yes}"
             echo "IdleSinceHint=$(( ($(date +%s) - ${STUB_IDLE_MIN:-20} * 60) * 1000000 ))" ;;
  *) [ -n "$STUB_SESSION" ] && echo "1 1000 u seat0" ;;
esac
exit 0
EOF
  export STUB_LOGIND_LOG="$BATS_TEST_TMPDIR/logind.log"
  chmod +x "$BATS_TEST_TMPDIR"/fakebin/*
  mkdir -p "$BATS_TEST_TMPDIR/ps"   # no battery => AC
  export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/rt/idle" OPS_SUDO="echo SUDO" OPS_RUNNER=/x/runner
  export PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
}
@test "idle-start restarts the target, sets flag, calls system idle-run" {
  stubs
  run bash "$BIN/executable_dots-ops" idle-start
  [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
  [[ $output == *"SUDO /x/runner system idle-run"* ]]
  grep -qx 'systemctl --user restart --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/calls.log"
}
@test "idle-end removes flag, stops the target, calls system idle-end, tolerates refusal" {
  stubs; mkdir -p "$(dirname "$OPS_IDLE_FLAG")"; touch "$OPS_IDLE_FLAG"
  run bash "$BIN/executable_dots-ops" idle-end
  [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]
  [[ $output == *"SUDO /x/runner system idle-end"* ]]
  grep -qx 'systemctl --user stop --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/calls.log"
  OPS_SUDO=false run bash "$BIN/executable_dots-ops" idle-end; [ "$status" -eq 0 ]
}
@test "idle-start tolerates sudo refusal" {
  stubs; OPS_SUDO=false run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
}
@test "R60 refused sudo for idle-run / idle-end -> system warn naming the fix; a later success clears it" {
  stubs
  OPS_SUDO=false run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$OPS_STATE/state/system.json")" = warn ]
  [ "$(jq -r .summary "$OPS_STATE/state/system.json")" = "root runner refused (rc=1): log out/in or check /etc/sudoers.d/dots-ops" ]
  rm -f "$OPS_STATE/state/system.json"
  OPS_SUDO=false run bash "$BIN/executable_dots-ops" idle-end; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$OPS_STATE/state/system.json")" = warn ]
  run bash "$BIN/executable_dots-ops" idle-end; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$OPS_STATE/state/system.json")" = ok ]
  rm -f "$OPS_STATE/state/system.json"; run bash "$BIN/executable_dots-ops" idle-end
  [ ! -e "$OPS_STATE/state/system.json" ]   # no state noise while everything works
}
@test "R58 fallback needs logind IdleHint=yes for >= 15 min: resume during active use (hint no / idle 5 min) is skipped" {
  stubs
  STUB_LOCKED=1 STUB_SESSION=1 STUB_IDLE_HINT=no run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]; [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]
  grep -q 'fallback skipped' "$OPS_STATE/log.jsonl"
  STUB_LOCKED=1 STUB_SESSION=1 STUB_IDLE_MIN=5 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ ! -e "$OPS_IDLE_FLAG" ]; [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]
  grep -q "^show-user $(id -u) " "$STUB_LOGIND_LOG"
  STUB_LOCKED=1 STUB_SESSION=1 STUB_IDLE_MIN=16 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ -e "$OPS_IDLE_FLAG" ]
}
@test "R58 idle-start / idle-end set the logind session idle hint (so the fallback check sees hypridle's idle), best effort" {
  stubs
  run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]
  grep -qx 'busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b true' "$BATS_TEST_TMPDIR/calls.log"
  run bash "$BIN/executable_dots-ops" idle-end; [ "$status" -eq 0 ]
  grep -qx 'busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b false' "$BATS_TEST_TMPDIR/calls.log"
  : > "$BATS_TEST_TMPDIR/calls.log"; STUB_LOCKED=1 run bash "$BIN/executable_dots-ops" idle-start --fallback
  run ! grep -q busctl "$BATS_TEST_TMPDIR/calls.log"   # the fallback reads the hint, never sets it
  run bash "$BIN/executable_dots-ops" idle-end --fallback; [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]
  run ! grep -q busctl "$BATS_TEST_TMPDIR/calls.log"   # nor does the end of the fallback window
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/fakebin/busctl"; run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]
}
@test "R58 fallback timer is not Persistent (a missed 03:30 must not fire on resume)" {
  t="$BATS_TEST_DIRNAME/../../home/private_dot_config/systemd/private_user/dots-ops-fallback.timer"
  grep -qx 'OnCalendar=\*-\*-\* 03:30:00' "$t"
  run ! grep -q '^Persistent=' "$t"
}
@test "fallback with screen locked on AC: flag, restart, 2h idle-end timer" {
  stubs; STUB_LOCKED=1 STUB_SESSION=1 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
  grep -q 'systemctl --user restart --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/calls.log"
  grep -Eq '^systemd-run --user --on-active=2h /.*/executable_dots-ops idle-end --fallback$' "$BATS_TEST_TMPDIR/calls.log"
}
@test "fallback with no graphical session on AC proceeds" {
  stubs; run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ -e "$OPS_IDLE_FLAG" ]; grep -q 'systemd-run --user --on-active=2h' "$BATS_TEST_TMPDIR/calls.log"
}
@test "fallback skipped when user active (session, not locked)" {
  stubs; STUB_SESSION=1 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]; [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]; grep -q 'fallback skipped' "$OPS_STATE/log.jsonl"
}
@test "fallback skipped on battery" {
  stubs; mkdir -p "$BATS_TEST_TMPDIR/ps/BAT0"; echo Battery > "$BATS_TEST_TMPDIR/ps/BAT0/type"
  STUB_LOCKED=1 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ ! -e "$OPS_IDLE_FLAG" ]; [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]
}
@test "run <rootjob> fails loudly when sudo refused" {
  OPS_SUDO=false run --separate-stderr bash "$BIN/executable_dots-ops" run updates-sec --now
  [ "$status" -ne 0 ]; [[ $stderr == *"updates-sec"*failed* ]]
  grep -q 'run failed' "$OPS_STATE/log.jsonl"
}
@test "run <rootjob> --now uses sudo run-now; without --now uses run" {
  export OPS_SUDO="echo SUDO" OPS_RUNNER=/x/runner
  run bash "$BIN/executable_dots-ops" run updates-sec --now; [ "$output" = "SUDO /x/runner updates-sec run-now" ]
  run bash "$BIN/executable_dots-ops" run updates-sec; [ "$output" = "SUDO /x/runner updates-sec run" ]
}
@test "run <userjob> --now runs inline with OPS_FORCE" {
  OPS_IDLE_FLAG=/nonexistent OPS_POWER_DIR="$BATS_TEST_TMPDIR" bash "$BIN/executable_dots-ops" run h --now
  [ -e "$BATS_TEST_TMPDIR/heavy" ]
}

# ---- orgManaged: [root] enabled = false -> user code never calls sudo ----
@test "org: idle-start / idle-end make no sudo call and set no warn (flag and idle target still work)" {
  stubs; export OPS_ROOT_ENABLED=0 OPS_SUDO="$BATS_TEST_TMPDIR/sudo-called"
  printf '#!/bin/sh\necho called >> %s/sudo.log\nexit 1\n' "$BATS_TEST_TMPDIR" > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
  run bash "$BIN/executable_dots-ops" idle-end; [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]
  [ ! -e "$BATS_TEST_TMPDIR/sudo.log" ]
  [ ! -e "$OPS_STATE/state/system.json" ]
  ! grep -q 'root runner refused' "$OPS_STATE/log.jsonl" 2>/dev/null
  grep -qx 'systemctl --user restart --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/calls.log"
}
@test "org: config.toml [root] enabled = false is what turns it off" {
  stubs; printf '[disk]\nwarn = 70\n[root]\nenabled = false\n' > "$OPS_CONFIG"
  run bash "$BIN/executable_dots-ops" idle-start; [ "$status" -eq 0 ]
  [[ $output != *SUDO* ]]
  printf '[root]\nenabled = true\n' > "$OPS_CONFIG"
  run bash "$BIN/executable_dots-ops" idle-start; [[ $output == *"SUDO /x/runner system idle-run"* ]]
}
@test "org: run <rootjob> prints the disabled message and exits 2, no sudo" {
  stubs; export OPS_ROOT_ENABLED=0
  run --separate-stderr bash "$BIN/executable_dots-ops" run updates-sec --now
  [ "$status" -eq 2 ]; [[ $stderr == *"root jobs are disabled on this machine (orgManaged)"* ]]; [[ $output != *SUDO* ]]
  run --separate-stderr bash "$BIN/executable_dots-ops" run updates-sec
  [ "$status" -eq 2 ]
}
@test "org: a user job still runs with run --now when root is off" {
  export OPS_ROOT_ENABLED=0 OPS_IDLE_FLAG=/nonexistent OPS_POWER_DIR="$BATS_TEST_TMPDIR"
  bash "$BIN/executable_dots-ops" run h --now; [ -e "$BATS_TEST_TMPDIR/heavy" ]
}
