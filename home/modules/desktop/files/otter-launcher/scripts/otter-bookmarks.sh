#!/usr/bin/env bash
# otter-bookmarks.sh — Zen Browser bookmarks (fzf-based otter-launcher module)
#
# Ported from rofi-bookmarks.sh: reads bookmarks straight from Zen
# Browser's places.sqlite and opens the selected one in a new tab via
# zen_open_url (does not touch the running browser's own state).
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"
# shellcheck source=/home/devsupreme/.config/rofi/scripts/zen-utils.sh
source "$HOME/.config/rofi/scripts/zen-utils.sh"

# Same query as rofi-bookmarks.sh: type=1 filters real bookmarks (not
# folders/separators), excludes NULL/empty titles and internal 'place:'
# smart-bookmark URLs, newest first. zen_query_db returns tab-separated
# columns, which we feed straight to fzf as "title<TAB>url".
bookmarks="$(zen_query_db "
    SELECT b.title, p.url
    FROM moz_bookmarks b
    JOIN moz_places p ON b.fk = p.id
    WHERE b.type = 1
    AND b.title IS NOT NULL
    AND b.title != ''
    AND p.url NOT LIKE 'place:%'
    ORDER BY b.dateAdded DESC;
")"

if [[ -z "$bookmarks" ]]; then
    notify-send "Bookmarks" "No bookmarks found" -u normal
    exit 0
fi

# --delimiter/--with-nth restrict the *displayed* field to the title while
# fzf still fuzzy-matches against it; the url stays attached (tab-
# separated) so it can be pulled back out of the selected line below.
chosen="$(echo "$bookmarks" | fzf --ansi --delimiter='\t' --with-nth=1 --header='bookmarks')"
[[ -z "$chosen" ]] && exit 0

url="$(cut -f2 <<<"$chosen")"
zen_open_url "$url"
