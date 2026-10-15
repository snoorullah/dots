#!/usr/bin/env bash
# herdr-keys.sh — searchable cheatsheet of every active herdr keybinding, built live
# from ~/.config/herdr/config.toml: built-in actions (your overrides plus the defaults
# you left alone), custom popups and plugin actions. Type to filter, Esc/Enter to close.
# Bound to prefix+K in herdr (tmux K = tmux-fzf's keybinding list).
set -uo pipefail

CONFIG="${HERDR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}"
FZF="${FZF_BIN:-fzf}"

# Plugin action titles ("<plugin>.<action>\t<title>"), if herdr is reachable.
titles=$(timeout 5 herdr plugin action list 2>/dev/null | python3 -c '
import json, sys
try:
    for a in json.load(sys.stdin)["result"]["actions"]:
        print("%s.%s\t%s" % (a["plugin_id"], a["action_id"], a.get("title", "")))
except Exception:
    pass')

rows=$(TITLES="$titles" python3 - "$CONFIG" <<'EOF'
import os, re, sys, tomllib

NAMES = {
    "help": "Help", "settings": "Settings", "detach": "Detach", "reload_config": "Reload config",
    "open_notification_target": "Open notification target", "workspace_picker": "Workspace picker",
    "goto": "Go to tab / pane / agent", "new_workspace": "New workspace", "new_worktree": "New worktree",
    "open_worktree": "Open worktree", "remove_worktree": "Remove worktree",
    "rename_workspace": "Rename workspace", "close_workspace": "Close workspace",
    "previous_workspace": "Previous workspace", "next_workspace": "Next workspace",
    "previous_agent": "Previous agent", "next_agent": "Next agent", "focus_agent": "Focus agent N",
    "remote_image_paste": "Paste image (remote)", "new_tab": "New tab", "rename_tab": "Rename tab",
    "previous_tab": "Previous tab", "next_tab": "Next tab", "move_tab_previous": "Move tab left",
    "move_tab_next": "Move tab right", "switch_tab": "Switch to tab N", "switch_workspace": "Switch to workspace N",
    "close_tab": "Close tab", "rename_pane": "Rename pane", "edit_scrollback": "Scrollback in editor",
    "clear_pane": "Clear pane", "focus_pane_left": "Focus pane left", "focus_pane_down": "Focus pane down",
    "focus_pane_up": "Focus pane up", "focus_pane_right": "Focus pane right",
    "cycle_pane_next": "Next pane", "cycle_pane_previous": "Previous pane", "last_pane": "Last pane",
    "split_vertical": "Split side by side", "split_horizontal": "Split stacked", "close_pane": "Close pane",
    "zoom": "Zoom pane", "resize_mode": "Resize mode", "resize_pane_left": "Resize pane left",
    "resize_pane_down": "Resize pane down", "resize_pane_up": "Resize pane up",
    "resize_pane_right": "Resize pane right", "toggle_sidebar": "Toggle sidebar",
    "navigate_workspace_up": "Navigate: workspace up", "navigate_workspace_down": "Navigate: workspace down",
    "navigate_pane_left": "Navigate: pane left", "navigate_pane_down": "Navigate: pane down",
    "navigate_pane_up": "Navigate: pane up", "navigate_pane_right": "Navigate: pane right",
}
titles = dict(l.split("\t", 1) for l in os.environ.get("TITLES", "").splitlines() if "\t" in l)
text = open(sys.argv[1]).read()
cfg = tomllib.loads(text).get("keys", {})
prefix = cfg.get("prefix", "ctrl+b")

# Inline "# comment" per action line and per keys.command key line, from the raw text.
in_keys, notes, key_notes = False, {}, {}
for line in text.splitlines():
    if line.startswith("["):
        in_keys = line.strip() in ("[keys]", "[[keys.command]]")
        continue
    m = re.match(r'^(#\s*)?([a-z_]+)\s*=\s*(\[[^\]]*\]|"[^"]*")\s*(?:#\s*(.*))?$', line)
    if not (in_keys and m):
        continue
    commented, name, val, note = m.groups()
    if name == "key" and not commented:
        key_notes[tomllib.loads(f"v = {val}")["v"]] = note or ""
    elif commented and name not in cfg and name in NAMES:          # a default you left alone
        default = tomllib.loads(f"v = {val}")["v"]
        if default:
            cfg.setdefault("_defaults", {})[name] = default
    elif not commented:
        notes[name] = note or ""

def show(k):
    k = k.replace("prefix+", "prefix ")
    return k

rows = []
for name, title in NAMES.items():
    if name in cfg:
        val, tag = cfg[name], "set"
    elif name in cfg.get("_defaults", {}):
        val, tag = cfg["_defaults"][name], "default"
    else:
        continue
    for k in (val if isinstance(val, list) else [val]):
        if k:
            desc = title + (f"   · {notes[name]}" if notes.get(name) else "")
            rows.append(("herdr", show(k), desc))
for c in cfg.get("command", []):
    k, note = c["key"], key_notes.get(c["key"], "")
    if c.get("type") == "plugin_action":
        desc = titles.get(c["command"], c["command"])
        grp = "plugin"
    else:
        desc, grp = f'{c.get("type", "shell")}: {c["command"]}', "custom"
    rows.append((grp, show(k), desc + (f"   · {note}" if note else "")))

print(f"  prefix = {prefix}")
for grp in ("herdr", "custom", "plugin"):
    for g, k, d in sorted(r for r in rows if r[0] == grp):
        print(f"  {grp:<7} {k:<24} {d}")
EOF
)

printf '%s\n' "$rows" | "$FZF" --no-sort --layout=reverse --header-lines=1 \
  --prompt='keys > ' --header='herdr keybindings · type to filter · Esc/Enter to close' \
  --color='header:italic' --bind 'enter:abort' >/dev/null
exit 0
