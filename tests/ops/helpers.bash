# shared bats setup: isolated state dir + recording notify-send
setup_ops() {
  export OPS_STATE="$BATS_TEST_TMPDIR/state" OPS_ROOT_STATE="$BATS_TEST_TMPDIR/root"
  export OPS_NOTIFY="$BATS_TEST_TMPDIR/notify" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$NOTIFY_LOG" > "$OPS_NOTIFY"; chmod +x "$OPS_NOTIFY"
  : > "$NOTIFY_LOG"
  source "$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh"
}
notified() { wc -l < "$NOTIFY_LOG" | tr -d ' '; }

# hermetic: a runner under systemd exports INVOCATION_ID; code under test reads it (dots-ops-run inline guard)
unset INVOCATION_ID
