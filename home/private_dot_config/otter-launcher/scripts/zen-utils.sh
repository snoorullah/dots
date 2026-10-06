# zen-utils.sh — Shared utilities for Zen Browser scripts
# Source this file, do not execute directly.

export PATH="$HOME/.fzf/bin:$PATH"

CACHE_DIR="$HOME/.cache/zen-tabs"
FAVICON_DIR="$CACHE_DIR/favicons"

ZEN_WM_CLASS="zen-alpha"

# zen_open_url()
#   Open a URL in Zen Browser via xdg-open, fully detached from the caller.
#
#   Parameters: $1 — URL to open
zen_open_url() {
    xdg-open "$1" &>/dev/null &
    disown
}

# zen_urlencode()
#   URL-encode text read from stdin using Python's urllib.parse.quote_plus.
#   Reads the full stdin, strips surrounding whitespace, and prints the encoded
#   string to stdout.
#
#   Usage:  echo "my search query" | zen_urlencode
zen_urlencode() {
    python3 -c "import sys,urllib.parse; print(urllib.parse.quote_plus(sys.stdin.read().strip()))"
}

# zen_find_profile()
#   Locate the active Zen Browser profile directory under ~/.zen/.
#   Prefers release profiles (matching *.Default*release*), falling back to
#   any directory matching *.default*.
#
#   Output: absolute path to the profile directory on stdout
#   Returns: 0 on success, 1 if no matching profile is found
zen_find_profile() {
    local zen_dir="$HOME/.zen"

    # Prefer release profiles first
    local profile
    profile=$(find "$zen_dir" -maxdepth 1 -type d -name '*.Default*release*' -print -quit 2>/dev/null)

    # Fall back to any .default directory
    if [[ -z "$profile" ]]; then
        profile=$(find "$zen_dir" -maxdepth 1 -type d -name '*.default*' -print -quit 2>/dev/null)
    fi

    if [[ -z "$profile" ]]; then
        return 1
    fi

    echo "$profile"
}

# zen_query_db()
#   Safely query Zen Browser's places.sqlite database.
#   Copies the database to /tmp before querying to avoid WAL lock conflicts
#   with a running Zen instance. Uses tab as the column separator. Cleans up
#   the temporary copy on exit.
#
#   Parameters: $1 — SQL query string
#   Output:     query results with tab-separated columns on stdout
#   Returns:    0 on success, 1 if the profile or database cannot be found
zen_query_db() {
    local sql="$1"

    local profile
    profile=$(zen_find_profile) || {
        notify-send -a "Zen Browser" -u critical "Zen Browser" "Profile not found"
        return 1
    }

    local db_path="$profile/places.sqlite"
    if [[ ! -f "$db_path" ]]; then
        notify-send -a "Zen Browser" -u critical "Zen Browser" "places.sqlite not found in profile"
        return 1
    fi

    local tmp_db="/tmp/zen-places-$$.sqlite"
    cp "$db_path" "$tmp_db"

    sqlite3 -separator $'\t' "$tmp_db" "$sql" 2>/dev/null

    rm -f "$tmp_db"
}

# zen_get_favicon()
#   Fetch and cache the favicon for a given domain using Google's favicon API.
#   Favicons are cached in $FAVICON_DIR by MD5 hash of the domain name and
#   refreshed after 7 days. Prints the path to the cached favicon file on
#   stdout.
#
#   Parameters: $1 — domain (e.g. "github.com")
#   Output:     absolute path to the cached favicon file on stdout
zen_get_favicon() {
    local domain="$1"
    local hash
    hash=$(echo -n "$domain" | md5sum | cut -d' ' -f1)
    local cache_file="$FAVICON_DIR/${hash}.png"

    # Use the cached file if it exists and is less than 7 days old
    if [[ -f "$cache_file" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
        if (( age < 604800 )); then
            echo "$cache_file"
            return 0
        fi
    fi

    # Fetch from Google's favicon service
    local url="https://www.google.com/s2/favicons?domain=${domain}&sz=128"
    if curl -fsSL --max-time 5 -o "$cache_file" "$url" 2>/dev/null; then
        echo "$cache_file"
    else
        # Return whatever we have (possibly stale) rather than nothing
        [[ -f "$cache_file" ]] && echo "$cache_file"
        return 1
    fi
}

# zen_focus_browser()
#   Focus the Zen Browser window using i3's IPC, matching by X11 class.
zen_focus_browser() {
    i3-msg "[class=\"$ZEN_WM_CLASS\"]" focus &>/dev/null
}

# zen_notify()
#   Send a desktop notification attributed to "Zen Browser".
#
#   Parameters: $1 — message text
#               $2 — (optional) display duration in milliseconds (default: 3000)
zen_notify() {
    notify-send -a "Zen Browser" -t "${2:-3000}" "$1"
}

mkdir -p "$CACHE_DIR" "$FAVICON_DIR" 2>/dev/null
