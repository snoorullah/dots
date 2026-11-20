# Profile and workspace switcher (board: `MenuWorkspaceSwitcher.dc.html`)

Shown when `Ui.open === "workspaces"`. Reads Hyprland, moves windows, sends nothing.
---
## 1. Frames

| View | Size | What |
|---|---|---|
| A pop | 360 wide | header (profile, needs badge, window count), strip of 7 profiles, workspaces with window rows |
| A full | 880x560 | filter bar, 92 px profile rail, same tree, hint footer |
| B grid | 880x560 | 4x2 profile cards; each lists its workspaces as app chips |
| C map | 880x560 | 220 px rail, workspace tabs, schematic tile map of one workspace |
| Hover | 300 wide | 150 ms preview of a profile's workspaces as app chips |

States: default, hover, filter, move (toast + undo), empty, needs, salah, error, locked.

## 2. Data

1. Profiles and their workspaces: `modules/bar/js/Profiles.js` (`list`, `profileOf`, `primary`).
2. Windows and workspaces: `Quickshell.Hyprland` (`toplevels`, `workspaces`, `focusedWorkspace`).
3. A workspace with `urgent` counts as one "needs you" in its profile.
4. Salah: `SalahSource` window open dims every profile but the active one.
5. Locked: shows one line, no profile or window name.

## 3. Actions (Hyprland 0.56 Lua, via `hyprctl dispatch`, argv only)

| Action | Dispatch |
|---|---|
| Focus workspace | `hl.dsp.focus({ workspace = "N" })` |
| Focus window | `hl.dsp.focus({ window = "address:0x.." })` |
| Move window | `hl.dsp.window.move({ workspace = "N", follow = bool })` |
| Move a selected window | `--batch` of the focus then the move |

A reply other than `ok` shows the error row with Retry. Undo moves the window back.

## 4. Keyboard

| Key | Does |
|---|---|
| Left Right, h l | previous / next profile |
| Down Up, j k | window in the profile (grid: row of cards) |
| Enter | focus the window, else the profile's workspace |
| Shift+Enter | move the focused or selected window to the profile, follow it |
| Shift+1..7 | move to that profile; 1..7 alone picks it |
| Tab, / | next view; filter |
| Esc | clear filter, then `Ui.close()` |

## 5. Out of scope (needs your approval)

Fidelity gaps against the board. Each is a decision, not an oversight.

| Gap | Board shows |
|---|---|
| Screen-share mask toggle | "Masked title" on sensitive windows |
| Window states | "working" and "paused" |
| Suggest chip | "Dev?" on Other windows |
| Launcher row | "Open <query> in launcher"; no-match text says Enter opens it |
| Set buttons | "New workspace", "Start startup set" |
| Session | "Back to last set" |
| Row actions | float, pin, close |

Also left out:

Tiling assistant, grouped tabs, scratchpad, new named workspaces.
No window titles when locked. No green. No pulsing.

---
## 6. Wiring (outside this module, required follow-ups)

1. `shell.qml`: `import "modules/wsswitch"` and `WsSwitcher {}`.
2. `modules/bar/Bar.qml:136`, `Profiles.qml`: click calls `Ui.toggle("workspaces", screen, x)`.
3. `shell.qml` IPC handler `toggle workspaces`; `hyprland.lua.tmpl:296` Super+Tab runs `qs ipc call ...`.
4. `services/Ui.qml`: add `workspaces` to the popout-name comment.
