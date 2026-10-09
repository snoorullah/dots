load helpers
bats_require_minimum_version 1.5.0
# Disk domain: disk-watch, disk-clean-user, disk-clean-system, smart, trim, containers-prune/volumes, ops_family.
# Every command that could mutate is a stub on PATH (tests/ops/stubs) or runs under DOTS_OPS_DRY_RUN=1.
R="$BATS_TEST_DIRNAME/../.."
UJ="$R/home/private_dot_local/lib/dots-ops/jobs"
SJ="$R/system/dots-ops/jobs"

setup() {
  setup_ops
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export OPS_SUDO="$BATS_TEST_TMPDIR/sudo" OPS_RUNNER=/fake/dots-ops-run
  printf '#!/bin/sh\necho "sudo $*" >> "%s"\n' "$STUB_LOG" > "$OPS_SUDO"; chmod +x "$OPS_SUDO"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ops_cfg() { echo "$2"; }   # the runner provides ops_cfg; tests use the defaults
}
runjob() { source "$1"; job_main; }   # runjob <file>: defines and runs job_main in this shell
ustate() { jq -r ".$2" "$OPS_STATE/state/$1.json"; }
rstate() { jq -r ".$2" "$OPS_ROOT_STATE/$1.json"; }
asroot() {   # root-job context: state in $OPS_ROOT_STATE, os-release from $1
  export OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/root" OPS_STATE="$BATS_TEST_TMPDIR/rootlog"
  mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks"
  printf '%b' "$1" > "$BATS_TEST_TMPDIR/os"; export OPS_OS_RELEASE="$BATS_TEST_TMPDIR/os"
}

# ---- ops_family ----
@test "ops_family maps os-release ID / ID_LIKE" {
  f="$BATS_TEST_TMPDIR/os"
  chk() { printf '%b' "$1" > "$f"; OPS_OS_RELEASE=$f run ops_family; [ "$status" -eq 0 ]; [ "$output" = "$2" ]; }
  chk 'ID=arch\n' arch
  chk 'ID=endeavouros\nID_LIKE=arch\n' arch
  chk 'ID=ubuntu\nID_LIKE=debian\n' debian
  chk 'ID=debian\n' debian
  chk 'ID=fedora\n' fedora
  chk 'ID=rocky\nID_LIKE="rhel centos fedora"\n' fedora
  chk 'ID=nixos\n' nixos
  chk 'ID="alpine"\n' unknown
  OPS_OS_RELEASE="$BATS_TEST_TMPDIR/missing" run ops_family; [ "$output" = unknown ]
}

# ---- disk-watch ----  (STUB_FINDMNT lines: FSTYPE SIZE USE% TARGET OPTS)
dw() { STUB_FINDMNT="$1" runjob "$UJ/disk-watch.sh"; }
@test "disk-watch: healthy mounts -> ok, nothing started" {
  dw 'ext4 500000000000 10% / rw\nxfs 500000000000 50% /data rw\n'
  [ "$(ustate disk-watch status)" = ok ]
  ! grep -q 'disk-clean-user' "$STUB_LOG"
  ! grep -q 'run-now' "$STUB_LOG"
  grep -q 'findmnt -rn -b -O rw' "$STUB_LOG"
}
@test "disk-watch: rw ext4 at 91% -> warn naming only that mount, starts both cleaners with OPS_FORCE" {
  dw 'ext4 500000000000 91% / rw\nxfs 500000000000 50% /data rw\n'
  [ "$(ustate disk-watch status)" = warn ]
  [[ $(ustate disk-watch summary) == *"/ 91%"* ]]
  [[ $(ustate disk-watch summary) != *"/data"* ]]
  grep -qxF "systemd-run --user --no-block --collect --setenv=OPS_FORCE=1 -p ExecStopPost=$HOME/.local/bin/dots-ops-job --report-failure disk-clean-user $HOME/.local/bin/dots-ops-job disk-clean-user" "$STUB_LOG"
  grep -q 'sudo /fake/dots-ops-run disk-clean-system run-now' "$STUB_LOG"
}
@test "disk-watch: 96% -> fail" {
  dw 'ext4 500000000000 96% / rw\n'
  [ "$(ustate disk-watch status)" = fail ]
  [[ $(ustate disk-watch summary) == *"/ 96%"* ]]
}
@test "disk-watch: 100% iso9660, 99% 300 MiB vfat, 100% ro ext4, tmpfs/fuse -> ok (no false alarms)" {
  dw 'iso9660 8000000000 100% /run/media/u/DISC rw\nvfat 314572800 99% /boot rw\next4 500000000000 100% /mnt/ro ro\ntmpfs 8000000000 100% /run rw\nfuse.portal 9000000000 100% /run/doc rw\nefivarfs 9000000000 100% /sys/efi rw\n'
  [ "$(ustate disk-watch status)" = ok ]
  ! grep -q 'disk-clean' "$STUB_LOG"
}
@test "disk-watch: mount points with spaces (findmnt \\x20) are kept whole" {
  dw 'ext4 500000000000 90% /mnt/my\\x20disk rw\n'
  [[ $(ustate disk-watch summary) == *"/mnt/my disk 90%"* ]]
}
@test "disk-watch: refused sudo does not crash, user cleaner still started, still warn" {
  printf '#!/bin/sh\nexit 1\n' > "$OPS_SUDO"
  STUB_FINDMNT='ext4 500000000000 90% / rw\n' run runjob "$UJ/disk-watch.sh"
  [ "$status" -eq 0 ]
  [ "$(ustate disk-watch status)" = warn ]
  grep -q 'disk-clean-user' "$STUB_LOG"
  grep -q 'sudo' "$OPS_STATE/log.jsonl"
}
@test "disk-watch: dry-run prints instead of starting" {
  STUB_FINDMNT='ext4 500000000000 90% / rw\n' DOTS_OPS_DRY_RUN=1 run runjob "$UJ/disk-watch.sh"
  [[ $output == *"+ systemd-run --user --no-block --collect --setenv=OPS_FORCE=1 -p ExecStopPost=$HOME/.local/bin/dots-ops-job --report-failure disk-clean-user $HOME/.local/bin/dots-ops-job disk-clean-user"* ]]
  ! grep -q systemd-run "$STUB_LOG"
}
@test "R63 disk-watch: forced cleaners start at most every 6 h (backoff in OPS_STATE); still warn meanwhile" {
  dw 'ext4 500000000000 91% / rw\n'
  [ "$(grep -c 'disk-clean-user' "$STUB_LOG")" -eq 1 ]; [ "$(grep -c 'run-now' "$STUB_LOG")" -eq 1 ]
  [ -s "$OPS_STATE/disk-watch.forced" ]
  dw 'ext4 500000000000 92% / rw\n'
  [ "$(ustate disk-watch status)" = warn ]
  [ "$(grep -c 'disk-clean-user' "$STUB_LOG")" -eq 1 ]; [ "$(grep -c 'run-now' "$STUB_LOG")" -eq 1 ]
  grep -q 'cleaners started' "$OPS_STATE/log.jsonl"
  echo $(( $(date +%s) - 6 * 3600 - 1 )) > "$OPS_STATE/disk-watch.forced"
  dw 'ext4 500000000000 92% / rw\n'
  [ "$(grep -c 'disk-clean-user' "$STUB_LOG")" -eq 2 ]; [ "$(grep -c 'run-now' "$STUB_LOG")" -eq 2 ]
}

# ---- disk-clean-user ----
@test "disk-clean-user: deletes only >30d cache files, reports freed MB" {
  for d in pip uv npm yarn go-build thumbnails; do mkdir -p "$HOME/.cache/$d"; done
  head -c 3145728 /dev/zero > "$HOME/.cache/pip/old.bin"; touch -d '60 days ago' "$HOME/.cache/pip/old.bin"
  head -c 1024 /dev/zero > "$HOME/.cache/pip/new.bin"
  mkdir -p "$HOME/.cache/other"; head -c 1024 /dev/zero > "$HOME/.cache/other/o"; touch -d '90 days ago' "$HOME/.cache/other/o"
  runjob "$UJ/disk-clean-user.sh"
  [ ! -e "$HOME/.cache/pip/old.bin" ]
  [ -e "$HOME/.cache/pip/new.bin" ]
  [ -e "$HOME/.cache/other/o" ]
  [ "$(ustate disk-clean-user status)" = ok ]
  [[ $(ustate disk-clean-user summary) =~ ^freed\ ([0-9]+)\ MB$ ]]
  [ "${BASH_REMATCH[1]}" -ge 2 ]
  grep -q 'nix-collect-garbage --delete-older-than 14d' "$STUB_LOG"
}
@test "disk-clean-user: is heavy, dry-run deletes nothing" {
  mkdir -p "$HOME/.cache/pip"; touch -d '60 days ago' "$HOME/.cache/pip/old"
  source "$UJ/disk-clean-user.sh"; [ "$OPS_HEAVY" = 1 ]
  DOTS_OPS_DRY_RUN=1 run job_main
  [ -e "$HOME/.cache/pip/old" ]
  [[ $output == *"+ nix-collect-garbage --delete-older-than 14d"* ]]
  [[ $output == *"+ find $HOME/.cache/pip"* ]]
}
@test "disk-clean-user: no nix-collect-garbage on PATH is fine" {
  mkdir -p "$BATS_TEST_TMPDIR/nonix"
  for c in jq du find date stat mkdir cat grep tr sed awk head mv pkill flock; do
    p=$(command -v $c) && ln -sf "$p" "$BATS_TEST_TMPDIR/nonix/$c"
  done
  PATH="$BATS_TEST_TMPDIR/nonix" run runjob "$UJ/disk-clean-user.sh"
  [ "$status" -eq 0 ]; [ "$(ustate disk-clean-user status)" = ok ]
}

# ---- disk-clean-system ----
@test "disk-clean-system: dry-run shows journal vacuum and the debian cache clean" {
  asroot 'ID=ubuntu\nID_LIKE=debian\n'
  source "$SJ/disk-clean-system.sh"; [ "$OPS_HEAVY" = 1 ]
  DOTS_OPS_DRY_RUN=1 run job_main
  [[ $output == *"+ journalctl --vacuum-time=2weeks"* ]]
  [[ $output == *"+ apt-get clean"* ]]
  [[ $output != *"dnf"* && $output != *"paccache"* ]]
  [ ! -s "$STUB_LOG" ]
}
@test "disk-clean-system: fedora uses dnf; arch uses paccache only if present" {
  export DOTS_OPS_DRY_RUN=1
  asroot 'ID=fedora\n'; source "$SJ/disk-clean-system.sh"
  run job_main; [[ $output == *"+ dnf clean packages"* ]]
  asroot 'ID=arch\n'
  if ! command -v paccache >/dev/null; then run job_main; [[ $output != *paccache* ]]; fi
  mkdir -p "$BATS_TEST_TMPDIR/pc"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/pc/paccache"; chmod +x "$BATS_TEST_TMPDIR/pc/paccache"
  PATH="$BATS_TEST_TMPDIR/pc:$PATH" run job_main; [[ $output == *"+ paccache -rk2"* ]]
}
@test "disk-clean-system: nixos has no package-cache clean, ends ok" {
  asroot 'ID=nixos\n'
  runjob "$SJ/disk-clean-system.sh"
  [ "$(rstate disk-clean-system status)" = ok ]
  grep -q 'journalctl --vacuum-time=2weeks' "$STUB_LOG"
  ! grep -qE 'apt-get|dnf|paccache' "$STUB_LOG"
}
@test "disk-clean-system: /nix present -> nix-collect-garbage" {
  [ -d /nix ] || skip "no /nix on this host"
  asroot 'ID=arch\n'
  runjob "$SJ/disk-clean-system.sh"
  grep -q 'nix-collect-garbage --delete-older-than 14d' "$STUB_LOG"
}

# ---- smart ----
smartdisk() { mkdir -p "$BATS_TEST_TMPDIR/smart"; printf '%s' "$2" > "$BATS_TEST_TMPDIR/smart/$1.json"; }
sm() { asroot 'ID=arch\n'; export STUB_SMART_DIR="$BATS_TEST_TMPDIR/smart"; }
ATA_OK='{"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"name":"Reallocated_Sector_Ct","raw":{"value":0}}]}}'
@test "smart: no capable disks -> ok n/a" {
  sm; STUB_LSBLK='sda disk\nsr0 rom\nloop0 loop\n' STUB_SMART_NOCAP=sda runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = ok ]
  [ "$(rstate smart summary)" = "n/a: no SMART-capable disks" ]
}
@test "smart: no disks at all -> ok n/a" {
  sm; STUB_LSBLK='' runjob "$SJ/smart.sh"
  [ "$(rstate smart summary)" = "n/a: no SMART-capable disks" ]
}
@test "smart: healthy disk -> ok and counters stored, only sd?/nvme?n? scanned" {
  sm; smartdisk sda "$ATA_OK"
  STUB_LSBLK='sda disk\nzram0 disk\nsr0 rom\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = ok ]
  [ "$(jq -r .reallocated "$OPS_ROOT_STATE/root/smart-sda.json")" = 0 ]
  ! grep -q zram "$STUB_LOG"
}
@test "smart: failing health -> fail even when smartctl exits nonzero" {
  sm; smartdisk sda '{"smart_status":{"passed":false},"ata_smart_attributes":{"table":[]}}'
  STUB_LSBLK='sda disk\n' STUB_SMART_RC=8 runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]
  [[ $(rstate smart summary) == *sda* ]]
}
@test "smart: reallocated sectors increased vs last run -> fail" {
  sm; smartdisk sda '{"smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"name":"Reallocated_Sector_Ct","raw":{"value":8}}]}}'
  mkdir -p "$OPS_ROOT_STATE/root"; echo '{"reallocated":2,"media_errors":0}' > "$OPS_ROOT_STATE/root/smart-sda.json"
  STUB_LSBLK='sda disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]
  [[ $(rstate smart summary) == *"sda"*"reallocated"* ]]
  [ "$(jq -r .reallocated "$OPS_ROOT_STATE/root/smart-sda.json")" = 8 ]
}
@test "smart: nvme media_errors increased -> fail; unchanged after the 7-day window -> ok" {
  sm; smartdisk nvme0n1 '{"smart_status":{"passed":true},"nvme_smart_health_information_log":{"media_errors":3}}'
  mkdir -p "$OPS_ROOT_STATE/root"; echo '{"reallocated":0,"media_errors":1}' > "$OPS_ROOT_STATE/root/smart-nvme0n1.json"
  STUB_LSBLK='nvme0n1 disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]; [[ $(rstate smart summary) == *media_errors* ]]
  jq '.fail_until=1' "$OPS_ROOT_STATE/root/smart-nvme0n1.json" > "$BATS_TEST_TMPDIR/x" && mv "$BATS_TEST_TMPDIR/x" "$OPS_ROOT_STATE/root/smart-nvme0n1.json"
  STUB_LSBLK='nvme0n1 disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = ok ]
}

@test "smart: attribute id 5 counts even with a different name; no smart_status -> skipped as not capable" {
  sm; smartdisk sda '{"serial_number":"S/N 1","smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":5,"name":"Retired_Block_Count","raw":{"value":9}}]}}'
  smartdisk sdb '{"model_name":"usb bridge"}'
  mkdir -p "$OPS_ROOT_STATE/root"; echo '{"reallocated":1,"media_errors":0}' > "$OPS_ROOT_STATE/root/smart-S_N_1.json"
  STUB_LSBLK='sda disk\nsdb disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]; [[ $(rstate smart summary) == *"sda reallocated 1->9"* ]]
  [[ $(rstate smart summary) != *sdb* ]]
  [ ! -e "$OPS_ROOT_STATE/root/smart-sdb.json" ]
  sm; STUB_LSBLK='sdb disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart summary)" = "n/a: no SMART-capable disks" ]
}
@test "smart: counters keyed by serial survive a kernel-name change" {
  sm; smartdisk sda '{"serial_number":"ABC-123","smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":4}}]}}'
  STUB_LSBLK='sda disk\n' runjob "$SJ/smart.sh"
  [ -e "$OPS_ROOT_STATE/root/smart-ABC-123.json" ]
  smartdisk sdb '{"serial_number":"ABC-123","smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":6}}]}}'
  STUB_LSBLK='sdb disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]; [[ $(rstate smart summary) == *"sdb reallocated 4->6"* ]]
}
@test "smart: an increase keeps failing for 7 days (fail_until), then recovers" {
  sm; smartdisk sda '{"serial_number":"Z1","smart_status":{"passed":true},"ata_smart_attributes":{"table":[{"id":5,"name":"Reallocated_Sector_Ct","raw":{"value":8}}]}}'
  mkdir -p "$OPS_ROOT_STATE/root"; echo '{"reallocated":2,"media_errors":0}' > "$OPS_ROOT_STATE/root/smart-Z1.json"
  STUB_LSBLK='sda disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = fail ]
  fu=$(jq -r .fail_until "$OPS_ROOT_STATE/root/smart-Z1.json"); now=$(date +%s)
  [ "$fu" -gt $((now + 600000)) ] && [ "$fu" -le $((now + 604800 + 5)) ]
  STUB_LSBLK='sda disk\n' runjob "$SJ/smart.sh"   # counters now unchanged, still failing
  [ "$(rstate smart status)" = fail ]; [[ $(rstate smart summary) == *"recently"* ]]
  echo '{"reallocated":8,"media_errors":0,"fail_until":1}' > "$OPS_ROOT_STATE/root/smart-Z1.json"   # window elapsed
  STUB_LSBLK='sda disk\n' runjob "$SJ/smart.sh"
  [ "$(rstate smart status)" = ok ]
}

# ---- trim ----
@test "trim: fstrim.timer already enabled -> ok, no change" {
  asroot 'ID=arch\n'; STUB_FSTRIM_ENABLED=1 runjob "$SJ/trim.sh"
  [ "$(rstate trim status)" = ok ]
  ! grep -qE 'enable --now|fstrim -' "$STUB_LOG"
}
@test "trim: timer present but disabled -> enabled via ops_run (dry-run prints)" {
  asroot 'ID=arch\n'; export STUB_FSTRIM_UNIT=1
  DOTS_OPS_DRY_RUN=1 run runjob "$SJ/trim.sh"
  [[ $output == *"+ systemctl enable --now fstrim.timer"* ]]
  ! grep -q 'systemctl enable' "$STUB_LOG"
  runjob "$SJ/trim.sh"
  grep -q 'systemctl enable --now fstrim.timer' "$STUB_LOG"
  [ "$(rstate trim status)" = ok ]
}
@test "trim: no fstrim.timer unit at all -> fstrim -av" {
  asroot 'ID=arch\n'; runjob "$SJ/trim.sh"
  grep -q 'fstrim -av' "$STUB_LOG"
  [ "$(rstate trim status)" = ok ]
}

@test "trim: fstrim -av failing because discard is unsupported -> ok n/a; other failures warn" {
  asroot 'ID=arch\n'
  STUB_FSTRIM_ERR='fstrim: /: the discard operation is not supported' runjob "$SJ/trim.sh"
  [ "$(rstate trim status)" = ok ]; [ "$(rstate trim summary)" = "n/a: discard unsupported" ]
  STUB_FSTRIM_ERR='fstrim: /: FITRIM ioctl failed: Input/output error' runjob "$SJ/trim.sh"
  [ "$(rstate trim status)" = warn ]
}

# ---- containers-prune/volumes action ----
@test "containers-prune volumes: survives set -euo pipefail when docker prints no reclaimed line" {
  run env STUB_DOCKER_OUT='nothing to do\n' bash -c "set -euo pipefail; source $R/home/private_dot_local/lib/dots-ops/lib.sh; source $R/system/dots-ops/actions/containers-prune/volumes.sh; echo reached"
  [ "$status" -eq 0 ]; [[ $output == *reached* ]]
  [ "$(jq -r .summary "$OPS_STATE/state/containers-prune-volumes.json")" = "volumes pruned" ]   # R55: <job>-<action>
}
@test "containers-prune volumes: prunes with --volumes and records the reclaimed line" {
  source "$R/system/dots-ops/actions/containers-prune/volumes.sh"
  grep -q 'docker system prune --volumes -f' "$STUB_LOG"
  [ "$(ustate containers-prune-volumes status)" = ok ]
  [[ $(ustate containers-prune-volumes summary) == *"Total reclaimed space: 1.5GB"* ]]
  [ ! -e "$OPS_STATE/state/containers-prune.json" ]
}
@test "containers-prune volumes: dry-run does not call docker" {
  export DOTS_OPS_DRY_RUN=1
  run bash -c "source $R/home/private_dot_local/lib/dots-ops/lib.sh; source $R/system/dots-ops/actions/containers-prune/volumes.sh"
  [[ $output == *"+ docker system prune --volumes -f"* ]]
  ! grep -q docker "$STUB_LOG"
}

# ---- units ----
@test "timers: schedules, Persistent, and unit wiring" {
  U="$R/home/private_dot_config/systemd/private_user"; S="$R/system/dots-ops/units"
  grep -q '^OnCalendar=hourly' "$U/dots-ops-disk-watch.timer"
  grep -q '^Unit=dots-ops@disk-watch.service' "$U/dots-ops-disk-watch.timer"
  grep -q '^OnCalendar=daily' "$S/dots-ops-smart.timer"
  grep -q '^OnCalendar=weekly' "$S/dots-ops-trim.timer"
  grep -q '^OnCalendar=\*-\*-\* 03:40' "$S/dots-ops-disk-clean-system.timer"
  for t in "$U/dots-ops-disk-watch.timer" "$S/dots-ops-smart.timer" "$S/dots-ops-trim.timer" "$S/dots-ops-disk-clean-system.timer"; do
    grep -q '^Persistent=true' "$t"; grep -q '^WantedBy=timers.target' "$t"
  done
  grep -q 'dots-ops@disk-clean-system.service' "$S/dots-ops-system-idle.target"
  grep -q 'dots-ops-disk-watch.timer' "$R/home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl"
}

@test "org: disk-watch at 91% warns, starts disk-clean-user, makes no root call" {
  export OPS_ROOT_ENABLED=0
  dw 'ext4 500000000000 91% / rw\n'
  [ "$(ustate disk-watch status)" = warn ]
  grep -q 'disk-clean-user' "$STUB_LOG"
  ! grep -q 'sudo' "$STUB_LOG"
  ! grep -q 'run-now' "$STUB_LOG"
}
