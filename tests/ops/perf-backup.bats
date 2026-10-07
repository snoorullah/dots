load helpers
bats_require_minimum_version 1.5.0
# Performance modes (power-profile root job, `dots-ops perf-mode`, udev rule) and restic backups (backup, backup-watch, backup-check).
# restic, powerprofilesctl, swaync-client are stubs in $BIN (first on PATH); the real ones are never run. HOME is a temp dir.
R="$BATS_TEST_DIRNAME/../.."
UJ="$R/home/private_dot_local/lib/dots-ops/jobs"
SJ="$R/system/dots-ops/jobs"
CLI="$R/home/private_dot_local/private_bin/executable_dots-ops"

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }

setup() {
  setup_ops
  export BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export PATH="$BIN:$PATH"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export OPS_POWER_DIR="$BATS_TEST_TMPDIR/ps"; mkdir -p "$OPS_POWER_DIR"
  export OPS_LIB="$R/home/private_dot_local/lib/dots-ops/lib.sh"
  unset RESTIC_REPOSITORY RESTIC_PASSWORD RESTIC_PASSWORD_FILE DOTS_OPS_DRY_RUN
  ops_cfg() { case $1 in backup.keep_daily) echo 7 ;; backup.keep_weekly) echo 4 ;; backup.keep_monthly) echo 6 ;; backup.max_age_hours) echo 48 ;; *) echo "$2" ;; esac; }
  mkstub powerprofilesctl 'echo "powerprofilesctl $*" >> "$STUB_LOG"'
  mkstub swaync-client 'echo "swaync-client $*" >> "$STUB_LOG"'
  mkstub chezmoi 'echo "chezmoi $*" >> "$STUB_LOG"; [ "$1" = source-path ] && echo "${STUB_SOURCE_PATH:-$HOME/dots}"; exit 0'
  # restic stub: records args; STUB_RESTIC_RC/STUB_RESTIC_ERR fail every call; STUB_SNAP_JSON answers `snapshots`
  mkstub restic 'echo "restic $*" >> "$STUB_LOG"
if [ -n "${STUB_RESTIC_RC:-}" ]; then printf "%b\n" "${STUB_RESTIC_ERR:-boom}" >&2; exit "$STUB_RESTIC_RC"; fi
case $1 in
  backup) echo "{\"message_type\":\"status\",\"percent_done\":0.5}"
          echo "{\"message_type\":\"summary\",\"snapshot_id\":\"abcdef0123456789\",\"data_added\":5242880}" ;;
  snapshots) printf "%s\n" "${STUB_SNAP_JSON:-[]}" ;;
esac
exit 0'
  export RESTIC_REPOSITORY=/fake/repo RESTIC_PASSWORD=pw
}
ustate() { jq -r ".$2" "$OPS_STATE/state/$1.json"; }
rstate() { jq -r ".$2" "$OPS_ROOT_STATE/$1.json"; }
runjob() { source "$1"; job_main; }
mkps() {   # mkps <name> <type> [online]
  mkdir -p "$OPS_POWER_DIR/$1"; echo "$2" > "$OPS_POWER_DIR/$1/type"; [ -z "${3:-}" ] || echo "$3" > "$OPS_POWER_DIR/$1/online"
}
asroot() { export OPS_IS_ROOT=1 OPS_ROOT_STATE="$BATS_TEST_TMPDIR/root" OPS_STATE="$BATS_TEST_TMPDIR/rootlog"; mkdir -p "$OPS_STATE/state" "$OPS_STATE/locks" "$OPS_STATE/queue" "$OPS_STATE/pending"; }
nopp() {   # PATH without a real powerprofilesctl: stubs + a symlink farm of /usr/bin minus it
  local farm="$BATS_TEST_TMPDIR/farm" f; mkdir -p "$farm"
  for f in /usr/bin/*; do [ "${f##*/}" = powerprofilesctl ] || ln -sf "$f" "$farm/${f##*/}"; done
  rm -f "$BIN/powerprofilesctl"; echo "$BIN:$farm"
}
snap_at() { printf '[{"time":"%s","short_id":"abcd1234"}]' "$(date -u -d "-$1 hours" +%Y-%m-%dT%H:%M:%S.123456789Z)"; }

# ---- power-profile (root job) ----
@test "power-profile: laptop on AC -> performance" {
  asroot; mkps AC Mains 1; mkps BAT0 Battery
  runjob "$SJ/power-profile.sh"
  grep -qx 'powerprofilesctl set performance' "$STUB_LOG"
  [ "$(rstate power-profile status)" = ok ]
}
@test "power-profile: laptop on battery -> power-saver" {
  asroot; mkps AC Mains 0; mkps BAT0 Battery
  runjob "$SJ/power-profile.sh"
  grep -qx 'powerprofilesctl set power-saver' "$STUB_LOG"
}
@test "power-profile: desktop (no battery) -> balanced" {
  asroot; mkps AC Mains 1
  runjob "$SJ/power-profile.sh"
  grep -qx 'powerprofilesctl set balanced' "$STUB_LOG"
}
@test "power-profile: peripheral batteries do not make a desktop a laptop" {
  asroot; mkps AC Mains 1; mkps hid-mouse Battery; echo Device > "$OPS_POWER_DIR/hid-mouse/scope"
  runjob "$SJ/power-profile.sh"
  grep -qx 'powerprofilesctl set balanced' "$STUB_LOG"
}
@test "power-profile: no power-profiles-daemon -> ok n/a, nothing run" {
  asroot; mkps AC Mains 1
  PATH="$(nopp)" runjob "$SJ/power-profile.sh"
  [ "$(rstate power-profile status)" = ok ]; [[ $(rstate power-profile summary) == n/a* ]]
}
@test "power-profile: dry-run prints the command and does not run it" {
  asroot; mkps AC Mains 1; mkps BAT0 Battery
  run runjob "$SJ/power-profile.sh"
  DOTS_OPS_DRY_RUN=1 run runjob "$SJ/power-profile.sh"
  [[ $output == *'+ powerprofilesctl set performance'* ]]
  [ "$(grep -c . "$STUB_LOG")" = 1 ]   # only the non-dry first run
}
@test "power-profile: a failing powerprofilesctl -> warn, not fail" {
  asroot; mkps AC Mains 1; mkstub powerprofilesctl 'exit 1'
  runjob "$SJ/power-profile.sh"
  [ "$(rstate power-profile status)" = warn ]
}
@test "udev rule: Mains change event starts the root job through an absolute systemctl path" {
  f="$R/system/dots-ops/udev/90-dots-ops-power.rules"
  grep -qx 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/usr/bin/systemctl start --no-block dots-ops@power-profile.service"' "$f"
}
@test "NixOS module rewrites the udev systemctl path to the store and provides powerprofilesctl" {
  n="$R/nix/hosts/nixos-laptop/dots-ops.nix"
  grep -q 'replace-fail /usr/bin/systemctl ${pkgs.systemd}/bin/systemctl' "$n"
  grep -q 'pkgs.power-profiles-daemon' "$n"
}

# ---- perf-mode ----
perf() { run --separate-stderr bash "$CLI" perf-mode "$@"; }
@test "perf-mode on: performance profile + DND on + state file + notification" {
  perf on; [ "$status" -eq 0 ]
  grep -qx 'powerprofilesctl set performance' "$STUB_LOG"; grep -qx 'swaync-client -dn' "$STUB_LOG"
  [ "$(cat "$OPS_STATE/perf-mode")" = on ]; grep -q 'on' "$NOTIFY_LOG"
}
@test "perf-mode off on AC -> balanced + DND off" {
  mkps AC Mains 1; mkps BAT0 Battery; echo on > "$OPS_STATE/perf-mode"
  perf off; [ "$status" -eq 0 ]
  grep -qx 'powerprofilesctl set balanced' "$STUB_LOG"; grep -qx 'swaync-client -df' "$STUB_LOG"
  [ "$(cat "$OPS_STATE/perf-mode")" = off ]
}
@test "perf-mode off on battery -> power-saver" {
  mkps AC Mains 0; mkps BAT0 Battery
  perf off; grep -qx 'powerprofilesctl set power-saver' "$STUB_LOG"
}
@test "perf-mode default toggles on then off" {
  mkps AC Mains 1
  perf; [ "$(cat "$OPS_STATE/perf-mode")" = on ]; grep -qx 'swaync-client -dn' "$STUB_LOG"
  perf; [ "$(cat "$OPS_STATE/perf-mode")" = off ]; grep -qx 'swaync-client -df' "$STUB_LOG"
}
@test "perf-mode explicit toggle behaves like the default" {
  perf toggle; [ "$(cat "$OPS_STATE/perf-mode")" = on ]
}
@test "perf-mode without powerprofilesctl still toggles DND and says profiles are unavailable" {
  PATH="$(nopp)" perf on; [ "$status" -eq 0 ]
  grep -qx 'swaync-client -dn' "$STUB_LOG"; grep -q 'power profiles unavailable' "$NOTIFY_LOG"
  [ "$(cat "$OPS_STATE/perf-mode")" = on ]
}
@test "perf-mode dry-run prints the commands and runs nothing" {
  DOTS_OPS_DRY_RUN=1 perf on; [ "$status" -eq 0 ]
  [[ $output == *'+ powerprofilesctl set performance'* ]]; [[ $output == *'+ swaync-client -dn'* ]]
  [ ! -s "$STUB_LOG" ]
}
@test "perf-mode rejects an unknown argument" {
  perf sideways; [ "$status" -eq 2 ]
}

# ---- backup ----
@test "backup: unset repository -> warn 'not configured', never fail, restic not run" {
  unset RESTIC_REPOSITORY
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = warn ]; [[ $(ustate backup summary) == *'not configured'* ]]
  ! grep -q restic "$STUB_LOG"
}
@test "backup: no password source at all -> warn not configured" {
  unset RESTIC_PASSWORD
  runjob "$UJ/backup.sh"; [ "$(ustate backup status)" = warn ]
}
@test "backup: RESTIC_PASSWORD_FILE counts as a password" {
  unset RESTIC_PASSWORD; export RESTIC_PASSWORD_FILE=/fake/pw
  runjob "$UJ/backup.sh"; [ "$(ustate backup status)" = ok ]
}
@test "backup: ~/.secrets (0600, own) is sourced for the credentials" {
  unset RESTIC_REPOSITORY RESTIC_PASSWORD
  printf 'RESTIC_REPOSITORY=/from/secrets\nRESTIC_PASSWORD=pw\n' > "$HOME/.secrets"; chmod 600 "$HOME/.secrets"
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = ok ]
}
@test "backup: ~/.secrets writable by group/other is NOT sourced" {
  unset RESTIC_REPOSITORY RESTIC_PASSWORD
  printf 'RESTIC_REPOSITORY=/from/secrets\nRESTIC_PASSWORD=pw\n' > "$HOME/.secrets"; chmod 662 "$HOME/.secrets"
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = warn ]; ! grep -q restic "$STUB_LOG"
}
@test "backup: success -> ok with short snapshot id and added size; forget uses the config policy" {
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = ok ]
  [[ $(ustate backup summary) == *abcdef01* ]]; [[ $(ustate backup summary) == *'5 MiB'* ]]
  grep -qx "restic backup $HOME --exclude-caches --exclude-file $HOME/.config/dots-ops/backup-excludes --tag dots-ops --json" "$STUB_LOG"
  grep -qx 'restic forget --tag dots-ops --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune' "$STUB_LOG"
}
@test "backup: dry-run shows backup and forget with config values, runs nothing" {
  DOTS_OPS_DRY_RUN=1 run runjob "$UJ/backup.sh"
  [[ $output == *'+ restic forget --tag dots-ops --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune'* ]]
  [[ $output == *'+ restic backup'* ]]
  ! grep -q '^restic' "$STUB_LOG"
}
@test "backup: dots repo inside HOME is not added twice" {
  runjob "$UJ/backup.sh"
  [ "$(grep -c '^restic backup' "$STUB_LOG")" = 1 ]
  ! grep '^restic backup' "$STUB_LOG" | grep -q "$HOME/dots"
}
@test "backup: dots repo outside HOME is added" {
  export STUB_SOURCE_PATH=/srv/dots
  runjob "$UJ/backup.sh"
  grep '^restic backup' "$STUB_LOG" | grep -q " $HOME /srv/dots "
}
@test "backup: locked repository (exit 11) -> warn 'repository locked'" {
  export STUB_RESTIC_RC=11 STUB_RESTIC_ERR='unable to create lock'
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = warn ]; [[ $(ustate backup summary) == *'repository locked'* ]]
  ! grep -q '^restic forget' "$STUB_LOG"
}
@test "backup: other failure -> fail with the last stderr line, no forget" {
  export STUB_RESTIC_RC=1 STUB_RESTIC_ERR='first line\nFatal: wrong password'
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = fail ]; [[ $(ustate backup summary) == *'Fatal: wrong password'* ]]
  ! grep -q '^restic forget' "$STUB_LOG"
}
@test "backup: unreadable files (exit 3) still made a snapshot -> warn, forget still runs" {
  mkstub restic 'echo "restic $*" >> "$STUB_LOG"; [ "$1" = backup ] && { echo "{\"message_type\":\"summary\",\"snapshot_id\":\"abcdef0123\",\"data_added\":1}"; exit 3; }; exit 0'
  runjob "$UJ/backup.sh"
  [ "$(ustate backup status)" = warn ]; grep -q '^restic forget' "$STUB_LOG"
}
@test "backup is heavy" { grep -q '^OPS_HEAVY=1' "$UJ/backup.sh"; }
@test "backup-excludes lists the brief's patterns" {
  f="$R/home/private_dot_config/dots-ops/backup-excludes"
  for p in .cache .local/share/Trash .nix-profile node_modules .cargo/registry go/pkg 'Downloads/*.iso' walls/.git; do grep -qF -- "$p" "$f"; done
}

# ---- backup-watch ----
@test "backup-watch: not configured -> ok n/a" {
  unset RESTIC_REPOSITORY
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = ok ]; [[ $(ustate backup-watch summary) == n/a* ]]
}
@test "backup-watch: snapshot 50 h old (max 48) -> fail" {
  export STUB_SNAP_JSON; STUB_SNAP_JSON=$(snap_at 50)
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = fail ]
  grep -qx 'restic snapshots --tag dots-ops --latest 1 --json' "$STUB_LOG"
}
@test "backup-watch: snapshot 5 h old -> ok 'last backup 5h ago'" {
  export STUB_SNAP_JSON; STUB_SNAP_JSON=$(snap_at 5)
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = ok ]; [ "$(ustate backup-watch summary)" = 'last backup 5h ago' ]
}
@test "backup-watch: snapshot time with a numeric offset is parsed" {
  export STUB_SNAP_JSON; STUB_SNAP_JSON=$(printf '[{"time":"%s+00:00"}]' "$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%S.5)")
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = ok ]; [ "$(ustate backup-watch summary)" = 'last backup 3h ago' ]
}
@test "backup-watch: no snapshots at all -> fail" {
  export STUB_SNAP_JSON='[]'
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = fail ]
}
@test "backup-watch: repository unreachable -> warn, not fail" {
  export STUB_RESTIC_RC=1 STUB_RESTIC_ERR='Fatal: unable to open repository'
  runjob "$UJ/backup-watch.sh"
  [ "$(ustate backup-watch status)" = warn ]
}

# ---- backup-check ----
@test "backup-check: runs the 5% read-data subset; success -> ok" {
  runjob "$UJ/backup-check.sh"
  grep -qx 'restic check --read-data-subset=5%' "$STUB_LOG"; [ "$(ustate backup-check status)" = ok ]
}
@test "backup-check: failure -> fail with the last line" {
  export STUB_RESTIC_RC=1 STUB_RESTIC_ERR='Fatal: pack abc corrupt'
  runjob "$UJ/backup-check.sh"
  [ "$(ustate backup-check status)" = fail ]; [[ $(ustate backup-check summary) == *'pack abc corrupt'* ]]
}
@test "backup-check: not configured -> ok n/a; job is heavy" {
  unset RESTIC_REPOSITORY
  runjob "$UJ/backup-check.sh"
  [[ $(ustate backup-check summary) == n/a* ]]; grep -q '^OPS_HEAVY=1' "$UJ/backup-check.sh"
}

# ---- wiring ----
@test "timers: backup-watch daily and backup-check weekly, both Persistent; enabled by the systemd script" {
  d="$R/home/private_dot_config/systemd/private_user"
  grep -qx 'OnCalendar=daily' "$d/dots-ops-backup-watch.timer"; grep -qx 'Unit=dots-ops@backup-watch.service' "$d/dots-ops-backup-watch.timer"
  grep -qx 'OnCalendar=weekly' "$d/dots-ops-backup-check.timer"; grep -qx 'Unit=dots-ops@backup-check.service' "$d/dots-ops-backup-check.timer"
  grep -qx 'Persistent=true' "$d/dots-ops-backup-watch.timer"; grep -qx 'Persistent=true' "$d/dots-ops-backup-check.timer"
  grep -q 'dots-ops-backup-watch.timer dots-ops-backup-check.timer' "$R/home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl"
}
@test "bindings: Hyprland Super+Shift+F12 and Waybar right-click run perf-mode" {
  grep -q 'SHIFT + F12.*dots-ops perf-mode' "$R/home/private_dot_config/hypr/hyprland.lua.tmpl"
  grep -q '"on-click-right": ".*dots-ops perf-mode"' "$R/home/private_dot_config/waybar/config.jsonc.tmpl"
}
@test "root layer: power-profiles-daemon (arch, debian) and tuned-ppd (fedora) are installed" {
  s="$R/home/.chezmoiscripts/run_once_before_00-system.sh.tmpl"
  [ "$(grep -c 'power-profiles-daemon' "$s")" -ge 2 ]; grep -q 'tuned-ppd' "$s"
}
@test "CLI usage mentions perf-mode" { grep -q 'perf-mode \[on|off|toggle\]' "$CLI"; }
