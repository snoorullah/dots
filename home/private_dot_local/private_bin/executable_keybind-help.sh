#!/usr/bin/env bash
# keybind-help.sh — a searchable, keyboard-navigable cheatsheet of every Hyprland
# keybind. Summoned by Super+Shift+/ (= "?"). Reference-only: type to filter,
# Esc/Enter to close. Hand-mirrored from ~/.config/hypr/hyprland.lua — keep in
# sync when binds change (the lua uses the caelestia hl.* plugin API, so
# `hyprctl binds` only shows opaque "__lua" callbacks, not the real commands).
set -uo pipefail

FZF="${FZF_BIN:-fzf}"

# Each row: "<keys padded>  <description>". "──" rows are section headers.
read -r -d '' ROWS <<'EOF'
━━━━━━━  WINDOWS  ━━━━━━━
  Super + Return          Terminal (ghostty)
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
  Super + Ctrl + A/W/D/C/R/N/O  Profile: Agents/Web/Dev/Comms/Review/Notes/Other
  Super + Scroll ↑ / ↓    Previous / next workspace
━━━━━━━  LAUNCHERS  (otter)  ━━━━━━━
  Super + D               otter-launcher — main panel
  Super + Space           Launcher — apps, clipboard, files, math, emoji, hosts
  Super + Alt + Space     otter-launcher — apps (was Super + Space)
  Alt + Tab               Window switcher — hold Alt, Tab to cycle, release to pick
  Alt + Shift + Tab       Window switcher — cycle backwards
  Alt + Alt_L             Window switcher — release Alt to pick
  Super + Tab             Profiles and workspaces (switcher)
  Super + Alt + Tab       Windows
  Super + Shift + S       Run a command
  Super + Shift + F       Files — file manager (yazi)
  Super + /               Workspaces menu
  Super + P               Projects
  Super + G               Git profile switcher
  Super + T               tmux sessions
  Super + Shift + O       Bookmarks
  Super + Shift + N       Control centre — inbox tab
  Super + N               Obsidian search
  Super + ,               Zen browser tabs
  Super + M               Media / playerctl
  Super + Shift + M       YouTube Music
  Super + Shift + E       Power menu
  Super + Ctrl + S        System menu
  Super + C               Clipboard history (launcher, c: mode)
  Super + Shift + B       Bluetooth (bluetuith)
  Super + Shift + W       Wallpaper picker
━━━━━━━  TASKS  /  ADHD  ━━━━━━━
  Super + A               Focus block — pick/add a task & start
  Super + Shift + A       Quick capture — add a task
  Super + Shift + X       Focus / salah status
  Super + Shift + Return  taskwarrior-tui (daily driver)
  Super + Shift + P       Break — pause task + lock
  Super + Shift + ;       Salah logger (one-key)
  Super + Alt + D         Dose taken — start the health check-ins
  Super + Alt + M         Work mail (aerc)
  Super + Shift + U       Log untracked work (whiteboard, call) — one key, no prompt
━━━━━━━  CONTROL CENTRE  (Quickshell)  ━━━━━━━
  Super + Alt + I         Control centre — queue tab
  Super + Shift + I       Control centre — time tab
  Super + Alt + O         Overview — open / close
  Super + Alt + F         Start a focus block
  Super + Alt + J         Sidebar — open / close
  Super + Alt + K         Jump back to the last pane
  Super + Alt + S         System panel (wifi, sound, power)
  Super + Alt + N         Quick capture card
  Super + Alt + B         Back to the task after a detour
  Super + Shift + T       Lamp test — light every bar indicator for 5 s
  Super + Alt + Q         Switch shell: Quickshell ↔ Waybar
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
  Super + Escape          Away — say why, then lock (terminal picker if Quickshell is down)
  Super + Alt + E         Session menu — lock, log out, suspend, reboot, power off
  Super + Alt + W         Wallpaper picker card
  Super + Alt + L         Logo menu
  Super + Alt + T         Tiling assistant
  Super + Alt + R         Restore the saved window layout (asks first)
  Super + grave           Scratchpad note for this profile
  Super + Shift + F12     Performance mode (power profile + do-not-disturb)
  Super + I               Show / hide waybar — toggle bar (zen mode)
  Super + Shift + C / R   Reload Hyprland config
  Super + Delete          Exit Hyprland
  Super + Shift + /       This keybind menu
EOF

printf '%s\n' "$ROWS" | "$FZF" \
  --exact --reverse --no-sort --cycle --border=rounded --info=inline \
  --prompt=$'􀜌  ' --pointer='▌' \
  --header=$'􁌆  keybinds   ·   type to filter · Esc to close' --header-first \
  --color='bg+:#44475a,bg:#282a36,fg:#f8f8f2,fg+:#ffffff,hl:#bd93f9,hl+:#ff79c6,pointer:#ff79c6,prompt:#8be9fd,border:#6272a4,header:#6272a4,info:#6272a4,gutter:#282a36' \
  >/dev/null 2>&1 || true
