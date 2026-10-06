#!/usr/bin/env bash
# usage: HOME=<rendered-or-real home> NIXBIN=<dir with pinned tools> tests/in-home.sh
# Review Focus 2, 3: PATH contract with a hostile /usr/bin-like dir *after* Nix; empty user data.
set -uo pipefail
fail=0; B="$HOME/.local/bin"; NIXBIN="${NIXBIN:-$HOME/.nix-profile/bin}"
fake="$(mktemp -d)"; printf '#!/bin/sh\nexit 99\n' > "$fake/task"; chmod +x "$fake/task"
P="$B:$NIXBIN:$fake:/usr/bin:/bin"
grep -qE '^PATH=\$\{?HOME\}?/\.local/bin:\$\{?HOME\}?/\.nix-profile/bin:' "$HOME/.config/environment.d/10-dots-path.conf" \
  || { echo "FAIL environment.d PATH order"; fail=1; }
run() { env -i HOME="$HOME" USER="${USER:-u}" XDG_RUNTIME_DIR=/tmp PATH="$P" "$@"; }
for s in waybar-salah.sh waybar-ctx.sh waybar-tracking.sh waybar-project.sh waybar-kube.sh; do
  out="$(run "$B/$s" 2>/dev/null)"
  printf '%s' "$out" | run jq -e '.text != null' >/dev/null || { echo "FAIL $s -> '$out'"; fail=1; }
done
run "$B/adhd-focus.sh" status >/dev/null || { echo "FAIL adhd-focus.sh status"; fail=1; }
exit $fail
