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
  local c; for c in systemctl systemd-run; do
    printf '#!/bin/sh\necho "%s $*" >> %s/calls.log\n' "$c" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fakebin/$c"
  done
  printf '#!/bin/sh\n[ -n "$STUB_LOCKED" ]\n' > "$BATS_TEST_TMPDIR/fakebin/pgrep"
  printf '#!/bin/sh\n[ -n "$STUB_SESSION" ] && echo "1 1000 u seat0"\nexit 0\n' > "$BATS_TEST_TMPDIR/fakebin/loginctl"
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
@test "fallback with screen locked on AC: flag, restart, 2h idle-end timer" {
  stubs; STUB_LOCKED=1 STUB_SESSION=1 run bash "$BIN/executable_dots-ops" idle-start --fallback
  [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
  grep -q 'systemctl --user restart --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/calls.log"
  grep -Eq '^systemd-run --user --on-active=2h /.*/executable_dots-ops idle-end$' "$BATS_TEST_TMPDIR/calls.log"
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
