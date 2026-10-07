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

@test "R62 warn notifies once on the transition, never again after the reminder window (only fail reminds)" {
  OPS_REMIND_SECS=0 ops_state net warn "x"
  OPS_REMIND_SECS=0 ops_state net warn "x"
  OPS_REMIND_SECS=0 ops_state net warn "y"
  [ "$(notified)" = 1 ]
  OPS_REMIND_SECS=0 ops_state net fail "z"; [ "$(notified)" = 2 ]   # warn -> fail is a change
  OPS_REMIND_SECS=0 ops_state net warn "w"; [ "$(notified)" = 3 ]   # fail -> warn too
}

# ---- R57: unit failure reporter (ExecStopPost) ----
@test "R57 reporter: failed/timed-out unit -> fail 'unit <result>/<code>/<status>' under the job name" {
  SERVICE_RESULT=timeout EXIT_CODE=killed EXIT_STATUS=TERM INVOCATION_ID=inv1 ops_report_unit backup
  [ "$(jq -r .status "$OPS_STATE/state/backup.json")" = fail ]
  [ "$(jq -r .summary "$OPS_STATE/state/backup.json")" = "unit timeout/killed/TERM" ]
  [ "$(notified)" = 1 ]
  SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=203 INVOCATION_ID=inv2 OPS_IS_ROOT=1 ops_report_unit smart
  [ "$(jq -r .summary "$OPS_ROOT_STATE/smart.json")" = "unit exit-code/exited/203" ]
}
@test "R57 reporter: success writes nothing; a failure the job already reported in this run is kept" {
  SERVICE_RESULT=success EXIT_CODE=exited EXIT_STATUS=0 INVOCATION_ID=i ops_report_unit backup
  [ ! -e "$OPS_STATE/state/backup.json" ]
  INVOCATION_ID=run1 ops_state backup fail "restic: repository locked"
  SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=1 INVOCATION_ID=run1 ops_report_unit backup
  [ "$(jq -r .summary "$OPS_STATE/state/backup.json")" = "restic: repository locked" ]
  # an action unit reports under <job>-<action>; its own failure state (e.g. updates-full) counts as already reported
  INVOCATION_ID=run2 OPS_IS_ROOT=1 ops_state updates-full fail "pacman -Syu: conflict"
  SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=1 INVOCATION_ID=run2 OPS_IS_ROOT=1 ops_report_unit updates-full-apply act
  [ ! -e "$OPS_ROOT_STATE/updates-full-apply.json" ]
}
@test "R57 reporter: ok written earlier in the same run does not hide a later crash; action success clears its own unit failure" {
  INVOCATION_ID=run3 ops_state disk-watch ok "worst 10%"
  SERVICE_RESULT=signal EXIT_CODE=killed EXIT_STATUS=KILL INVOCATION_ID=run3 ops_report_unit disk-watch
  [ "$(jq -r .summary "$OPS_STATE/state/disk-watch.json")" = "unit signal/killed/KILL" ]
  SERVICE_RESULT=signal EXIT_CODE=killed EXIT_STATUS=KILL INVOCATION_ID=a1 ops_report_unit firewall-apply act
  [ "$(jq -r .status "$OPS_STATE/state/firewall-apply.json")" = fail ]
  SERVICE_RESULT=success EXIT_CODE=exited EXIT_STATUS=0 INVOCATION_ID=a2 ops_report_unit firewall-apply act
  [ "$(jq -r .status "$OPS_STATE/state/firewall-apply.json")" = ok ]
  SERVICE_RESULT=success INVOCATION_ID=a3 ops_report_unit never-failed act; [ ! -e "$OPS_STATE/state/never-failed.json" ]
}
@test "R57 dots-ops-job --report-failure <name> [act] is the reporter entry point; bad names refused" {
  J="$BATS_TEST_DIRNAME/../../home/private_dot_local/private_bin/executable_dots-ops-job"
  export OPS_LIB="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh"
  run env SERVICE_RESULT=timeout EXIT_CODE=killed EXIT_STATUS=TERM INVOCATION_ID=x bash "$J" --report-failure backup-check
  [ "$status" -eq 0 ]; [ "$(jq -r .summary "$OPS_STATE/state/backup-check.json")" = "unit timeout/killed/TERM" ]
  run env SERVICE_RESULT=timeout bash "$J" --report-failure ../x; [ "$status" -eq 2 ]
  run env SERVICE_RESULT=timeout bash "$J" --report-failure ask-x; [ "$status" -eq 2 ]
  run env SERVICE_RESULT=timeout bash "$J" --report-failure ok bogus; [ "$status" -eq 2 ]
}
@test "R57 every dots-ops job unit carries the ExecStopPost reporter (user + system template)" {
  R="$BATS_TEST_DIRNAME/../.."
  grep -qx 'ExecStopPost=%h/.local/bin/dots-ops-job --report-failure %i' "$R/home/private_dot_config/systemd/private_user/dots-ops@.service"
  grep -qx 'ExecStopPost=/usr/local/bin/dots-ops-job --report-failure %i' "$R/system/dots-ops/units/dots-ops@.service"
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
