#!/usr/bin/env bash
# usage: tests/placement.sh — renders each data file and checks expected targets + GPU branch
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
for data in "$root"/tests/data-*.toml; do
  out="$(mktemp -d)"; bash "$root/tests/render.sh" "$data" "$out" || { echo "RENDER-FAIL $data"; fail=1; continue; }
  mux=$(sed -nE 's/ *multiplexer = "(.*)"/\1/p' "$data"); gpu=$(sed -nE 's/ *gpu = "(.*)"/\1/p' "$data")
  org=$(sed -nE 's/ *orgManaged = (true|false)/\1/p' "$data"); [ "$org" = true ] || org=false
  while read -r mode tag path; do
    case "$mode" in ""|\#*) continue ;; esac
    f="$out/$path"
    # selectors: all | <multiplexer> | personal (only when orgManaged = false; must be ABSENT on org machines)
    if [ "$tag" = personal ] && [ "$org" = true ]; then
      [ ! -e "$f" ] || { echo "PRESENT-ON-ORG[$gpu/$mux] $path (orgManaged must not deploy it)"; fail=1; }
      continue
    fi
    [ "$tag" = all ] || [ "$tag" = personal ] || [ "$tag" = "$mux" ] || continue
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
