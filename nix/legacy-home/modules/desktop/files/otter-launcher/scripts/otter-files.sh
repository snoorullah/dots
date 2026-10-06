#!/usr/bin/env bash
# otter-files.sh — fzf directory navigator (fzf-based otter-launcher module)
#
# rofi's built-in filebrowser modi has no CLI equivalent, and no
# yazi/lf/ranger is installed on this box, so this is a small bespoke
# navigator: browse into directories, "../" to go up, open files via
# xdg-open. Starts at $HOME.
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

CUR="$HOME"

# list_dir -- "../" first, then directories ("name/"), then files
# ("name"), each group sorted independently. Hidden entries are included
# (find does not exclude dotfiles the way shell globs do).
list_dir() {
    local dir="$1" y f
    local -a dirs=() files=()

    while IFS=$'\t' read -r y f; do
        [[ -z "$f" ]] && continue
        if [[ "$y" == "d" ]]; then
            dirs+=("$f/")
        else
            files+=("$f")
        fi
    done < <(find "$dir" -maxdepth 1 -mindepth 1 -printf '%y\t%f\n' 2>/dev/null)

    printf '../\n'
    if ((${#dirs[@]})); then
        printf '%s\n' "${dirs[@]}" | sort
    fi
    if ((${#files[@]})); then
        printf '%s\n' "${files[@]}" | sort
    fi
}

while true; do
    display="${CUR/#$HOME/\~}"
    chosen="$(list_dir "$CUR" | fzf --header="  $display")"

    [[ -z "$chosen" ]] && exit 0

    if [[ "$chosen" == "../" ]]; then
        CUR="$(dirname "$CUR")"
        continue
    fi

    if [[ "$chosen" == */ ]]; then
        CUR="$CUR/${chosen%/}"
        continue
    fi

    # Not "../" and not directory-suffixed: it's a file.
    setsid -f xdg-open "$CUR/$chosen" >/dev/null 2>&1
    exit 0
done
