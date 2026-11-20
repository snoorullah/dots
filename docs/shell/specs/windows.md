# Windows: tiling, group tabs, restore, scratchpad (board: `Windows.dc.html`)

Reads Hyprland and `dots-layout`. Changes the layout through `hyprctl`. Sends nothing.
---
## 1. Boards and data

| Part | Board state | Data | Read-only or stubbed |
|---|---|---|---|
| Tiling assistant | 6 presets, picked, "N windows... fits", Apply | tiled windows on the focused workspace; last preset per profile (`dots-layout pref`) | Apply is live; the edge-drag zones are not built |
| Group tabs | strip of the focused group, close mark, "N in group" | `lastIpcObject.grouped` of each toplevel | drag a tab out to split: not built; group membership is not restored |
| Restore prompt | 5 parts, Restore, Start clean, best-guess warning | `dots-layout status` (saved file of an earlier boot) | "Finished agents" reopens plain shells |
| Scratchpad | 5 tabs, note, 4 actions | `dots-layout note` per profile; special workspace `scratch-<profile>` | Terminal, Snippet, Math, Ask, Turn into task, Send to agent are stubs |
| Switcher parts | see section 5 | `modules/wsswitch` | see section 5 |

---
## 2. Owner decisions in force

1. Restore after login ASKS ("Restore yesterday's layout?"); never automatic.
2. Agents are saved PAUSED and come back as a shell in the same directory. Nothing resumes one.
3. Nothing leaves the machine. Notes are local files, 0600, in `~/.local/state/dots-layout/`.

---
## 3. `dots-layout` (Python, `private_bin/executable_dots-layout`)

| Command | Does |
|---|---|
| `save` | every 10 min (timer): clients (class, workspace, geometry, group, argv from `/proc`), herdr panes; skipped while a prompt is pending (first 30 min), when nothing is open, or when argv holds a key/token |
| `status` | JSON for the prompt and for "Back to last set" |
| `restore [--apply] [--parts] [--workspaces]` | plan (default) or run; apps already open are skipped; `undo` closes only what it opened |
| `startup --workspace N --name P` | argv list `P` from `~/.config/dots/startup-sets.json` |
| `note get/set/save`, `pref get/set` | scratchpad text, last tiling preset |

Launch: `hyprctl dispatch 'hl.dsp.exec_cmd([==[[workspace N silent] <shell-quoted argv>]==])'`.

---
## 4. Hyprland dispatches (Lua)

`hl.dsp.workspace.toggle_special("scratch-dev")`, `hl.dsp.group.toggle()`, `.next()`, `.prev()`,
`hl.dsp.focus({ window = "address:0x.." })` (picks a tab), `hl.dsp.layout("mfact exact 0.6")`,
`hyprctl eval 'hl.workspace_rule({ workspace = "3", layout = "master" })'` (UNVERIFIED on a live compositor).

---
## 5. Switcher parts finished here (`modules/wsswitch`)

| Part | Where | Source |
|---|---|---|
| Screen-share mask | "Masked title" on mail, chat, private and password windows; `Masked` pill | `WsSwitcher.masked` (no source sets it yet; integration binds it) |
| Working, paused | ring dot; "resumed paused" | `WsSwitcher.agentStates` (`addr -> state`) |
| `Dev?` chip | windows in Other; one click moves | app kind to profile map in `js/Model.js` |
| Launcher row | "Open ... in launcher", no-match text, Enter | `quickshell ipc -p <shellDir> call dots.launcher query <text>` |
| Back to last set, Start startup set, New workspace | tree, grid card, map | `dots-layout status`, `restore --workspaces`, `startup`; free number from `Profiles.js` |

Not built: row actions (float, pin, close).

---
## 6. Wiring still owed (not shipped until done)

1. `dots.launcher` IpcHandler with `toggle()` and `query(text)` (launcher team; add to `launcher-contract.md`). Until then Enter on the row does nothing.
2. `shell.qml`: instantiate `WindowsPopout` and `TabsOverlay`; bind `WsSwitcher.masked` and `agentStates`.
   The screen-share mask has no source: it is NOT shipped, only tested with fixtures.
3. `run_onchange_after_24-systemd.sh.tmpl`: `systemctl --user enable --now dots-layout-save.timer dots-layout-logout.service`.
   The logout unit saves with `save --force` when the graphical session stops.
4. `dots.windows` IPC target for tiling, restore, scratchpad.
