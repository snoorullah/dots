#!/usr/bin/env bash
# otter-tmux.sh — tmux session manager (fzf-based otter-launcher module)
#
# Ported from rofi-tmux.sh: list/attach existing sessions, create a new
# named session, or kill a session. Preserves the original's inside-tmux
# vs outside-tmux detection (switch-client vs attach; spawn a kitty only
# when invoked from outside tmux).
set -uo pipefail
source "$HOME/.config/otter-launcher/scripts/_otter-fzf.sh"

new_entry=$'  New Session'
kill_entry=$'  Kill Session'

# get_sessions -- one line per running tmux session, formatted as
# "<name> (<N> windows) [attached]" (the "[attached]" tag only appears if
# someone is already attached), same as rofi-tmux.sh, followed by the two
# fixed action entries.
get_sessions() {
    local sessions
    sessions="$(tmux list-sessions -F "#{session_name} (#{session_windows} windows) #{?session_attached,[attached],}" 2>/dev/null)"
    [[ -n "$sessions" ]] && echo "$sessions"
    echo "$new_entry"
    echo "$kill_entry"
}

chosen="$(get_sessions | fzf --header=$' tmux')"

# Exit silently if the user dismissed the menu without choosing.
[[ -z "$chosen" ]] && exit 0

if [[ "$chosen" == "$new_entry" ]]; then
    # --- Create a new session ---
    # fzf has no pure "text input" mode like `rofi -lines 0`; emulate one
    # with --print-query over an empty candidate list so Enter yields
    # whatever the user typed.
    session_name="$(printf '' | fzf --print-query --header='session name' --prompt='name> ' | sed -n '1p')"
    if [[ -n "$session_name" ]]; then
        # Nesting "tmux new-session" inside an existing tmux client fails
        # ("sessions should be nested with care"); create detached and
        # switch the current client instead when already inside tmux.
        if [[ -n "${TMUX:-}" ]]; then
            tmux new-session -d -s "$session_name" && tmux switch-client -t "$session_name"
        else
            # Not inside tmux: spawn a new kitty terminal running the new
            # tmux session, detached so this script can exit immediately.
            setsid -f kitty -e tmux new-session -s "$session_name" >/dev/null 2>&1
        fi
        notify-send "Tmux" "Created session: $session_name" -t 3000
    fi
elif [[ "$chosen" == "$kill_entry" ]]; then
    # --- Kill an existing session ---
    sessions="$(tmux list-sessions -F "#{session_name}" 2>/dev/null)"
    if [[ -z "$sessions" ]]; then
        notify-send "Tmux" "No sessions to kill" -t 3000
        exit 0
    fi
    target="$(echo "$sessions" | fzf --header='kill which session?')"
    if [[ -n "$target" ]]; then
        tmux kill-session -t "$target"
        notify-send "Tmux" "Killed session: $target" -t 3000
    fi
else
    # --- Attach to an existing session ---
    # The chosen line starts with the session name, followed by metadata
    # in parentheses -- same first-word extraction as rofi-tmux.sh (note:
    # this means session names containing spaces are not fully supported,
    # a limitation carried over unchanged from the reference script).
    session_name="$(awk '{print $1}' <<<"$chosen")"
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$session_name"
    else
        setsid -f kitty -e tmux attach-session -t "$session_name" >/dev/null 2>&1
    fi
fi
