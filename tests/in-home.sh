#!/usr/bin/env bash
# PATH-contract behavioural test (Review Focus 2, 3).
# usage: HOME=<rendered-or-real home> [NIXBIN=<real nix profile bin>] tests/in-home.sh [--sentinel]
#
# Modes:
#  sentinel (default when NIXBIN is unset, or with --sentinel): NIXBIN is a temp dir holding a
#    fake `task` that prints a unique marker (`_get rc.context` -> FAKECTX). A hostile `task`
#    (exit 99) sits in a dir AFTER it and BEFORE /usr/bin. Proves (a) `task` resolves to the
#    Nix-side binary through the PATH contract, (b) waybar-ctx.sh really executed it (FAKECTX).
#    Host /usr/bin still supplies jq etc. in this mode.
#  real (NIXBIN points at a built Nix profile, e.g. $act/home-path/bin): `task` must resolve
#    to $NIXBIN/task, and all scripts must emit valid JSON using the real pinned tools.
# Always: environment.d PATH order check; JSON validity of waybar-* scripts; empty user data.
set -uo pipefail
mode=real
[ "${1:-}" = "--sentinel" ] && { mode=sentinel; NIXBIN=""; }
[ -z "${NIXBIN:-}" ] && mode=sentinel
fail=0; B="$HOME/.local/bin"
tmp="$(mktemp -d)"; hostile="$tmp/hostile"; mkdir -p "$hostile"
printf '#!/bin/sh\nexit 99\n' > "$hostile/task"; chmod +x "$hostile/task"
if [ "$mode" = sentinel ]; then
  NIXBIN="$tmp/nix"; mkdir -p "$NIXBIN"
  cat > "$NIXBIN/task" <<'EOS'
#!/bin/sh
case "$*" in
  "_get rc.context") echo FAKECTX ;;
  *) echo dots-nix-task ;;
esac
EOS
  chmod +x "$NIXBIN/task"
fi
P="$B:$NIXBIN:$hostile:/usr/bin:/bin"
grep -qE '^PATH=\$\{?HOME\}?/\.local/bin:\$\{?HOME\}?/\.nix-profile/bin:' "$HOME/.config/environment.d/10-dots-path.conf" \
  || { echo "FAIL environment.d PATH order"; fail=1; }
run() { env -i HOME="$HOME" USER="${USER:-u}" XDG_RUNTIME_DIR=/tmp PATH="$P" "$@"; }
got="$(run sh -c 'command -v task')"
[ "$got" = "$NIXBIN/task" ] || { echo "FAIL task resolves to '$got', want $NIXBIN/task"; fail=1; }
for s in waybar-salah.sh waybar-ctx.sh waybar-tracking.sh waybar-project.sh waybar-kube.sh; do
  out="$(run "$B/$s" 2>/dev/null </dev/null)"
  printf '%s' "$out" | run jq -e '.text != null' >/dev/null || { echo "FAIL $s -> '$out'"; fail=1; }
done
if [ "$mode" = sentinel ]; then
  out="$(run "$B/waybar-ctx.sh" 2>/dev/null </dev/null)"
  case "$out" in *FAKECTX*) ;; *) echo "FAIL waybar-ctx.sh did not run the Nix-side task: '$out'"; fail=1 ;; esac
fi
run "$B/adhd-focus.sh" status >/dev/null </dev/null || { echo "FAIL adhd-focus.sh status"; fail=1; }
rm -rf "$tmp"
echo "in-home ($mode): $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
