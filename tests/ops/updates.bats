load helpers
bats_require_minimum_version 1.5.0
# Updates domain: updates-check, updates-security, updates-full/apply, reboot-needed (+ reboot actions), firmware, dots-update,
# the R5 two-button ask, timers and the reboot path unit, root-layer packages.
# Every command that could mutate is a stub on PATH (tests/ops/stubs) or runs under DOTS_OPS_DRY_RUN=1.
R="$BATS_TEST_DIRNAME/../.."
UJ="$R/home/private_dot_local/lib/dots-ops/jobs"
SJ="$R/system/dots-ops/jobs"
SA="$R/system/dots-ops/actions"
SU="$R/system/dots-ops/units"
LIB="$R/home/private_dot_local/lib/dots-ops/lib.sh"

setup() {
  setup_ops
  export ORIG_PATH="$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ops_cfg() { echo "$2"; }
}
runjob() { source "$1"; job_main; }
ustate() { jq -r ".$2" "$OPS_STATE/state/$1.json"; }
rstate() { jq -r ".$2" "$OPS_ROOT_STATE/$1.json"; }
asroot() {   # root-job context with os-release $1
  export OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/root" OPS_STATE="$BATS_TEST_TMPDIR/rootlog"
  mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks"
  printf '%b' "$1" > "$BATS_TEST_TMPDIR/os"; export OPS_OS_RELEASE="$BATS_TEST_TMPDIR/os"
}
DEB='ID=ubuntu\nID_LIKE=debian\n'; ARCH='ID=arch\n'; FED='ID=fedora\n'; NIX='ID=nixos\n'
# runact <job> <action>: source the root action under the runner's shell options, dry-run
runact() { DOTS_OPS_DRY_RUN=1 bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/$1/$2.sh"; }
without_cmd() {   # without_cmd <cmd>: hermetic PATH = stubs (minus <cmd>) + the basic tools the jobs use, nothing else
  local d="$BATS_TEST_TMPDIR/nobin" s t p
  mkdir -p "$d"
  for s in "$BATS_TEST_DIRNAME"/stubs/*; do [ "${s##*/}" = "$1" ] || ln -sf "$s" "$d/${s##*/}"; done
  for t in bash sh jq date grep cat mkdir mv rm stat tr tail head awk sed flock find sort basename dirname uname chmod wc env touch; do
    p=$(PATH="$ORIG_PATH" command -v "$t") && ln -sf "$p" "$d/$t"
  done
  rm -f "$d/$1"
  PATH="$d"
}

# ---- updates-check ----
@test "updates-check debian: refreshes indexes via ops_run, counts 3 Inst lines, writes the ask" {
  asroot "$DEB"
  export STUB_APT_INST='Inst libc6 [1] (2 Ubuntu)\nInst linux-image-generic [1] (2 Ubuntu)\nInst curl [1] (2 Ubuntu)\nConf curl (2 Ubuntu)\n'
  runjob "$SJ/updates-check.sh"
  grep -qx 'apt-get update -qq' "$STUB_LOG"
  [ "$(rstate ask-updates-full question)" = "Apply 3 updates (kernel/driver: yes)?" ]
  [ "$(rstate ask-updates-full action)" = "root:updates-full apply" ]
  [ "$(rstate updates-check status)" = warn ]; [ "$(rstate updates-check summary)" = "3 pending" ]
}
@test "updates-check debian: dry run prints the index refresh instead of running it" {
  asroot "$DEB"; export DOTS_OPS_DRY_RUN=1
  run bash -c "source '$LIB'; source '$SJ/updates-check.sh'; job_main"
  ! grep -q 'apt-get update' "$STUB_LOG"
  [[ $output == *"+ apt-get update -qq"* ]]
}
@test "updates-check debian: nothing pending -> ok, no ask" {
  asroot "$DEB"; export STUB_APT_INST=''
  runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-updates-full.json" ]
}
@test "updates-check: a stale ask is withdrawn when nothing is pending any more" {
  asroot "$DEB"; echo '{}' > "$OPS_ROOT_STATE/ask-updates-full.json" 2>/dev/null || { mkdir -p "$OPS_ROOT_STATE"; echo '{}' > "$OPS_ROOT_STATE/ask-updates-full.json"; }
  export STUB_APT_INST=''; runjob "$SJ/updates-check.sh"
  [ ! -e "$OPS_ROOT_STATE/ask-updates-full.json" ]
}
@test "updates-check arch: checkupdates only, never pacman -Sy; kernel flag no" {
  asroot "$ARCH"; export STUB_CHECKUPDATES='firefox 1 -> 2\nvim 1 -> 2\n'
  runjob "$SJ/updates-check.sh"
  [ "$(rstate ask-updates-full question)" = "Apply 2 updates (kernel/driver: no)?" ]
  grep -q '^checkupdates' "$STUB_LOG"; ! grep -q '^pacman' "$STUB_LOG"
}
@test "updates-check arch: kernel flag from nvidia/linux, checkupdates rc 2 means none" {
  asroot "$ARCH"; export STUB_CHECKUPDATES='nvidia-utils 1 -> 2\n'
  runjob "$SJ/updates-check.sh"
  [[ $(rstate ask-updates-full question) == *"kernel/driver: yes"* ]]
  rm -f "$OPS_ROOT_STATE/ask-updates-full.json"; export STUB_CHECKUPDATES=''
  runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = ok ]
}
@test "updates-check arch: checkupdates missing -> warn install pacman-contrib" {
  asroot "$ARCH"; without_cmd checkupdates
  runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = warn ]; [[ $(rstate updates-check summary) == *pacman-contrib* ]]
}
@test "updates-check fedora: dnf check-update exit 100 = updates, counted; 0 = none; else warn" {
  asroot "$FED"
  export STUB_DNF_RC=100 STUB_DNF_OUT='\nkernel-core.x86_64   6.1  updates\nbash.x86_64   5.2  updates\n\nObsoleting Packages\nold.x86_64 1 updates\n'
  runjob "$SJ/updates-check.sh"
  [ "$(rstate ask-updates-full question)" = "Apply 2 updates (kernel/driver: yes)?" ]
  grep -qx 'dnf -q check-update' "$STUB_LOG"
  rm -f "$OPS_ROOT_STATE/ask-updates-full.json"; STUB_DNF_RC=0 STUB_DNF_OUT='' runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-updates-full.json" ]
  STUB_DNF_RC=1 STUB_DNF_OUT='' runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = warn ]
}
@test "updates-check nixos -> ok n/a: nixos-rebuild, no package manager touched" {
  asroot "$NIX"; runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = ok ]; [[ $(rstate updates-check summary) == "n/a: nixos-rebuild"* ]]
  [ "$(cat "$STUB_LOG")" = "systemctl start --no-block dots-ops@reboot-needed.service" ]   # only the reboot re-check
}

# ---- updates-security ----
@test "updates-security is heavy" { source "$SJ/updates-security.sh"; [ "$OPS_HEAVY" = 1 ]; }
@test "updates-security debian: unattended-upgrade -v" {
  asroot "$DEB"; runjob "$SJ/updates-security.sh"
  grep -qx 'unattended-upgrade -v' "$STUB_LOG"; [ "$(rstate updates-security status)" = ok ]
}
@test "updates-security debian: failure -> fail with output" {
  asroot "$DEB"; STUB_UU_FAIL='boom dpkg' runjob "$SJ/updates-security.sh"
  [ "$(rstate updates-security status)" = fail ]; [[ $(rstate updates-security summary) == *"boom dpkg"* ]]
}
@test "updates-security fedora: dnf upgrade --security -y" {
  asroot "$FED"; runjob "$SJ/updates-security.sh"
  grep -qx 'dnf upgrade --security -y' "$STUB_LOG"; [ "$(rstate updates-security status)" = ok ]
}
@test "updates-security arch and nixos -> ok n/a, nothing run (Review Focus 4)" {
  asroot "$ARCH"; runjob "$SJ/updates-security.sh"
  [ "$(rstate updates-security status)" = ok ]; [[ $(rstate updates-security summary) == "n/a: no security channel"* ]]
  asroot "$NIX"; runjob "$SJ/updates-security.sh"
  [[ $(rstate updates-security summary) == n/a:* ]]
  [ ! -s "$STUB_LOG" ]
}

# ---- updates-full apply ----
@test "updates-full apply dry-run: debian command, noninteractive, keep conffiles" {
  asroot "$DEB"
  run runact updates-full apply; [ "$status" -eq 0 ]
  [[ $output == *"+ env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -o DPkg::Lock::Timeout=300 dist-upgrade"* ]]
}
@test "updates-full apply dry-run: fedora and arch commands" {
  asroot "$FED"; run runact updates-full apply
  [[ $output == *"+ dnf upgrade -y"* ]]
  asroot "$ARCH"; run runact updates-full apply
  [[ $output == *"+ pacman -Syu --noconfirm"* ]]
}
@test "updates-full apply: records rollback hint (snapper present) and queues the reboot check" {
  asroot "$ARCH"
  run runact updates-full apply; [ "$status" -eq 0 ]
  [ "$(rstate updates-full status)" = ok ]; [[ $(rstate updates-full summary) == *"rollback: snapper"* ]]
  [[ $output == *"+ systemctl start --no-block dots-ops@reboot-needed.service"* ]]
}
@test "updates-full apply: rollback hint says none without snapper/timeshift" {
  asroot "$ARCH"; without_cmd snapper
  run runact updates-full apply; [ "$status" -eq 0 ]
  [[ $(rstate updates-full summary) == *"rollback: none"* ]]
}
@test "updates-full apply: failure records step + last 3 lines + hint, exits non-zero, no reboot check" {
  asroot "$ARCH"
  run env STUB_PACMAN_FAIL='l1\nl2\nl3\nl4-last' bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/updates-full/apply.sh"
  [ "$status" -ne 0 ]
  [ "$(rstate updates-full status)" = fail ]
  s=$(rstate updates-full summary)
  [[ $s == "pacman -Syu"* ]] || [[ $s == *"pacman"* ]]
  [[ $s == *l4-last* && $s == *l3* && $s == *l2* && $s != *l1* && $s == *"rollback:"* ]]
  ! grep -q reboot-needed "$STUB_LOG"
}
@test "updates-full apply: debian failure of dist-upgrade is a fail too" {
  asroot "$DEB"
  run env STUB_APT_FAIL='E: broken' bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/updates-full/apply.sh"
  [ "$status" -ne 0 ]; [ "$(rstate updates-full status)" = fail ]; [[ $(rstate updates-full summary) == *"E: broken"* ]]
}

# ---- reboot-needed ----
@test "reboot-needed debian: /var/run/reboot-required -> ask with alt action (R5)" {
  asroot "$DEB"; touch "$BATS_TEST_TMPDIR/rr"; export OPS_REBOOT_REQUIRED="$BATS_TEST_TMPDIR/rr"
  runjob "$SJ/reboot-needed.sh"
  f="$OPS_ROOT_STATE/ask-reboot-needed.json"
  [ "$(jq -r .question "$f")" = "Reboot now or tonight 03:00?" ]
  [ "$(jq -r .action "$f")" = "root:reboot now" ]
  [ "$(jq -r .alt_action "$f")" = "root:reboot tonight" ]
  [ "$(jq -r .alt_label "$f")" = "Tonight 03:00" ]
  [ "$(rstate reboot-needed status)" = warn ]
}
@test "reboot-needed debian: no flag file -> ok and a stale ask is withdrawn" {
  asroot "$DEB"; export OPS_REBOOT_REQUIRED="$BATS_TEST_TMPDIR/absent"
  mkdir -p "$OPS_ROOT_STATE"; echo '{}' > "$OPS_ROOT_STATE/ask-reboot-needed.json"
  runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
}
@test "reboot-needed arch: running kernel without a modules dir -> ask with alt action" {
  asroot "$ARCH"; mkdir -p "$BATS_TEST_TMPDIR/modules/6.2.0-arch1"
  export OPS_MODULES_DIR="$BATS_TEST_TMPDIR/modules" OPS_KERNEL_RELEASE=6.1.0-arch1
  runjob "$SJ/reboot-needed.sh"
  [ "$(jq -r .alt_action "$OPS_ROOT_STATE/ask-reboot-needed.json")" = "root:reboot tonight" ]
}
@test "reboot-needed arch: running kernel still installed -> ok" {
  asroot "$ARCH"; mkdir -p "$BATS_TEST_TMPDIR/modules/6.1.0-arch1"
  export OPS_MODULES_DIR="$BATS_TEST_TMPDIR/modules" OPS_KERNEL_RELEASE=6.1.0-arch1
  runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
}
@test "reboot-needed fedora: dnf needs-restarting -r exit 1 = needed, 0 = ok" {
  asroot "$FED"; STUB_NR_RC=1 runjob "$SJ/reboot-needed.sh"
  [ -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]; grep -qx 'dnf needs-restarting -r' "$STUB_LOG"
  STUB_NR_RC=0 runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
}
@test "reboot-needed nixos -> ok n/a" {
  asroot "$NIX"; runjob "$SJ/reboot-needed.sh"
  [[ $(rstate reboot-needed summary) == n/a:* ]]
}
@test "reboot actions: now = systemctl reboot; tonight = a 03:00 transient timer running the lock-checking job, never bare shutdown (dry run)" {
  asroot "$DEB"
  run runact reboot now;     [ "$status" -eq 0 ]; [ "$output" = "+ systemctl reboot" ]
  run runact reboot tonight; [ "$status" -eq 0 ]
  [[ $output == *"+ systemd-run --no-block --collect --unit=dots-ops-reboot-scheduled --on-calendar=*-*-* 03:00:00 --setenv=PATH="*" --setenv=OPS_IS_ROOT=1 -p ExecStopPost=/usr/local/bin/dots-ops-job --report-failure reboot-scheduled /usr/local/bin/dots-ops-job reboot-scheduled"* ]]
  [[ $output != *shutdown* ]]
  [ ! -e "$OPS_ROOT_STATE/root/reboot-scheduled.json" ]   # dry run: nothing armed
}

# ---- R56: shared root package lock ----
holdlock() {   # hold the pkg lock in the background for $1 s (default 5); waits until it is really held
  mkdir -p "$OPS_ROOT_STATE/root/locks"   # exec: the holder IS the sleep, so `kill $LOCKPID` releases the lock
  ( exec 9>>"$OPS_ROOT_STATE/root/locks/pkg.lock"; flock -x 9; exec sleep "${1:-5}" ) & LOCKPID=$!
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do flock -n "$OPS_ROOT_STATE/root/locks/pkg.lock" true || return 0; sleep 0.1; done; return 1
}
lockprobe() {   # a package-manager stub that records whether the pkg lock is held while it runs
  printf '#!/bin/sh\necho "%s $*" >> "$STUB_LOG"\nflock -n "%s" true && echo FREE >> "%s" || echo HELD >> "%s"\nexit 0\n' \
    "$1" "$OPS_ROOT_STATE/root/locks/pkg.lock" "$BATS_TEST_TMPDIR/probe" "$BATS_TEST_TMPDIR/probe" > "$BATS_TEST_TMPDIR/pb/$1"
  chmod +x "$BATS_TEST_TMPDIR/pb/$1"
}
@test "R56 updates-full apply and updates-security hold the pkg lock during the package transaction, release it after" {
  asroot "$ARCH"; mkdir -p "$BATS_TEST_TMPDIR/pb"; lockprobe pacman; lockprobe unattended-upgrade
  PATH="$BATS_TEST_TMPDIR/pb:$PATH" run runact_live updates-full apply; [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/probe")" = HELD ]
  asroot "$DEB"; : > "$BATS_TEST_TMPDIR/probe"
  PATH="$BATS_TEST_TMPDIR/pb:$PATH" runjob "$SJ/updates-security.sh"
  [ "$(cat "$BATS_TEST_TMPDIR/probe")" = HELD ]
  flock -n "$OPS_ROOT_STATE/root/locks/pkg.lock" true   # released once the transaction is over
}
@test "R56 a held pkg lock: apply waits, then fails without running; updates-security skips with warn" {
  asroot "$ARCH"; holdlock 5
  OPS_PKG_LOCK_WAIT=1 run runact_live updates-full apply
  [ "$status" -ne 0 ]; ! grep -q '^pacman' "$STUB_LOG"
  [ "$(rstate updates-full status)" = fail ]; [[ $(rstate updates-full summary) == *"package transaction"* ]]
  asroot "$DEB"; OPS_PKG_LOCK_WAIT=1 runjob "$SJ/updates-security.sh"
  ! grep -q '^unattended-upgrade' "$STUB_LOG"
  [ "$(rstate updates-security status)" = warn ]; [[ $(rstate updates-security summary) == *"package transaction"* ]]
  kill "$LOCKPID" 2>/dev/null || true
}
@test "R56 reboot now refuses while a package transaction runs: warn, non-zero, ask kept, no reboot" {
  asroot "$DEB"; mkdir -p "$OPS_ROOT_STATE"; echo '{}' > "$OPS_ROOT_STATE/ask-reboot-needed.json"; holdlock 5
  run runact_live reboot now; [ "$status" -ne 0 ]
  ! grep -q 'systemctl reboot' "$STUB_LOG"
  [ "$(rstate reboot-needed status)" = warn ]; [ "$(rstate reboot-needed summary)" = "package transaction running — try again" ]
  [ -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
  kill "$LOCKPID" 2>/dev/null || true
}
@test "R56 reboot tonight arms the scheduled job (tries 0), withdraws the ask and says how to cancel" {
  asroot "$DEB"; mkdir -p "$OPS_ROOT_STATE"; echo '{}' > "$OPS_ROOT_STATE/ask-reboot-needed.json"
  run runact_live reboot tonight; [ "$status" -eq 0 ]
  grep -q '^systemd-run .*--unit=dots-ops-reboot-scheduled --on-calendar=\*-\*-\* 03:00:00 .* reboot-scheduled$' "$STUB_LOG"
  ! grep -q '^shutdown' "$STUB_LOG"
  [ "$(jq -r .tries "$OPS_ROOT_STATE/root/reboot-scheduled.json")" = 0 ]
  [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
  [[ $(rstate reboot-needed summary) == *"03:00"*"systemctl stop dots-ops-reboot-scheduled.timer"* ]]
}
@test "R56 reboot-scheduled job: not armed -> nothing; armed + lock free -> reboot; lock held -> re-arm +15 min, at most 8 times" {
  asroot "$DEB"
  runjob "$SJ/reboot-scheduled.sh"; ! grep -q 'reboot' "$STUB_LOG"   # nothing armed (e.g. the daily timer fired again)
  mkdir -p "$OPS_ROOT_STATE/root"; echo '{"tries":0}' > "$OPS_ROOT_STATE/root/reboot-scheduled.json"
  holdlock 8
  runjob "$SJ/reboot-scheduled.sh"
  ! grep -qx 'systemctl reboot' "$STUB_LOG"
  grep -q '^systemd-run .*--unit=dots-ops-reboot-scheduled-1 --on-active=15min .* reboot-scheduled$' "$STUB_LOG"
  [ "$(jq -r .tries "$OPS_ROOT_STATE/root/reboot-scheduled.json")" = 1 ]
  [[ $(rstate reboot-needed summary) == *"retry 1/8"* ]]
  echo '{"tries":8}' > "$OPS_ROOT_STATE/root/reboot-scheduled.json"; : > "$STUB_LOG"
  runjob "$SJ/reboot-scheduled.sh"
  ! grep -q 'systemd-run' "$STUB_LOG"; ! grep -qx 'systemctl reboot' "$STUB_LOG"
  [ ! -e "$OPS_ROOT_STATE/root/reboot-scheduled.json" ]
  [ "$(rstate reboot-needed status)" = warn ]; [[ $(rstate reboot-needed summary) == *"gave up"* ]]
  kill "$LOCKPID" 2>/dev/null || true; wait "$LOCKPID" 2>/dev/null || true
  echo '{"tries":3}' > "$OPS_ROOT_STATE/root/reboot-scheduled.json"; : > "$STUB_LOG"
  runjob "$SJ/reboot-scheduled.sh"
  grep -qx 'systemctl reboot' "$STUB_LOG"; [ ! -e "$OPS_ROOT_STATE/root/reboot-scheduled.json" ]
}

# ---- firmware ----
@test "firmware: fwupdmgr absent -> ok n/a" {
  asroot "$DEB"; without_cmd fwupdmgr
  runjob "$SJ/firmware.sh"
  [ "$(rstate firmware status)" = ok ]; [[ $(rstate firmware summary) == n/a:* ]]
}
@test "firmware: updates available -> ask root:firmware apply, refresh via ops_run" {
  asroot "$DEB"; export STUB_FWUPD_JSON='{"Devices":[{"Name":"BIOS","Releases":[{"Version":"2"}]},{"Name":"Dock"}]}'
  runjob "$SJ/firmware.sh"
  grep -qx 'fwupdmgr refresh --force -y' "$STUB_LOG"
  [ "$(rstate ask-firmware action)" = "root:firmware apply" ]
  [[ $(rstate ask-firmware question) == *1* ]]
  [ "$(rstate firmware status)" = warn ]
}
@test "firmware: refresh exit 2 (nothing to do) is fine; get-updates exit 2 with no devices -> ok, no ask" {
  asroot "$DEB"; export STUB_FWUPD_REFRESH_RC=2 STUB_FWUPD_GET_RC=2 STUB_FWUPD_JSON=''
  runjob "$SJ/firmware.sh"
  [ "$(rstate firmware status)" = ok ]; [ ! -e "$OPS_ROOT_STATE/ask-firmware.json" ]
}
@test "firmware: refresh hard failure -> warn, no ask" {
  asroot "$DEB"; export STUB_FWUPD_REFRESH_RC=1
  runjob "$SJ/firmware.sh"
  [ "$(rstate firmware status)" = warn ]; [ ! -e "$OPS_ROOT_STATE/ask-firmware.json" ]
}
@test "firmware apply dry-run: fwupdmgr update -y --no-reboot-check" {
  asroot "$DEB"
  run runact firmware apply; [ "$status" -eq 0 ]
  [[ $output == *"+ fwupdmgr update -y --no-reboot-check"* ]]
}
@test "firmware apply failure -> state fail, non-zero" {
  asroot "$DEB"
  run env STUB_FWUPD_FAIL=nope bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/firmware/apply.sh"
  [ "$status" -ne 0 ]; [ "$(rstate firmware status)" = fail ]
}

# ---- dots-update (user) ----
@test "dots-update is heavy, runs chezmoi update --apply --no-tty, ok on success" {
  source "$UJ/dots-update.sh"; [ "$OPS_HEAVY" = 1 ]
  job_main
  grep -qx 'chezmoi update --apply --no-tty' "$STUB_LOG"; [ "$(ustate dots-update status)" = ok ]
}
@test "dots-update: dry run prints the command" {
  DOTS_OPS_DRY_RUN=1 run bash -c "source '$LIB'; source '$UJ/dots-update.sh'; job_main"
  [ ! -s "$STUB_LOG" ]
}
@test "dots-update: failure -> fail with a chezmoi diff hint" {
  STUB_CHEZMOI_FAIL='conflict in foo' runjob "$UJ/dots-update.sh"
  [ "$(ustate dots-update status)" = fail ]
  [[ $(ustate dots-update summary) == *"chezmoi diff"* && $(ustate dots-update summary) == *"conflict in foo"* ]]
}

# ---- R5: two-button ask ----
@test "R5 ops_ask (user) stores alt_action and alt_label" {
  export OPS_ASK_UI=0
  ops_ask reboot-needed "Reboot?" "root:reboot now" "root:reboot tonight" "Tonight 03:00"
  p="$OPS_STATE/pending/reboot-needed.json"
  [ "$(jq -r .alt_action "$p")" = "root:reboot tonight" ]; [ "$(jq -r .alt_label "$p")" = "Tonight 03:00" ]
}
@test "R5 ops_ask without alt stores neither key" {
  export OPS_ASK_UI=0
  ops_ask j "q" "user:true"
  [ "$(jq 'has("alt_action") or has("alt_label")' "$OPS_STATE/pending/j.json")" = false ]
}
@test "R5 root ops_ask writes alt_label to the ask file" {
  OPS_IS_ROOT=1 ops_ask reboot-needed "q" "root:reboot now" "root:reboot tonight" "Tonight 03:00"
  [ "$(jq -r .alt_label "$OPS_ROOT_STATE/ask-reboot-needed.json")" = "Tonight 03:00" ]
}
@test "R5 ops_answer alt runs alt_action through the root dispatch and clears the pending" {
  export OPS_ASK_UI=0 OPS_SUDO="$BATS_TEST_TMPDIR/sudo" OPS_RUNNER=/fake/dots-ops-run
  printf '#!/bin/sh\necho "$*" > %s/sudo.args\n' "$BATS_TEST_TMPDIR" > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  ops_ask reboot-needed "q" "root:reboot now" "root:reboot tonight" "Tonight 03:00"
  ops_answer reboot-needed alt
  [ "$(cat "$BATS_TEST_TMPDIR/sudo.args")" = "/fake/dots-ops-run reboot tonight" ]
  [ ! -e "$OPS_STATE/pending/reboot-needed.json" ]
}
@test "R5 ops_answer alt runs a user: alt_action too; approve still runs the main action" {
  export OPS_ASK_UI=0
  ops_ask j "q" "user:touch $BATS_TEST_TMPDIR/main" "user:touch $BATS_TEST_TMPDIR/alt" "Other"
  ops_answer j alt
  [ -e "$BATS_TEST_TMPDIR/alt" ] && [ ! -e "$BATS_TEST_TMPDIR/main" ]
  ops_ask j "q" "user:touch $BATS_TEST_TMPDIR/main" "user:touch $BATS_TEST_TMPDIR/alt" "Other"
  ops_answer j approve
  [ -e "$BATS_TEST_TMPDIR/main" ]
}
@test "R5 ops_answer alt without an alt_action does nothing" {
  export OPS_ASK_UI=0
  ops_ask j "q" "user:touch $BATS_TEST_TMPDIR/main"
  run ops_answer j alt; [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/main" ]
}
@test "R5 ops_answer alt on an expired pending does not run" {
  export OPS_ASK_UI=0
  ops_ask j "q" "user:true" "user:touch $BATS_TEST_TMPDIR/alt" "Other"
  jq '.expires=1' "$OPS_STATE/pending/j.json" > t && mv t "$OPS_STATE/pending/j.json"
  run ops_answer j alt; [ ! -e "$BATS_TEST_TMPDIR/alt" ]
}
@test "R5 CLI answer accepts alt" {
  export OPS_ASK_UI=0 OPS_LIB="$LIB"
  ops_ask j "q" "user:true" "user:touch $BATS_TEST_TMPDIR/alt" "Other"
  run bash "$R/home/private_dot_local/private_bin/executable_dots-ops" answer j alt
  [ "$status" -eq 0 ]; [ -e "$BATS_TEST_TMPDIR/alt" ]
}
@test "R5 relay passes alt_action and alt_label through to the user pending" {
  export OPS_ASK_UI=0 OPS_LIB="$LIB" OPS_JOBS_DIR="$BATS_TEST_TMPDIR/userjobs"; mkdir -p "$OPS_JOBS_DIR" "$OPS_ROOT_STATE"
  jq -cn --argjson t "$(date +%s)" '{question:"Reboot now or tonight 03:00?",action:"root:reboot now",alt_action:"root:reboot tonight",alt_label:"Tonight 03:00",asked:$t}' \
    > "$OPS_ROOT_STATE/ask-reboot-needed.json"
  run bash "$R/home/private_dot_local/private_bin/executable_dots-ops" relay; [ "$status" -eq 0 ]
  p="$OPS_STATE/pending/reboot-needed.json"
  [ "$(jq -r .alt_action "$p")" = "root:reboot tonight" ]; [ "$(jq -r .alt_label "$p")" = "Tonight 03:00" ]
}
@test "R5 relay refuses a non-root alt_action" {
  export OPS_ASK_UI=0 OPS_LIB="$LIB" OPS_JOBS_DIR="$BATS_TEST_TMPDIR/userjobs"; mkdir -p "$OPS_JOBS_DIR" "$OPS_ROOT_STATE"
  jq -cn --argjson t "$(date +%s)" '{question:"q",action:"root:reboot now",alt_action:"user:touch /tmp/pwn",alt_label:"x",asked:$t}' \
    > "$OPS_ROOT_STATE/ask-reboot-needed.json"
  run bash "$R/home/private_dot_local/private_bin/executable_dots-ops" relay
  [ ! -e "$OPS_STATE/pending/reboot-needed.json" ]
}
@test "R5 dots-ops-ask adds the alt button only when the pending has alt_action, and routes the answer" {
  export OPS_ASK_UI=0 OPS_LIB="$LIB"
  mkdir -p "$HOME/.local/bin"
  # notify-send -p prints the id first (R54: kept in pending/<job>.nid while the toast is up), then the chosen action
  printf '#!/bin/sh\necho "$@" >> %s/ns.args\ncase " $* " in *" -p "*) echo 4711; sleep 0.5; cat "$OPS_STATE"/pending/*.nid > %s/nid.seen 2>/dev/null ;; esac\necho "${STUB_NS_CHOICE:-}"\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/notify-send"; chmod +x "$BATS_TEST_TMPDIR/notify-send"
  printf '#!/bin/sh\necho "answer $*" >> %s/ans.log\n' "$BATS_TEST_TMPDIR" > "$HOME/.local/bin/dots-ops"; chmod +x "$HOME/.local/bin/dots-ops"
  export PATH="$BATS_TEST_TMPDIR:$PATH"
  ASK="$R/home/private_dot_local/private_bin/executable_dots-ops-ask"
  ops_ask reboot-needed "Reboot?" "root:reboot now" "root:reboot tonight" "Tonight 03:00"
  tok=$(ops_pending_token reboot-needed)
  STUB_NS_CHOICE=alt run bash "$ASK" reboot-needed; [ "$status" -eq 0 ]
  grep -q -- '-A alt=Tonight 03:00' "$BATS_TEST_TMPDIR/ns.args"
  [ "$(cat "$BATS_TEST_TMPDIR/ans.log")" = "answer answer reboot-needed alt $tok" ]   # R54: the token of the content shown
  [ "$(cat "$BATS_TEST_TMPDIR/nid.seen")" = 4711 ]                                     # id kept while the toast was up
  [ ! -e "$OPS_STATE/pending/reboot-needed.nid" ]                                     # and dropped once it is gone
  : > "$BATS_TEST_TMPDIR/ns.args"
  ops_ask j "q" "user:true"
  STUB_NS_CHOICE=skip run bash "$ASK" j
  ! grep -q -- 'alt=' "$BATS_TEST_TMPDIR/ns.args"
}

# ---- units ----
@test "updates timers: updates-check daily + 10 min after boot; security 04:00; firmware weekly; all Persistent" {
  g() { grep -q "$2" "$SU/$1"; }
  g dots-ops-updates-check.timer '^OnCalendar=daily'; g dots-ops-updates-check.timer '^OnBootSec=10min'
  g dots-ops-updates-check.timer '^Unit=dots-ops@updates-check.service'
  g dots-ops-updates-security.timer '^OnCalendar=\*-\*-\* 04:00'; g dots-ops-updates-security.timer '^Unit=dots-ops@updates-security.service'
  g dots-ops-firmware.timer '^OnCalendar=weekly'; g dots-ops-firmware.timer '^Unit=dots-ops@firmware.service'
  for t in updates-check updates-security firmware; do g dots-ops-$t.timer '^Persistent=true'; g dots-ops-$t.timer 'WantedBy=timers.target'; done
}
@test "updates-security is wanted by the system idle target" {
  grep -q '^Wants=.*dots-ops@updates-security.service' "$SU/dots-ops-system-idle.target"
  grep -q 'dots-ops@disk-clean-system.service' "$SU/dots-ops-system-idle.target"
}
@test "reboot path unit triggers reboot-needed on /run/reboot-required (R63: not the legacy /var/run)" {
  f="$SU/dots-ops-reboot.path"
  grep -qx 'PathChanged=/run/reboot-required' "$f"
  grep -q '^Unit=dots-ops@reboot-needed.service' "$f"; grep -q 'WantedBy=paths.target\|WantedBy=multi-user.target' "$f"
  grep -q 'OPS_REBOOT_REQUIRED:-/run/reboot-required}' "$SJ/reboot-needed.sh"
}
@test "dots-update user timer: daily, persistent, enabled by the systemd script" {
  f="$R/home/private_dot_config/systemd/private_user/dots-ops-dots-update.timer"
  grep -q '^OnCalendar=daily' "$f"; grep -q '^Persistent=true' "$f"; grep -q '^Unit=dots-ops@dots-update.service' "$f"
  grep -q 'enable --now dots-ops-dots-update.timer' "$R/home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl"
}
@test "R59 dots-update and backup-check are pulled by the idle target" {
  t="$R/home/private_dot_config/systemd/private_user/dots-ops-idle.target.tmpl"
  grep -q '^Wants=.*dots-ops@dots-update.service' "$t"; grep -q '^Wants=.*dots-ops@backup-check.service' "$t"
  grep -q '^Wants=.*dots-ops@backup.service' "$t"
}
@test "R59 dots-update: ran within 1 day -> skipped unless forced; a real run records when" {
  runjob "$UJ/dots-update.sh"; grep -q 'chezmoi update' "$STUB_LOG"
  [ -s "$OPS_STATE/dots-update.last" ]
  : > "$STUB_LOG"; runjob "$UJ/dots-update.sh"
  ! grep -q chezmoi "$STUB_LOG"; grep -q 'skipped: last run' "$OPS_STATE/log.jsonl"
  OPS_FORCE=1 runjob "$UJ/dots-update.sh"; grep -q 'chezmoi update' "$STUB_LOG"
  echo $(( $(date +%s) - 86401 )) > "$OPS_STATE/dots-update.last"; : > "$STUB_LOG"
  runjob "$UJ/dots-update.sh"; grep -q 'chezmoi update' "$STUB_LOG"
  rm -f "$OPS_STATE/dots-update.last"; DOTS_OPS_DRY_RUN=1 run runjob "$UJ/dots-update.sh"; [ ! -e "$OPS_STATE/dots-update.last" ]
}
@test "units verify (systemd-analyze, temp copies)" {
  command -v systemd-analyze >/dev/null || skip "no systemd-analyze"
  d="$BATS_TEST_TMPDIR/units"; mkdir -p "$d"
  cp "$SU"/dots-ops-updates-check.timer "$SU"/dots-ops-updates-security.timer "$SU"/dots-ops-firmware.timer "$SU"/dots-ops-reboot.path "$d/"
  cp "$R/home/private_dot_config/systemd/private_user/dots-ops-dots-update.timer" "$d/"
  # the triggered service template lives next to them so verify can resolve Unit=
  cp "$SU/dots-ops@.service" "$d/"
  for s in updates-check updates-security firmware reboot-needed dots-update; do cp "$SU/dots-ops@.service" "$d/dots-ops@$s.service"; done
  sed -i 's#^ExecStart=.*#ExecStart=/bin/true#' "$d"/dots-ops@*.service
  run systemd-analyze verify "$d"/dots-ops-updates-check.timer "$d"/dots-ops-updates-security.timer "$d"/dots-ops-firmware.timer \
    "$d"/dots-ops-reboot.path "$d"/dots-ops-dots-update.timer
  [[ $output != *"dots-ops-"*"Failed"* ]] && [[ $output != *"Invalid"* ]]
}

# ---- root layer packages ----
render_pkgs() {   # render_pkgs <osRelease id> [idLike]: DOTS_PKG_LIST output of the rendered root script
  local out="$BATS_TEST_TMPDIR/root-system.sh"
  local real; real=$(PATH="$ORIG_PATH"; unset -f chezmoi; for d in ${ORIG_PATH//:/ }; do [ "$d" = "$BATS_TEST_DIRNAME/stubs" ] || { [ -x "$d/chezmoi" ] && { echo "$d/chezmoi"; break; }; }; done)
  [ -n "$real" ] || skip "no chezmoi"   # the stub chezmoi shadows the real one on PATH
  "$real" execute-template --override-data "{\"gpu\":\"mesa\",\"multiplexer\":\"tmux\",\"chezmoi\":{\"homeDir\":\"/h\",\"workingTree\":\"/w\",\"osRelease\":{\"id\":\"$1\",\"idLike\":\"${2:-}\"}}}" \
    < "$R/home/.chezmoiscripts/run_once_before_00-system.sh.tmpl" > "$out" 2> "$BATS_TEST_TMPDIR/err" || { cat "$BATS_TEST_TMPDIR/err" >&2; return 1; }
  bash -n "$out"
  DOTS_PKG_LIST=1 bash "$out"
}
@test "root layer packages: unattended-upgrades (debian), dnf-plugins-core (fedora), pacman-contrib (arch), fwupd everywhere" {
  run render_pkgs ubuntu debian; [ "$status" -eq 0 ]; [[ $output == *unattended-upgrades* && $output == *fwupd* ]]
  run render_pkgs fedora;        [ "$status" -eq 0 ]; [[ $output == *dnf-plugins-core* && $output == *fwupd* ]]
  run render_pkgs arch;          [ "$status" -eq 0 ]; [[ $output == *pacman-contrib* && $output == *fwupd* ]]
}

# ---- fix round 1: R34-R37 and minors ----
runact_live() { bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/$1/$2.sh"; }   # stubs on PATH, not dry run
RN='systemctl start --no-block dots-ops@reboot-needed.service'
@test "R35 updates-check re-evaluates the reboot state at the end, every family, also with 0 updates" {
  asroot "$DEB"; STUB_APT_INST='Inst curl [1] (2 u)\n' runjob "$SJ/updates-check.sh"; grep -qx "$RN" "$STUB_LOG"
  : > "$STUB_LOG"; STUB_APT_INST='' runjob "$SJ/updates-check.sh"; grep -qx "$RN" "$STUB_LOG"
  : > "$STUB_LOG"; asroot "$ARCH"; STUB_CHECKUPDATES='' runjob "$SJ/updates-check.sh"; grep -qx "$RN" "$STUB_LOG"
  : > "$STUB_LOG"; asroot "$FED"; STUB_DNF_RC=0 runjob "$SJ/updates-check.sh"; grep -qx "$RN" "$STUB_LOG"
  : > "$STUB_LOG"; asroot "$NIX"; runjob "$SJ/updates-check.sh"; grep -qx "$RN" "$STUB_LOG"
}
@test "R35 updates-security starts the reboot check after success only" {
  asroot "$DEB"; runjob "$SJ/updates-security.sh"; grep -qx "$RN" "$STUB_LOG"
  : > "$STUB_LOG"; STUB_UU_FAIL=boom runjob "$SJ/updates-security.sh"; ! grep -q reboot-needed "$STUB_LOG"
}
@test "R35 reboot-needed clears a stale warn and its ask once nothing is needed (after a reboot)" {
  asroot "$DEB"; touch "$BATS_TEST_TMPDIR/rr"; export OPS_REBOOT_REQUIRED="$BATS_TEST_TMPDIR/rr"
  runjob "$SJ/reboot-needed.sh"; [ "$(rstate reboot-needed status)" = warn ]
  rm -f "$BATS_TEST_TMPDIR/rr"
  runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [ "$(rstate reboot-needed summary)" = "no reboot needed" ]
  [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
}
@test "R35 fedora: dnf missing or an error rc is ok n/a, never a reboot ask" {
  asroot "$FED"; STUB_NR_RC=2 runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [[ $(rstate reboot-needed summary) == n/a:* ]]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
  STUB_NR_RC=127 runjob "$SJ/reboot-needed.sh"
  [[ $(rstate reboot-needed summary) == n/a:* ]]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
  without_cmd dnf; runjob "$SJ/reboot-needed.sh"
  [ "$(rstate reboot-needed status)" = ok ]; [[ $(rstate reboot-needed summary) == n/a:* ]]; [ ! -e "$OPS_ROOT_STATE/ask-reboot-needed.json" ]
}
@test "debian apply options: confold + confdef + lock timeout" {
  asroot "$DEB"; run runact updates-full apply
  [[ $output == *"-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -o DPkg::Lock::Timeout=300"* ]]
}
@test "debian updates-check: a failing apt-get -s dist-upgrade warns with its last line and keeps the ask" {
  asroot "$DEB"; mkdir -p "$OPS_ROOT_STATE"; echo '{"question":"old"}' > "$OPS_ROOT_STATE/ask-updates-full.json"
  printf '#!/bin/sh\ncase " $* " in *" -s "*) echo "E: dpkg was interrupted"; exit 100 ;; esac\nexit 0\n' > "$BATS_TEST_TMPDIR/apt-get"; chmod +x "$BATS_TEST_TMPDIR/apt-get"
  PATH="$BATS_TEST_TMPDIR:$PATH" runjob "$SJ/updates-check.sh"
  [ "$(rstate updates-check status)" = warn ]; [[ $(rstate updates-check summary) == *"E: dpkg was interrupted"* ]]
  [ "$(jq -r .question "$OPS_ROOT_STATE/ask-updates-full.json")" = old ]
}
@test "reboot actions keep the ask file when the command fails, remove it on success" {
  asroot "$DEB"; mkdir -p "$OPS_ROOT_STATE"; a="$OPS_ROOT_STATE/ask-reboot-needed.json"
  echo '{}' > "$a"; run env STUB_SYSTEMCTL_FAIL=1 bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/reboot/now.sh"
  [ "$status" -ne 0 ]; [ -e "$a" ]
  run runact_live reboot now; [ "$status" -eq 0 ]; [ ! -e "$a" ]; grep -qx 'systemctl reboot' "$STUB_LOG"
  echo '{}' > "$a"; run env STUB_SYSTEMRUN_FAIL=1 bash -c 'set -euo pipefail; source "$1"; source "$2"' _ "$LIB" "$SA/reboot/tonight.sh"
  [ "$status" -ne 0 ]; [ -e "$a" ]; [ ! -e "$OPS_ROOT_STATE/root/reboot-scheduled.json" ]   # timer not created: nothing armed
  run runact_live reboot tonight; [ "$status" -eq 0 ]; [ ! -e "$a" ]; grep -q '^systemd-run .*--on-calendar' "$STUB_LOG"
}
@test "R36 ops_ask launches the UI through systemd-run --user, not setsid; failure does not fail ops_ask; OPS_ASK_UI=0 skips" {
  export OPS_ASK_UI=1
  ops_ask j "q" "user:true"
  grep -qx "systemd-run --user --no-block --collect $HOME/.local/bin/dots-ops-ask j" "$STUB_LOG"
  rm -f "$OPS_STATE/pending/j.json"; : > "$STUB_LOG"
  STUB_SYSTEMRUN_FAIL=1 run ops_ask j "q" "user:true"; [ "$status" -eq 0 ]; [ -e "$OPS_STATE/pending/j.json" ]
  rm -f "$OPS_STATE/pending/j.json"; : > "$STUB_LOG"; OPS_ASK_UI=0 ops_ask j "q" "user:true"
  ! grep -q systemd-run "$STUB_LOG"
  ! grep -q setsid "$LIB"
}
@test "R37 user job unit allows 2h" {
  grep -qx 'TimeoutStartSec=2h' "$R/home/private_dot_config/systemd/private_user/dots-ops@.service"
}
@test "R63 config.toml has no root-job knobs (root ignores the user config, R18)" {
  c="$R/home/private_dot_config/dots-ops/config.toml"
  run ! grep -q 'updates-security' "$c"
  for j in "$SJ"/*.sh; do n=$(basename "$j" .sh); run ! grep -qF "[jobs.$n]" "$c"; done
}
