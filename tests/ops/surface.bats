load helpers
setup() {
  setup_ops; export OPS_ASK_UI=0
  export OPS_LIB="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh"
  CLI="$BATS_TEST_DIRNAME/../../home/private_dot_local/private_bin/executable_dots-ops"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"; export PKILL_LOG="$BATS_TEST_TMPDIR/pkill.log"
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$PKILL_LOG" > "$BIN/pkill"; chmod +x "$BIN/pkill"
  export PATH="$BIN:$PATH"
}
wb() { bash "$CLI" waybar; }

@test "waybar with no states is ok" {
  run wb; [ "$status" -eq 0 ]
  echo "$output" | jq -e '.text=="✓" and .class=="ok"'
}
@test "one warn shows '! 1' class warn" {
  ops_state a warn "disk 85%"
  run wb; echo "$output" | jq -e '.text=="! 1" and .class=="warn"'
  [[ $(echo "$output" | jq -r .tooltip) == *"a: disk 85%"* ]]
}
@test "fail plus warn shows '✗ 2' class fail (counts fail jobs)" {
  ops_state a fail "x"; ops_state b fail "y"; ops_state c warn "z"
  run wb; echo "$output" | jq -e '.text=="✗ 2" and .class=="fail"'
}
@test "live pending appends ask count and raises class to warn" {
  ops_ask j "Apply updates?" "user:true"
  run wb; echo "$output" | jq -e '.text=="✓ · 1 ask" and .class=="warn"'
  [[ $(echo "$output" | jq -r .tooltip) == *"Apply updates?"* ]]
}
@test "pending on top of fail keeps class fail" {
  ops_state a fail "x"; ops_ask j "q" "user:true"
  run wb; echo "$output" | jq -e '.text=="✗ 1 · 1 ask" and .class=="fail"'
}
@test "summaries with quotes still give valid JSON" {
  ops_state a warn 'he said "hi" \ and
newline'
  run wb; echo "$output" | jq -e .text
}
@test "ops_state and ops_answer signal waybar; root does not" {
  ops_state a ok fine; grep -q -- '-RTMIN+9 -x waybar' "$PKILL_LOG"
  : > "$PKILL_LOG"; ops_ask j q "user:true"; ops_answer j skip; grep -q -- '-RTMIN+9' "$PKILL_LOG"
  : > "$PKILL_LOG"; OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/r" ops_state rj ok fine; [ ! -s "$PKILL_LOG" ]
}
@test "ops_status_lines emits job ⟂ status ⟂ summary ⟂ age, worst first" {
  ops_state good ok fine; ops_state bad fail "broke"
  run ops_status_lines
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "bad ⟂ fail ⟂ broke ⟂ "* ]]
  [[ ${lines[1]} == "good ⟂ ok ⟂ fine ⟂ "* ]]
}
@test "ops_status_lines includes pending asks" {
  ops_ask j "Apply?" "user:true"
  run ops_status_lines; [[ $output == "j ⟂ ask ⟂ Apply? ⟂ "* ]]
}
@test "status wiring: fzf gets header and bindings" {
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/fzf.args"; cat >/dev/null\n' "$BATS_TEST_TMPDIR" > "$BIN/fzf"; chmod +x "$BIN/fzf"
  ops_state a warn w
  run bash "$CLI" status; [ "$status" -eq 0 ]
  grep -q 'enter: log · ctrl-a: approve · ctrl-s: snooze · ctrl-k: skip · ctrl-r: run now' "$BATS_TEST_TMPDIR/fzf.args"
  grep -q 'ctrl-r:execute' "$BATS_TEST_TMPDIR/fzf.args"; grep -q 'reload' "$BATS_TEST_TMPDIR/fzf.args"
}
@test "garbage state file next to a fail file: class fail, counted, tooltip names it" {
  ops_state a fail "x"; echo '{not json' > "$OPS_STATE/state/junk.json"
  run wb; echo "$output" | jq -e '.text=="✗ 1" and .class=="fail"'
  [[ $(echo "$output" | jq -r .tooltip) == *"junk: unreadable state"* ]]
  [[ $(echo "$output" | jq -r .tooltip) == *"a: x"* ]]
}
@test "garbage state file alone: class warn, never ok" {
  echo '{not json' > "$OPS_STATE/state/junk.json"
  run wb; echo "$output" | jq -e '.text=="! 1" and .class=="warn"'
}
@test "ops_status_lines survives a garbage state file and lists it" {
  ops_state a fail "x"; echo '{not json' > "$OPS_STATE/state/junk.json"
  run ops_status_lines; [ "$status" -eq 0 ]
  [[ ${lines[0]} == "a ⟂ fail ⟂ x ⟂ "* ]]
  [[ ${lines[1]} == "junk ⟂ warn ⟂ unreadable state ⟂ "* ]]
}
@test "snoozed ask is hidden: waybar stays ok with no ask text, no status row (R25)" {
  ops_ask j q "user:true"; ops_answer j snooze
  [ -f "$OPS_STATE/pending/j.json" ]
  run wb; echo "$output" | jq -e '.text=="✓" and .class=="ok"'
  [[ $output != *ask* ]]
  run ops_status_lines; [[ $output != *"j ⟂"* ]]
}
