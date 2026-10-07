#!/usr/bin/env bash
# Custom tmux-fzf menu — runs entirely in a floating kitty terminal
# Features: breadcrumbs, back navigation (Esc/[back]), native input prompts

set -u

# Re-launch in floating terminal if called from tmux directly
if [ -z "${TMUX_FZF_FLOAT:-}" ] && [ -n "${TMUX:-}" ]; then
    exec "$HOME/.config/tmux/scripts/fzf-float.sh" "$0" "$@"
fi

TMUX_BIN="/usr/bin/tmux"

# ── Helpers ───────────────────────────────────────────────────────────

pick() {
    # $1 = breadcrumb, $2 = prompt icon, rest = fzf args
    local crumb="$1" icon="$2"
    shift 2
    fzf --prompt="$icon " --header="$crumb" "$@"
}

# ── Main loop (allows back navigation) ────────────────────────────────

while true; do

category=$(printf "window\nsession\npane\ncommand\nkeybinding" | pick \
    "tmux-fzf" "" --no-multi) || exit 0

[ -z "$category" ] && exit 0

# ══════════════════════════════════════════════════════════════════════
# WINDOW
# ══════════════════════════════════════════════════════════════════════
if [[ "$category" == "window" ]]; then
    while true; do
        action=$(printf "switch\nrename\nkill\nswap\n← back" | pick \
            "tmux-fzf › window" "" --no-multi) || break
        [[ "$action" == "← back" || -z "$action" ]] && break

        current=$($TMUX_BIN display-message -p '#S:#I')
        windows=$($TMUX_BIN list-windows -a -F '#S:#I: #{window_name}#{?window_active, (active),}')

        if [[ "$action" == "switch" ]]; then
            windows_filtered=$(echo "$windows" | grep -v "^${current}:")
            target=$(printf "%s\n← back" "$windows_filtered" | pick \
                "tmux-fzf › window › switch" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            session=$(echo "$target" | cut -d: -f1)
            win=$(echo "$target" | cut -d: -f2 | sed 's/:.*//')
            $TMUX_BIN switch-client -t "$session" 2>/dev/null
            $TMUX_BIN select-window -t "$session:$win"
            exit 0

        elif [[ "$action" == "rename" ]]; then
            cur_display=$($TMUX_BIN display-message -p '#S:#I: #{window_name}')
            target=$(printf "[current] %s\n%s\n← back" "$cur_display" "$windows" | pick \
                "tmux-fzf › window › rename" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            if [[ "$target" == "[current]"* ]]; then
                win_target="$current"
            else
                win_target=$(echo "$target" | sed 's/: .*//')
            fi
            printf "\033[38;2;189;147;249m tmux-fzf › window › rename › name\033[0m\n"
            printf "\033[1;35mNew name: \033[0m"
            read -r new_name
            [ -z "$new_name" ] && continue
            $TMUX_BIN rename-window -t "$win_target" "$new_name"
            exit 0

        elif [[ "$action" == "kill" ]]; then
            cur_display=$($TMUX_BIN display-message -p '#S:#I: #{window_name}')
            target=$(printf "[current] %s\n%s\n← back" "$cur_display" "$windows" | pick \
                "tmux-fzf › window › kill" "" -m) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            echo "$target" | while read -r line; do
                if [[ "$line" == "[current]"* ]]; then t="$current"
                else t=$(echo "$line" | sed 's/: .*//'); fi
                $TMUX_BIN kill-window -t "$t" 2>/dev/null
            done
            exit 0

        elif [[ "$action" == "swap" ]]; then
            target=$(printf "%s\n← back" "$windows" | pick \
                "tmux-fzf › window › swap (from)" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            t1=$(echo "$target" | sed 's/: .*//')
            remaining=$(echo "$windows" | grep -v "^$t1:")
            target2=$(printf "%s\n← back" "$remaining" | pick \
                "tmux-fzf › window › swap (to)" "" --no-multi) || continue
            [[ "$target2" == "← back" || -z "$target2" ]] && continue
            t2=$(echo "$target2" | sed 's/: .*//')
            $TMUX_BIN swap-window -s "$t1" -t "$t2"
            exit 0
        fi
    done

# ══════════════════════════════════════════════════════════════════════
# SESSION
# ══════════════════════════════════════════════════════════════════════
elif [[ "$category" == "session" ]]; then
    while true; do
        action=$(printf "switch\nnew\nrename\nkill\n← back" | pick \
            "tmux-fzf › session" "" --no-multi) || break
        [[ "$action" == "← back" || -z "$action" ]] && break

        sessions=$($TMUX_BIN list-sessions -F '#S: #{session_windows} windows#{?session_attached, (attached),}')

        if [[ "$action" == "switch" ]]; then
            current_session=$($TMUX_BIN display-message -p '#S')
            sessions_filtered=$(echo "$sessions" | grep -v "^${current_session}:")
            target=$(printf "%s\n← back" "$sessions_filtered" | pick \
                "tmux-fzf › session › switch" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            session=$(echo "$target" | cut -d: -f1)
            $TMUX_BIN switch-client -t "$session"
            exit 0

        elif [[ "$action" == "new" ]]; then
            printf "\033[38;2;189;147;249m tmux-fzf › session › new\033[0m\n"
            printf "\033[1;35mSession name: \033[0m"
            read -r session_name
            [ -z "$session_name" ] && continue
            $TMUX_BIN new-session -d -s "$session_name"
            $TMUX_BIN switch-client -t "$session_name"
            exit 0

        elif [[ "$action" == "rename" ]]; then
            target=$(printf "%s\n← back" "$sessions" | pick \
                "tmux-fzf › session › rename" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            session=$(echo "$target" | cut -d: -f1)
            printf "\033[38;2;189;147;249m tmux-fzf › session › rename › name\033[0m\n"
            printf "\033[1;35mNew name: \033[0m"
            read -r new_name
            [ -z "$new_name" ] && continue
            $TMUX_BIN rename-session -t "$session" "$new_name"
            exit 0

        elif [[ "$action" == "kill" ]]; then
            target=$(printf "%s\n← back" "$sessions" | pick \
                "tmux-fzf › session › kill" "" -m) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            echo "$target" | while read -r line; do
                session=$(echo "$line" | cut -d: -f1)
                $TMUX_BIN kill-session -t "$session" 2>/dev/null
            done
            exit 0
        fi
    done

# ══════════════════════════════════════════════════════════════════════
# PANE
# ══════════════════════════════════════════════════════════════════════
elif [[ "$category" == "pane" ]]; then
    while true; do
        action=$(printf "switch\nkill\nswap\n← back" | pick \
            "tmux-fzf › pane" "" --no-multi) || break
        [[ "$action" == "← back" || -z "$action" ]] && break

        panes=$($TMUX_BIN list-panes -a -F '#S:#I.#P: [#{window_name}] #{pane_current_command} #{pane_width}x#{pane_height}#{?pane_active, (active),}')

        if [[ "$action" == "switch" ]]; then
            target=$(printf "%s\n← back" "$panes" | pick \
                "tmux-fzf › pane › switch" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            pane_target=$(echo "$target" | sed 's/: .*//')
            session=$(echo "$pane_target" | cut -d: -f1)
            $TMUX_BIN switch-client -t "$session" 2>/dev/null
            $TMUX_BIN select-pane -t "$pane_target"
            exit 0

        elif [[ "$action" == "kill" ]]; then
            target=$(printf "%s\n← back" "$panes" | pick \
                "tmux-fzf › pane › kill" "" -m) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            echo "$target" | while read -r line; do
                t=$(echo "$line" | sed 's/: .*//')
                $TMUX_BIN kill-pane -t "$t" 2>/dev/null
            done
            exit 0

        elif [[ "$action" == "swap" ]]; then
            target=$(printf "%s\n← back" "$panes" | pick \
                "tmux-fzf › pane › swap (from)" "" --no-multi) || continue
            [[ "$target" == "← back" || -z "$target" ]] && continue
            t1=$(echo "$target" | sed 's/: .*//')
            remaining=$(echo "$panes" | grep -v "^$t1:")
            target2=$(printf "%s\n← back" "$remaining" | pick \
                "tmux-fzf › pane › swap (to)" "" --no-multi) || continue
            [[ "$target2" == "← back" || -z "$target2" ]] && continue
            t2=$(echo "$target2" | sed 's/: .*//')
            $TMUX_BIN swap-pane -s "$t1" -t "$t2"
            exit 0
        fi
    done

# ══════════════════════════════════════════════════════════════════════
# COMMAND
# ══════════════════════════════════════════════════════════════════════
elif [[ "$category" == "command" ]]; then
    commands=$($TMUX_BIN list-commands -F '#{command_list_name}')
    target=$(printf "%s\n← back" "$commands" | pick \
        "tmux-fzf › command" "" --no-multi) || continue
    [[ "$target" == "← back" || -z "$target" ]] && continue
    printf "\033[38;2;189;147;249m tmux-fzf › command › %s\033[0m\n" "$target"
    printf "\033[1;35m:%s \033[0m" "$target"
    read -r cmd_args
    $TMUX_BIN $target $cmd_args 2>&1 || true
    exit 0

# ══════════════════════════════════════════════════════════════════════
# KEYBINDING
# ══════════════════════════════════════════════════════════════════════
elif [[ "$category" == "keybinding" ]]; then
    bindings=$($TMUX_BIN list-keys)
    selected=$(printf "%s\n← back" "$bindings" | pick \
        "tmux-fzf › keybinding" "" --no-multi) || continue
    [[ "$selected" == "← back" || -z "$selected" ]] && continue
fi

done
