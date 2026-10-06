#!/usr/bin/env bash
# otter-projects.sh — project launcher (fzf-based otter-launcher module)
#
# Ported from rofi-projects.sh: lists directories under ~/work/, tagging
# each with an icon for its detected project type (same marker-file
# detection, same order), then offers a second menu to open the chosen
# project in VS Code / a terminal / the file manager (same open commands).
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

PROJECTS_DIR="$HOME/work"
mkdir -p "$PROJECTS_DIR"

# get_project_icon -- same detection order as rofi-projects.sh (most
# specific marker files first, generic git/folder fallbacks last).
# NOTE: the reference script left Rust/Node/Python/Java/Ruby/generic-git
# icons as empty strings (an apparent oversight -- confirmed by inspecting
# the file's raw bytes). This port fills those in with real glyphs for a
# consistent look; Go and the plain-directory icon are copied verbatim
# from the reference (same codepoints).
get_project_icon() {
    local dir="$1"
    if   [[ -f "$dir/go.mod" ]]; then echo $'󰟓'                            # Go
    elif [[ -f "$dir/Cargo.toml" ]]; then echo $''                      # Rust
    elif [[ -f "$dir/package.json" ]]; then echo $''                    # Node.js / JavaScript
    elif [[ -f "$dir/requirements.txt" || -f "$dir/pyproject.toml" || -f "$dir/setup.py" ]]; then echo $''  # Python
    elif [[ -f "$dir/pom.xml" || -f "$dir/build.gradle" ]]; then echo $''  # Java
    elif [[ -f "$dir/Gemfile" ]]; then echo $''                         # Ruby
    elif [[ -d "$dir/.git" ]]; then echo $''                            # Generic git repo
    else echo $'󰉋'                                                    # Plain directory
    fi
}

# list_projects -- "icon  name" per top-level dir under PROJECTS_DIR,
# same two-space separator as the reference script (find -maxdepth 1
# -mindepth 1 so only top-level directories appear).
list_projects() {
    local dir name icon
    while IFS= read -r dir; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        icon="$(get_project_icon "$dir")"
        printf '%s  %s\n' "$icon" "$name"
    done < <(find "$PROJECTS_DIR" -maxdepth 1 -mindepth 1 -type d | sort)
}

projects="$(list_projects)"
if [[ -z "$projects" ]]; then
    notify-send "Projects" "No projects found in $PROJECTS_DIR" -u normal
    exit 0
fi

chosen="$(echo "$projects" | fzf --header=$'󰉋 projects')"
[[ -z "$chosen" ]] && exit 0

# Strip the leading icon token (and the spaces after it) to recover the
# bare project name -- same extraction approach as rofi-projects.sh.
project_name="$(sed 's/^[^ ]* *//' <<<"$chosen")"
project_path="$PROJECTS_DIR/$project_name"

# Record the active project for waybar-project.sh (adhd waybar module).
# Only reached for a real selection: the [[ -z "$chosen" ]] guard above
# already exits on empty/abort, and $project_name is the bare directory
# name under ~/work/ (matches what waybar-project.sh looks up).
mkdir -p "$HOME/.cache/adhd"; printf '%s' "$project_name" > "$HOME/.cache/adhd/active-project"

# Sub-menu: choose which application to open the project with. Same
# three actions + open commands as rofi-projects.sh (VS Code / kitty /
# xdg-open); GUI launches are detached with setsid -f per the otter
# convention so this script (running in an otter-spawned kitty) can exit
# immediately without lingering.
actions=$'  Open in VS Code\n  Open Terminal\n󰉋  Open File Manager'
action="$(echo "$actions" | fzf --header="$project_name")"

case "$action" in
    *"VS Code"*)       setsid -f code "$project_path" >/dev/null 2>&1 ;;
    *"Terminal"*)       setsid -f kitty --directory "$project_path" >/dev/null 2>&1 ;;
    *"File Manager"*)   setsid -f xdg-open "$project_path" >/dev/null 2>&1 ;;
esac
