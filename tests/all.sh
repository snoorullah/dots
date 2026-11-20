#!/usr/bin/env bash
# Every suite, on this machine. GitHub Actions is not used for this repo, so this script IS the CI:
# lefthook runs it before every push (lefthook.yml), and it is what "tests pass" means in a PR.
#
#   tests/all.sh            all suites, 6 at a time; logs in $ALL_LOG_DIR (default: a temp dir)
#   tests/all.sh icons lint only the named suites
#   ALL_JOBS=1 tests/all.sh run one at a time
#
# Not run by default (each needs something a push should not wait on):
#   shell.sh         a private headless Hyprland  -> ALL_SHELL=1
#   distro-matrix.sh docker, five distro images   -> ALL_DISTRO=1
#   overlap.sh       a built activation package   -> run it by hand after a switch
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
log="${ALL_LOG_DIR:-$(mktemp -d -t dots-tests.XXXXXX)}"; mkdir -p "$log"
jobs="${ALL_JOBS:-6}"

# not suites: sourced libraries, render helpers, and the opt-in ones above
skip=" qs-harness render in-home all shell distro-matrix overlap "
suites=()
if [ $# -gt 0 ]; then suites=("$@")
else
  for f in tests/*.sh; do n="$(basename "$f" .sh)"; [[ "$skip" == *" $n "* ]] || suites+=("$n"); done
  suites+=(in-home ops)
  [ -n "${ALL_SHELL:-}" ] && suites+=(shell)
  [ -n "${ALL_DISTRO:-}" ] && suites+=(distro-matrix)
fi

run_one() {
  local n="$1" log="$2" rc=0 t0=$SECONDS
  case "$n" in
    in-home)
      local d; d="$(mktemp -d)"
      { bash tests/render.sh tests/data-nvidia-tmux.toml "$d" && HOME="$d" bash tests/in-home.sh --sentinel; } \
        >"$log/$n.log" 2>&1 || rc=$?
      rm -rf "$d" ;;
    ops)
      # same rule as the old CI job: the only allowed skip is "no /nix" (never true here)
      bats --tap tests/ops >"$log/$n.log" 2>&1 || rc=$?
      if grep -E '^(ok|not ok) .*# skip' "$log/$n.log" >/dev/null; then echo "unexpected skip" >>"$log/$n.log"; rc=1; fi ;;
    fonts)
      # before the first switch the families are not in fontconfig yet: check the packages, say so
      if fc-list : family | grep -q 'Bricolage Grotesque'; then bash tests/fonts.sh >"$log/$n.log" 2>&1 || rc=$?
      else FONTS_SKIP_FC=1 bash tests/fonts.sh >"$log/$n.log" 2>&1 || rc=$?; echo "NOTE fontconfig check skipped: fonts not installed yet" >>"$log/$n.log"; fi ;;
    distro-matrix)
      for img in ubuntu:24.04 debian:12 archlinux:latest fedora:41 rockylinux:9; do
        docker run --rm -v "$PWD:/src:ro" "$img" bash /src/tests/distro-matrix.sh >>"$log/$n.log" 2>&1 || rc=$?
      done ;;
    *) bash "tests/$n.sh" >"$log/$n.log" 2>&1 || rc=$? ;;
  esac
  printf '%s %s %ss\n' "$rc" "$n" "$((SECONDS - t0))" >"$log/$n.rc"
}
export -f run_one

# These render through chezmoi and collide when run side by side (each passes alone): run them one
# at a time, alongside the parallel pool.
serial=" lint orgmanaged placement in-home theme fonts extra-tools-dryrun taskgate track "
par=(); ser=()
for n in "${suites[@]}"; do if [[ "$serial" == *" $n "* ]]; then ser+=("$n"); else par+=("$n"); fi; done
( for n in "${ser[@]}"; do run_one "$n" "$log"; done ) &
[ ${#par[@]} -gt 0 ] && printf '%s\n' "${par[@]}" | xargs -P "$jobs" -I{} bash -c 'run_one "$@"' _ {} "$log"
wait

fail=0
printf '%-20s %-6s %s\n' SUITE RESULT TIME
for n in "${suites[@]}"; do
  read -r rc _ secs <"$log/$n.rc" 2>/dev/null || { rc=missing; secs=-; }
  if [ "$rc" = 0 ]; then r=pass; else r=FAIL; fail=1; fi
  grep -q '^NOTE' "$log/$n.log" 2>/dev/null && r="$r*"
  printf '%-20s %-6s %s\n' "$n" "$r" "$secs"
done
grep -h '^NOTE' "$log"/*.log 2>/dev/null | sed 's/^/* /'
echo "logs: $log"
if [ "$fail" != 0 ]; then
  echo "failed logs:"; for n in "${suites[@]}"; do read -r rc _ <"$log/$n.rc" 2>/dev/null; [ "${rc:-1}" = 0 ] || echo "  $log/$n.log"; done
fi
exit "$fail"
