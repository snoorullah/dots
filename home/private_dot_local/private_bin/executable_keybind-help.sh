#!/usr/bin/env bash
# keybind-help.sh — a searchable, keyboard-navigable cheatsheet of every Hyprland
# keybind. Summoned by Super+Shift+/ (= "?"). Reference-only: type to filter,
# Esc/Enter to close. Hand-mirrored from ~/.config/hypr/hyprland.lua — keep in
# sync when binds change (the lua uses the caelestia hl.* plugin API, so
# `hyprctl binds` only shows opaque "__lua" callbacks, not the real commands).
set -uo pipefail

FZF="${FZF_BIN:-/fzf}"
command -v "$FZF" >/dev/null 2>&1 || FZF=fzf

# Each row: "<keys padded>  <description>". "──" rows are section headers.
read -r -d '' ROWS <<'EOF'
━━━━━━━  WINDOWS  ━━━━━━━
  Super + Return          Terminal (kitty)
  Super + Shift + Q       Close window
  Alt + F4                Close window
  Super + F               Fullscreen
  Super + Shift + Space   Toggle floating
  Super + E               Toggle split direction
  Super + B               Preselect next split → right
  Super + V               Preselect next split → down
  Super + H / J / K / L   Focus  left / down / up / right
  Super + Shift + H/J/K/L  Move window  left / down / up / right
  Super + S               Toggle group (tabbed)
  Super + Ctrl + H / L    Group: previous / next window
  Super + R               Resize mode  (H/J/K/L to size · Return/Esc exit)
  Super + LMB drag        Move window
  Super + RMB drag        Resize window
━━━━━━━  WORKSPACES  ━━━━━━━
  Super + 1 … 0           Go to workspace 1–10
  Super + Shift + 1 … 0   Move window to workspace 1–10
  Super + Scroll ↑ / ↓    Previous / next workspace
━━━━━━━  LAUNCHERS  (otter)  ━━━━━━━
  Super + D               otter-launcher — main panel
  Super + Space           Apps
  Super + Tab             Windows
  Super + Shift + S       Run a command
  Super + Shift + F       Files — file manager (yazi)
  Super + /               Workspaces menu
  Super + P               Projects
  Super + G               Git profile switcher
  Super + T               tmux sessions
  Super + Shift + O       Bookmarks
  Super + N               Obsidian search
  Super + ,               Zen browser tabs
  Super + M               Media / playerctl
  Super + Shift + M       YouTube Music
  Super + Shift + E       Power menu
  Super + Ctrl + S        System menu
  Super + C               Clipboard history (clipse)
  Super + Shift + B       Bluetooth (bluetuith)
  Super + Shift + W       Wallpaper picker
━━━━━━━  TASKS  /  ADHD  ━━━━━━━
  Super + A               Focus block — pick/add a task & start
  Super + Shift + A       Quick capture — add a task
  Super + Shift + X       Focus / salah status
  Super + Shift + Return  taskwarrior-tui (daily driver)
  Super + Shift + P       Break — pause task + lock
  Super + Shift + ;       Salah logger (one-key)
━━━━━━━  MEDIA  /  HARDWARE  ━━━━━━━
  Vol Up / Down / Mute    Volume (OSD)
  Mic Mute                Toggle microphone
  Play / Next / Prev      playerctl transport
  Brightness Up / Down    Screen brightness (OSD)
  Caps Lock               Caps-lock OSD indicator
━━━━━━━  SCREENSHOT  ━━━━━━━
  Print                   Region screenshot
  Super + Print           Full-screen screenshot
━━━━━━━  SESSION  ━━━━━━━
  Super + Escape          Lock screen (hyprlock)
  Super + I               Show / hide waybar — toggle bar (zen mode)
  Super + Shift + C / R   Reload Hyprland config
  Super + Delete          Exit Hyprland
  Super + Shift + /       This keybind menu
EOF

printf '%s\n' "$ROWS" | "$FZF" \
  --exact --reverse --no-sort --cycle --border=rounded --info=inline \
  --prompt='  keybinds  ' --pointer='▌' \
  --header='type to filter  ·  Esc to close' --header-first \
  --color='bg+:#44475a,bg:#282a36,fg:#f8f8f2,fg+:#ffffff,hl:#bd93f9,hl+:#ff79c6,pointer:#ff79c6,prompt:#8be9fd,border:#6272a4,header:#6272a4,info:#6272a4,gutter:#282a36' \
  >/dev/null 2>&1 || true
