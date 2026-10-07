load helpers
setup() { setup_ops; }

@test "ops_log appends one JSON line with job, level, msg" {
  ops_log disk-watch info "hello"
  run jq -r '.job+" "+.level+" "+.msg' "$OPS_STATE/log.jsonl"
  [ "$output" = "disk-watch info hello" ]
}

@test "ok -> fail notifies once; repeated fail within 24h stays quiet" {
  ops_state smart fail "sda reallocated sectors"
  ops_state smart fail "sda reallocated sectors"
  [ "$(notified)" = 1 ]
}

@test "repeated fail after reminder window re-notifies" {
  OPS_REMIND_SECS=0 ops_state smart fail "x"
  OPS_REMIND_SECS=0 ops_state smart fail "x"
  [ "$(notified)" = 2 ]
}

@test "fail -> ok sends one recovered notification" {
  ops_state net fail "no dns"; ops_state net ok "back"; ops_state net ok "back"
  [ "$(notified)" = 2 ]
  grep -q "recovered" "$NOTIFY_LOG"
}

@test "first-ever ok is silent" {
  ops_state trim ok "done"; [ "$(notified)" = 0 ]
}

@test "notify failure queues and flush delivers later (Review Focus 2)" {
  printf '#!/bin/sh\nexit 1\n' > "$OPS_NOTIFY"
  ops_notify critical "t" "b"
  [ "$(ls "$OPS_STATE/queue" | wc -l)" = 1 ]
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$NOTIFY_LOG" > "$OPS_NOTIFY"
  ops_flush_queue
  [ "$(notified)" = 1 ] && [ "$(ls "$OPS_STATE/queue" | wc -l)" = 0 ]
}

@test "ops_run prints instead of executing in dry-run" {
  DOTS_OPS_DRY_RUN=1 run ops_run touch "$BATS_TEST_TMPDIR/should-not-exist"
  [ "$output" = "+ touch $BATS_TEST_TMPDIR/should-not-exist" ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-exist" ]
}

@test "root context writes OPS_ROOT_STATE and never notifies" {
  OPS_IS_ROOT=1 ops_state smart fail "x"
  [ -f "$OPS_ROOT_STATE/smart.json" ] && [ "$(notified)" = 0 ]
}

@test "ops_lock: second holder exits 0 without running" {
  ( ops_lock busy; sleep 2 ) &
  sleep 0.3
  run bash -c "source $BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh; ops_lock busy; echo ran"
  [ "$status" -eq 0 ]
  [[ $output != *ran* ]]
  wait
}
