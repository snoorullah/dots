#!/usr/bin/env bash
# claude-notify.sh — Claude Code `Notification` hook → desktop notification
#
# Outside tmux, Ghostty turns Claude Code's terminal notifications into desktop
# ones itself. Inside tmux those escape sequences never reach Ghostty, so this
# hook calls notify-send directly, tagged with the tmux session:window.
# Clicking the notification focuses the terminal window (Hyprland: switching
# workspace if needed) and jumps the tmux client to the pane that raised it.
#
# Wire up in ~/.claude/settings.json:
#   "hooks": { "Notification": [ { "hooks": [ { "type": "command",
#     "command": "~/.config/tmux/scripts/claude-notify.sh" } ] } ] }

# Not in tmux → Ghostty already handles it; avoid duplicate notifications.
[[ -n "$TMUX" && -n "$TMUX_PANE" ]] || exit 0
command -v notify-send &>/dev/null || exit 0

icon="$(dirname "$(readlink -f "$0")")/../assets/claude.png"
[[ -f "$icon" ]] || icon=utilities-terminal

input=$(cat)
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

message=$(field .message)
title=$(field .title)
cwd=$(field .cwd)
[[ -n "$message" ]] || message="Claude needs your attention"
[[ -n "$title" ]] || title="Claude Code"

location=$(tmux display-message -p -t "$TMUX_PANE" '#S:#I #W' 2>/dev/null)
project=${cwd:+$(basename "$cwd")}

# Untrusted text (model/tool output): neutralise notification markup (&, <, >)
# and tmux format expansion (#(cmd), #{...}) before it reaches either sink.
pango_esc() { local s=$1; s=${s//&/"&amp;"}; s=${s//</"&lt;"}; s=${s//>/"&gt;"}; printf '%s' "$s"; }
tmux_message=${message//\#/##}
nl=$'\n'

summary="$(pango_esc "$title${project:+ · $project}")"
body="$(pango_esc "$message")${location:+$nl<i>tmux $(pango_esc "$location")</i>}"

# Visual cue in tmux too (shows on whichever client is viewing that session)
tmux display-message -t "$TMUX_PANE" -d 4000 "󰚩 $tmux_message" 2>/dev/null

# Pick the tmux client to jump: one already on the pane's session, else the
# most recently active one.
pick_client() {
    local session
    session=$(tmux display-message -p -t "$TMUX_PANE" '#S')
    tmux list-clients -F '#{client_activity} #{client_session} #{client_name} #{client_pid}' |
        awk -v s="$session" '{ print ($2 == s ? 1 : 0), $0 }' |
        sort -k1,1nr -k2,2nr | head -1 | awk '{ print $4, $5 }'
}

# Hyprland: focus the terminal window hosting the tmux client — this also
# switches to its workspace. Panes often carry a stale/empty
# HYPRLAND_INSTANCE_SIGNATURE, so fall back to the live socket.
focus_terminal() {
    local client_pid=$1 pid address d
    command -v hyprctl &>/dev/null || return 0
    if [[ ! -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]; then
        for d in "$XDG_RUNTIME_DIR"/hypr/*/; do
            [[ -S "$d.socket.sock" ]] && export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$d")
        done
    fi
    # Walk up from the tmux client to the process that owns a Hyprland window
    local windows
    windows=$(hyprctl clients -j 2>/dev/null) || return 0
    pid=$client_pid
    while [[ -n "$pid" && "$pid" -gt 1 ]]; do
        address=$(jq -r --argjson p "$pid" 'map(select(.pid == $p)) | .[0].address // empty' <<<"$windows")
        [[ -n "$address" ]] && break
        pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    done
    [[ -n "$address" ]] || return 0
    # Lua dispatcher (Hyprland 0.55+) first; fall back to legacy syntax
    [[ "$(hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" 2>/dev/null)" == ok ]] ||
        hyprctl dispatch focuswindow "address:$address" &>/dev/null
}

# Detach from the hook so Claude isn't blocked waiting on the click.
(
    action=$(notify-send --app-name="Claude Code" --icon="$icon" \
        --urgency=normal --expire-time=10000 \
        --action=default=Focus --wait \
        "$summary" "$body" 2>/dev/null)
    if [[ "$action" == "default" ]]; then
        read -r client client_pid < <(pick_client)
        [[ -n "$client_pid" ]] && focus_terminal "$client_pid"
        tmux switch-client ${client:+-c "$client"} -t "$TMUX_PANE" 2>/dev/null
        tmux select-window -t "$TMUX_PANE" 2>/dev/null
        tmux select-pane -t "$TMUX_PANE" 2>/dev/null
    fi
) </dev/null &>/dev/null &
disown

exit 0
