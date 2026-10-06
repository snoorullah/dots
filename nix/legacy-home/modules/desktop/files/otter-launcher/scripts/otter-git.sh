#!/usr/bin/env bash
# otter-git.sh — git identity switcher (fzf-based otter-launcher module)
#
# Ported from rofi-git-profile.sh: reads pipe-delimited git profiles and
# switches the global git user.name/user.email to the selected identity.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

PROFILES_FILE="$HOME/.config/rofi/scripts/git-profiles.conf"
[[ ! -f "$PROFILES_FILE" ]] && PROFILES_FILE="$HOME/.config/rofi/scripts/git-profiles.example.conf"

if [[ ! -f "$PROFILES_FILE" ]]; then
    notify-send "Error" "Git profiles config not found: $PROFILES_FILE" -u critical
    exit 1
fi

# build_options -- "label (user <email>)" per non-blank, non-comment line,
# same format as rofi-git-profile.sh (used both for display and for
# matching the selection back to its profile below).
build_options() {
    local name user email
    while IFS='|' read -r name user email; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        printf '%s (%s <%s>)\n' "$name" "$user" "$email"
    done < "$PROFILES_FILE"
}

options="$(build_options)"
if [[ -z "$options" ]]; then
    notify-send "Git Profile" "No profiles configured" -u normal
    exit 0
fi

chosen="$(echo "$options" | fzf --header='git identity')"
[[ -z "$chosen" ]] && exit 0

# Re-read the profiles file and reconstruct the display string for each
# entry, comparing it against the selection -- avoids fragile parsing of
# the label/user/email back out of the chosen line, same approach as the
# reference script.
while IFS='|' read -r name user email; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    if [[ "$chosen" == "$name ($user <$email>)" ]]; then
        git config --global user.name "$user"
        git config --global user.email "$email"
        notify-send "Git Profile" "Switched to: $user <$email>" -t 3000
        break
    fi
done < "$PROFILES_FILE"
