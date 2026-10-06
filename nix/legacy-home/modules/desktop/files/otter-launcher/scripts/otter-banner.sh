#!/usr/bin/env bash
# Render the otter banner via kitty's image protocol (crisp). Called from otter header_cmd.
set -uo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"
IMG="${OTTER_BANNER:-$HOME/.config/otter-launcher/images/otter.png}"
[ -f "$IMG" ] || exit 0
chafa -f kitty --fit-width "$IMG" 2>/dev/null
