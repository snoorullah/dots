bats_require_minimum_version 1.5.0
# system/sshd/baseline.sh (C1): the root script's sshd baseline on every non-NixOS machine, org-managed included.
# Key-only drop-in written and validated before sshd is enabled; rolled back if sshd -t rejects it; sshd enabled
# only when the owner has an authorized key. sshd, systemctl and ssh-keygen are stubs; /etc/ssh is a temp dir.
R="$BATS_TEST_DIRNAME/../.."
B="$R/system/sshd/baseline.sh"

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
calls() { cat "$STUB_LOG"; }

setup() {
  export BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export SSHD_CONFIG="$BATS_TEST_TMPDIR/etc-ssh/sshd_config" SSHD_DIR="$BATS_TEST_TMPDIR/etc-ssh/sshd_config.d"
  mkdir -p "${SSHD_CONFIG%/*}"; printf 'UsePAM yes\nPasswordAuthentication yes\n' > "$SSHD_CONFIG"
  export AUTH_KEYS="$BATS_TEST_TMPDIR/home/.ssh/authorized_keys"; mkdir -p "${AUTH_KEYS%/*}"
  export SSHD_WAS_ON=0
  # systemctl: units in STUB_UNITS exist (cat), STUB_ACTIVE are active
  mkstub systemctl 'echo "systemctl $*" >> "$STUB_LOG"
for last; do :; done
case " $* " in
  *" cat "*) case " ${STUB_UNITS:-ssh.service ssh.socket} " in *" $last "*) exit 0 ;; esac; exit 1 ;;
  *" is-active "*) case " ${STUB_ACTIVE:-} " in *" $last "*) exit 0 ;; esac; exit 3 ;;
esac; exit 0'
  mkstub sshd 'echo "sshd $*" >> "$STUB_LOG"
case "$1" in
  -t) exit ${STUB_SSHD_T_RC:-0} ;;
  -V) echo "OpenSSH_${STUB_SSHD_VER:-9.6}p1, OpenSSL 3.0.13" >&2; exit 0 ;;
esac; exit 0'
  mkstub ssh-keygen 'echo "ssh-keygen $*" >> "$STUB_LOG"; exit 0'
}

@test "sshd-baseline: drop-in matches dots-ops ssh-harden 50-dots.conf (same keys, same values)" {
  diff <(grep -v '^#' "$R/system/sshd/40-dots-baseline.conf" | sort) <(grep -v '^#' "$R/system/dots-ops/sshd/50-dots.conf" | sort)
}

@test "sshd-baseline: key present -> Include added at the top, drop-in written, validated, sshd enabled" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"
  run bash "$B"
  [ "$status" = 0 ]
  [ "$(head -n 1 "$SSHD_CONFIG")" = "Include $SSHD_DIR/*.conf" ]
  grep -qx 'UsePAM yes' "$SSHD_CONFIG"
  [ "$(grep -v '^#' "$SSHD_DIR/40-dots-baseline.conf")" = "$(printf 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no')" ]
  calls | grep -qx "sshd -t -f $SSHD_CONFIG"
  calls | grep -qx 'ssh-keygen -A'
  calls | grep -qx 'systemctl enable --now ssh.service'
  # validated before it is enabled
  [ "$(calls | grep -n 'sshd -t' | cut -d: -f1)" -lt "$(calls | grep -n 'enable --now' | cut -d: -f1)" ]
}

@test "sshd-baseline: Debian-style Include already present -> sshd_config untouched" {
  printf 'Include /etc/ssh/sshd_config.d/*.conf\nUsePAM yes\n' > "$SSHD_CONFIG"; cp "$SSHD_CONFIG" "$BATS_TEST_TMPDIR/orig"
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"
  run bash "$B"
  [ "$status" = 0 ]
  cmp "$SSHD_CONFIG" "$BATS_TEST_TMPDIR/orig"
}

@test "sshd-baseline: idempotent (second run: one Include, same drop-in)" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"
  bash "$B" 2>/dev/null; cp "$SSHD_DIR/40-dots-baseline.conf" "$BATS_TEST_TMPDIR/first"
  run bash "$B"
  [ "$status" = 0 ]
  [ "$(grep -c '^Include' "$SSHD_CONFIG")" = 1 ]
  cmp "$SSHD_DIR/40-dots-baseline.conf" "$BATS_TEST_TMPDIR/first"
}

@test "sshd-baseline: no authorized key -> installed but disabled (socket too), never enabled" {
  : > "$AUTH_KEYS"
  run bash "$B"
  [ "$status" = 0 ]
  [ -f "$SSHD_DIR/40-dots-baseline.conf" ]
  ! calls | grep -q 'enable --now'
  calls | grep -qx 'systemctl disable --now ssh.socket'
  calls | grep -qx 'systemctl disable --now ssh.service'
  [[ $output == *"left DISABLED"* ]]
}

@test "sshd-baseline: comment-only authorized_keys counts as no key; missing file too" {
  printf '# no keys yet\n\n' > "$AUTH_KEYS"
  run bash "$B"; [ "$status" = 0 ]; ! calls | grep -q 'enable --now'
  rm -f "$AUTH_KEYS"; : > "$STUB_LOG"
  run bash "$B"; [ "$status" = 0 ]; ! calls | grep -q 'enable --now'
}

@test "sshd-baseline: no key but sshd was already on before dots -> left running, not reloaded, warned" {
  : > "$AUTH_KEYS"; export SSHD_WAS_ON=1 STUB_ACTIVE=ssh.service
  run bash "$B"
  [ "$status" = 0 ]
  ! calls | grep -qE 'disable|reload|restart|enable'
  [[ $output == *WARNING* ]]
}

@test "sshd-baseline: key present and sshd running -> reloaded, not re-enabled" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"; export STUB_ACTIVE=ssh.service
  run bash "$B"
  [ "$status" = 0 ]
  calls | grep -qx 'systemctl reload ssh.service'
}

@test "sshd-baseline: sshd -t rejects -> drop-in removed, Include rolled back, sshd stopped, exit 1" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"; cp "$SSHD_CONFIG" "$BATS_TEST_TMPDIR/orig"
  export STUB_SSHD_T_RC=255
  run bash "$B"
  [ "$status" = 1 ]
  [ ! -e "$SSHD_DIR/40-dots-baseline.conf" ]
  cmp "$SSHD_CONFIG" "$BATS_TEST_TMPDIR/orig"
  ! calls | grep -q 'enable --now'
  calls | grep -qx 'systemctl disable --now ssh.service'
  [[ $output == *"rolled back"* ]]
}

@test "sshd-baseline: sshd -t rejects -> a previous drop-in is restored, not deleted" {
  mkdir -p "$SSHD_DIR"; echo "# previous" > "$SSHD_DIR/40-dots-baseline.conf"
  export STUB_SSHD_T_RC=1
  run bash "$B"
  [ "$status" = 1 ]
  [ "$(cat "$SSHD_DIR/40-dots-baseline.conf")" = "# previous" ]
}

@test "sshd-baseline: OpenSSH < 8.7 gets ChallengeResponseAuthentication (as ssh-harden R49)" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"; export STUB_SSHD_VER=8.4
  run bash "$B"
  [ "$status" = 0 ]
  grep -qx 'ChallengeResponseAuthentication no' "$SSHD_DIR/40-dots-baseline.conf"
  ! grep -q '^KbdInteractiveAuthentication' "$SSHD_DIR/40-dots-baseline.conf"
}

@test "sshd-baseline: Fedora/Arch unit name sshd.service is used when ssh.service does not exist" {
  echo "ssh-ed25519 AAAA owner@laptop" > "$AUTH_KEYS"; export STUB_UNITS=sshd.service
  run bash "$B"
  [ "$status" = 0 ]
  calls | grep -qx 'systemctl enable --now sshd.service'
}
