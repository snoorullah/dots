load helpers
setup() { setup_ops; export OPS_ASK_UI=0; }

@test "ops_ask writes a pending file with question, action, expiry" {
  ops_ask updates-full "Apply 42 updates?" "root:updates-full apply"
  run jq -r '.question+"|"+.action' "$OPS_STATE/pending/updates-full.json"
  [ "$output" = "Apply 42 updates?|root:updates-full apply" ]
}
@test "a live pending is not re-asked" {
  ops_ask j "q" "user:true"; run ops_ask_pending j; [ "$status" -eq 0 ]
}
@test "expired pending counts as skip and is removed" {
  ops_ask j "q" "user:true"
  jq '.expires=1' "$OPS_STATE/pending/j.json" > t && mv t "$OPS_STATE/pending/j.json"
  run ops_ask_pending j; [ "$status" -ne 0 ]; [ ! -e "$OPS_STATE/pending/j.json" ]
}
@test "approve runs a user action and clears pending" {
  ops_ask j "q" "user:touch $BATS_TEST_TMPDIR/done"
  ops_answer j approve
  [ -e "$BATS_TEST_TMPDIR/done" ] && [ ! -e "$OPS_STATE/pending/j.json" ]
}
@test "approve of a root action calls sudo OPS_RUNNER with job and action (R1)" {
  export OPS_SUDO="$BATS_TEST_TMPDIR/sudo" OPS_RUNNER=/usr/local/bin/dots-ops-run
  printf '#!/bin/sh\necho "$*" > %s/sudo.args\n' "$BATS_TEST_TMPDIR" > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  ops_ask updates-full "q" "root:updates-full apply"; ops_answer updates-full approve
  [ "$(cat "$BATS_TEST_TMPDIR/sudo.args")" = "/usr/local/bin/dots-ops-run updates-full apply" ]
}
@test "OPS_RUNNER defaults to /usr/local path unless the NixOS path exists (R1)" {
  run bash -c "unset OPS_RUNNER; source $BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh; echo \$OPS_RUNNER"
  if [ -x /run/current-system/sw/bin/dots-ops-run ]; then
    [ "$output" = /run/current-system/sw/bin/dots-ops-run ]
  else
    [ "$output" = /usr/local/bin/dots-ops-run ]
  fi
}
@test "OPS_SUDO defaults to 'sudo -n' (R8)" {
  run bash -c "unset OPS_SUDO; source $BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh; echo \$OPS_SUDO"
  [ "$output" = "sudo -n" ]
}
@test "a failing sudo is logged and does not hang or abort (R8)" {
  export OPS_SUDO="$BATS_TEST_TMPDIR/sudo"; printf '#!/bin/sh\nexit 1\n' > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  ops_ask j "q" "root:j apply"
  run ops_answer j approve
  [ "$status" -ne 0 ]
  grep -q '"level":"warn"' "$OPS_STATE/log.jsonl"
}
@test "snooze keeps it silent for 24h" {
  ops_ask j "q" "user:true"; ops_answer j snooze
  run ops_ask_pending j; [ "$status" -eq 0 ]
  [ "$(jq -r .snooze_until "$OPS_STATE/pending/j.json")" -gt "$(date +%s)" ]
}
@test "idle_ok: idle flag + on AC -> ok (Review Focus 3)" {
  mkdir -p "$BATS_TEST_TMPDIR/ps/AC" ; echo Mains > "$BATS_TEST_TMPDIR/ps/AC/type"; echo 1 > "$BATS_TEST_TMPDIR/ps/AC/online"
  export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/idle"; touch "$OPS_IDLE_FLAG"
  run ops_idle_ok; [ "$status" -eq 0 ]
}
@test "idle_ok: on battery -> not ok even when idle" {
  mkdir -p "$BATS_TEST_TMPDIR/ps/AC" "$BATS_TEST_TMPDIR/ps/BAT0"
  echo Mains > "$BATS_TEST_TMPDIR/ps/AC/type"; echo 0 > "$BATS_TEST_TMPDIR/ps/AC/online"; echo Battery > "$BATS_TEST_TMPDIR/ps/BAT0/type"
  export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/idle"; touch "$OPS_IDLE_FLAG"
  run ops_idle_ok; [ "$status" -ne 0 ]
}
@test "idle_ok: desktop with no battery counts as AC" {
  mkdir -p "$BATS_TEST_TMPDIR/ps"; export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/idle"; touch "$OPS_IDLE_FLAG"
  run ops_idle_ok; [ "$status" -eq 0 ]
}
@test "idle_ok: not idle and not fallback -> not ok" {
  mkdir -p "$BATS_TEST_TMPDIR/ps"; export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/none"
  run ops_idle_ok; [ "$status" -ne 0 ]
}
@test "root context defaults OPS_IDLE_FLAG to /run/dots-ops/idle (R3)" {
  run bash -c "unset OPS_IDLE_FLAG; export OPS_IS_ROOT=1; source $BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh; echo \$OPS_IDLE_FLAG"
  [ "$output" = /run/dots-ops/idle ]
}
@test "failing sudo also sets job state to warn (R12)" {
  export OPS_SUDO="$BATS_TEST_TMPDIR/sudo"; printf '#!/bin/sh\nexit 1\n' > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  ops_ask j "q" "root:j apply"
  run ops_answer j approve
  [ "$(jq -r .status "$OPS_STATE/state/j.json")" = warn ]
}
@test "idle_ok: desktop with only a scope=Device battery counts as AC" {
  mkdir -p "$BATS_TEST_TMPDIR/ps/hidpp_battery_0"
  echo Battery > "$BATS_TEST_TMPDIR/ps/hidpp_battery_0/type"; echo Device > "$BATS_TEST_TMPDIR/ps/hidpp_battery_0/scope"
  export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps" OPS_IDLE_FLAG="$BATS_TEST_TMPDIR/idle"; touch "$OPS_IDLE_FLAG"
  run ops_on_ac; [ "$status" -eq 0 ]
  run ops_idle_ok; [ "$status" -eq 0 ]
}
@test "corrupt pending is removed and re-asked (R13a)" {
  echo 'not json{' > "$OPS_STATE/pending/j.json"
  run ops_ask_pending j; [ "$status" -ne 0 ]
  [ ! -e "$OPS_STATE/pending/j.json" ]
}
@test "approving an expired pending does not run the action (R13b)" {
  ops_ask j "q" "user:touch $BATS_TEST_TMPDIR/ran"
  jq '.expires=1' "$OPS_STATE/pending/j.json" > t && mv t "$OPS_STATE/pending/j.json"
  run ops_answer j approve
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ] && [ ! -e "$OPS_STATE/pending/j.json" ]
  grep -q "approval expired" "$OPS_STATE/log.jsonl"
}
