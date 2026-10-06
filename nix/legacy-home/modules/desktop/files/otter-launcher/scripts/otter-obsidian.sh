#!/usr/bin/env bash
# otter-obsidian.sh — Obsidian hub via fzf (Dracula/otter). Ported from
# rofi-obsidian{,-search,-create}.sh. Vault: ~/powerhouse.
# Actions: daily note, open vault, search notes, new note (2-step wizard).
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"
VAULT="$HOME/powerhouse"
[ -d "$VAULT" ] || { notify-send "Obsidian" "Vault not found: $VAULT" -u critical; exit 1; }

VAULT_NAME="$(basename "$VAULT")"
# Open a note IN OBSIDIAN (not VS Code) via the registered obsidian:// URI.
open_note() {
    local rel enc
    rel="${1#$VAULT/}"; rel="${rel%.md}"
    enc="$(python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe='/'))" "$rel")"
    setsid -f xdg-open "obsidian://open?vault=${VAULT_NAME}&file=${enc}" >/dev/null 2>&1
}
open_vault() { setsid -f xdg-open "obsidian://open?vault=${VAULT_NAME}" >/dev/null 2>&1; }

daily() {
    local d="$VAULT/daily"; mkdir -p "$d"
    local t f; t="$(date +%Y-%m-%d)"; f="$d/$t.md"
    [ -f "$f" ] || printf -- '---\ndate: %s\ntype: daily\ntags: [daily]\n---\n\n# %s\n\n## Tasks\n\n- [ ] \n\n## Notes\n\n' "$t" "$t" > "$f"
    open_note "$f"
}

search() {
    local n
    n="$(find "$VAULT" -name '*.md' -type f -printf '%P\n' | sort | fzf --header='search notes')" || return 0
    [ -n "$n" ] && open_note "$VAULT/$n"
}

create() {
    local dir name path
    dir="$(printf '.\n%s\n' "$(find "$VAULT" -type d -printf '%P\n' | grep -v '^\.' | sort)" | fzf --header='new note - pick folder')" || return 0
    [ -n "$dir" ] || return 0
    name="$(printf '' | fzf --print-query --header='new note - type a name (no .md), then Enter' 2>/dev/null | head -1)"
    [ -n "$name" ] || return 0
    if [ "$dir" = "." ]; then path="$VAULT/$name.md"; else mkdir -p "$VAULT/$dir"; path="$VAULT/$dir/$name.md"; fi
    if [ -f "$path" ]; then
        notify-send "Obsidian" "Already exists: $name" -u normal
    else
        printf -- '---\ndate: %s\ntype: note\ntags: []\n---\n\n# %s\n\n' "$(date +%Y-%m-%d)" "$name" > "$path"
        notify-send "Obsidian" "Created: $name" -t 3000
    fi
    open_note "$path"
}

action="$(printf '%s\n' 'daily note' 'open vault' 'search notes' 'new note' | fzf --header='obsidian')" || exit 0
case "$action" in
    'daily note')   daily ;;
    'open vault')   open_vault ;;
    'search notes') search ;;
    'new note')     create ;;
esac
