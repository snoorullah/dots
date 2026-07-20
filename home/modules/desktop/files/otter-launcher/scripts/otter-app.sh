#!/usr/bin/env bash
# otter-app.sh — desktop application launcher (fzf-based otter-launcher module)
#
# Scans every "<datadir>/applications" from XDG_DATA_HOME + XDG_DATA_DIRS (so snap,
# nix, flatpak, system and user apps all appear — Slack/Teams live under
# /var/lib/snapd/desktop/applications), parses each .desktop in a single awk pass,
# and CACHES the result. The cache is rebuilt only when an app directory's mtime
# changes, so the menu opens instantly instead of re-scanning every time.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/otter"
CACHE="$CACHE_DIR/apps.tsv"
mkdir -p "$CACHE_DIR"

# _app_dirs — every "<datadir>/applications" from XDG_DATA_HOME + XDG_DATA_DIRS
# (+ flatpak exports), deduped, in precedence order (data-home first wins de-dup).
_app_dirs() {
    local IFS=: d
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    declare -A seen_dir
    for d in "$data_home" $data_dirs \
             "$HOME/.local/share/flatpak/exports/share" "/var/lib/flatpak/exports/share"; do
        d="${d%/}/applications"
        [[ -d "$d" && -z "${seen_dir[$d]:-}" ]] || continue
        seen_dir["$d"]=1
        printf '%s\n' "$d"
    done
}

# _newest_mtime — newest mtime across the app dirs (cache-staleness signal).
_newest_mtime() {
    local d newest=0 m
    while IFS= read -r d; do
        m="$(stat -c %Y "$d" 2>/dev/null || echo 0)"
        (( m > newest )) && newest=$m
    done < <(_app_dirs)
    echo "$newest"
}

# build_list — "<desktop-id>\t<display-name>" for every visible entry; first (higher
# precedence) dir wins de-dup. Skips NoDisplay=true / Hidden=true.
build_list() {
    local dir file base rec
    declare -A seen
    while IFS= read -r dir; do
        while IFS= read -r -d '' file; do
            base="$(basename "$file" .desktop)"
            [[ -n "${seen[$base]:-}" ]] && continue
            rec="$(awk '
                /^\[Desktop Entry\]/{e=1; next}
                /^\[/{e=0}
                e && /^NoDisplay=/{if($0 ~ /=[Tt]rue/)nd=1}
                e && /^Hidden=/{if($0 ~ /=[Tt]rue/)hd=1}
                e && /^Name=/ && !n{n=substr($0,index($0,"=")+1)}
                END{if(nd||hd)exit 1; print n}' "$file" 2>/dev/null)" || continue
            seen["$base"]="${rec:-$base}"
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
    done < <(_app_dirs)
    local b
    for b in "${!seen[@]}"; do
        printf '%s\t%s\n' "$b" "${seen[$b]}"
    done | sort -t $'\t' -k2,2f
}

_ensure_cache() {
    if [[ ! -f "$CACHE" ]] || (( $(_newest_mtime) > $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) )); then
        build_list > "$CACHE.tmp" 2>/dev/null && mv -f "$CACHE.tmp" "$CACHE"
    fi
}

case "${1:-}" in
    --list)    _ensure_cache; cat "$CACHE"; exit 0 ;;
    --rebuild) build_list > "$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE"; echo "rebuilt: $(wc -l <"$CACHE") apps"; exit 0 ;;
esac

_ensure_cache
selection="$(fzf --delimiter=$'\t' --with-nth=2 --header=$' apps' < "$CACHE")"
[[ -z "$selection" ]] && exit 0
app_id="$(cut -f1 <<<"$selection")"
setsid -f gtk-launch "$app_id" >/dev/null 2>&1
