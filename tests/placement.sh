#!/usr/bin/env bash
# usage: tests/placement.sh — renders each data file and checks expected targets + GPU branch
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
for data in "$root"/tests/data-*.toml; do
  out="$(mktemp -d)"; bash "$root/tests/render.sh" "$data" "$out" || { echo "RENDER-FAIL $data"; fail=1; continue; }
  mux=$(sed -nE 's/ *multiplexer = "(.*)"/\1/p' "$data"); gpu=$(sed -nE 's/ *gpu = "(.*)"/\1/p' "$data")
  while read -r mode tag path; do
    case "$mode" in ""|\#*) continue ;; esac
    [ "$tag" = all ] || [ "$tag" = "$mux" ] || continue
    f="$out/$path"
    [ -e "$f" ] || { echo "MISSING[$gpu/$mux] $path"; fail=1; continue; }
    [ "$mode" != x ] || [ -x "$f" ] || { echo "NOT-EXEC[$gpu/$mux] $path"; fail=1; }
  done < "$root/tests/expected-targets.txt"
  h="$out/.config/hypr/hyprland.lua"
  if [ -f "$h" ]; then
    if [ "$gpu" = nvidia ]; then grep -q LIBVA_DRIVER_NAME "$h" || { echo "GPU: nvidia render lacks nvidia env"; fail=1; }
    else ! grep -q LIBVA_DRIVER_NAME "$h" || { echo "GPU: $gpu render has nvidia env"; fail=1; }; fi
  fi
done
exit $fail
