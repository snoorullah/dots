#!/usr/bin/env bash
# Render the otter banner via the kitty graphics protocol (Ghostty implements it) (crisp). Called from otter header_cmd.
set -uo pipefail
IMG="${OTTER_BANNER:-$HOME/.config/otter-launcher/images/otter.png}"
[ -f "$IMG" ] || exit 0
chafa --fit-width -f kitty "$IMG" 2>/dev/null
