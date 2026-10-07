load helpers
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
@test "idle-start/idle-end manage flag and call system runner via sudo" {
  export OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/rt/idle" OPS_SUDO="echo SUDO" OPS_RUNNER=/x/runner
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\necho "systemctl $*" >> %s/sc.log\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fakebin/systemctl"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/systemctl"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run bash "$BIN/executable_dots-ops" idle-start
  [ "$status" -eq 0 ]; [ -e "$OPS_IDLE_FLAG" ]
  [[ $output == *"SUDO /x/runner system idle-run"* ]]; grep -q 'start --no-block dots-ops-idle.target' "$BATS_TEST_TMPDIR/sc.log"
  OPS_SUDO="false" PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run bash "$BIN/executable_dots-ops" idle-end
  [ "$status" -eq 0 ]; [ ! -e "$OPS_IDLE_FLAG" ]
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
