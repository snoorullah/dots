# Menus spec (boards: `MenuWindowSwitcher`, `MenuWallpaperPicker`, `MenuLogoMenu`)

Surfaces `winswitch`, `wallpaper`, `logomenu` (`Ui.open` names). Nothing leaves the machine.
Each module: `js/` pure model (qmltestrunner), `py/` helpers (unittest, fake binaries), `*Ctl.qml`
behaviour (smoke-loaded offscreen), thin layer-shell window, `*Panel.qml` presentation.
---
## 1. Window switcher (`modules/winswitch`)

| Element | Source |
|---|---|
| Cards, order | `Hyprland.toplevels`; own MRU list (`activeToplevel`), seeded from `focusHistoryID` |
| App glyph, kind | `wsswitch/js/Model.js appOf(class)`; card art is schematic bars, never a capture |
| Profile chip | `bar/js/Profiles.js profileOf(workspace)` |
| Ticket chip, P / U | `py/pins.py` (`$XDG_STATE_HOME/dots-winswitch`), local; current ticket file, no default |
| Scopes `` ` `` `1` `2` `3` | Task (pinned first), Workspace, Profile, All; scratchpad and minimized last |
| Filter | `/` or any other letter; title, tabs, app, ticket, profile; hits kept in view |
| W close, M scratchpad | `hyprctl` argv (focus, then `window.close()` / move to `special:scratchpad`) |
| Close undo | the close is held 8 s, then dispatched; mail and chat need W twice |
| `?` question | `py/rank.py`: `llm`, titles only, 1.5 s, fuzzy fallback; ranks, never selects |

1. Binds call `next()`, `prev()`, `release()` (Alt up). Release inside 150 ms = quick flip, nothing drawn.
2. Held: strip opens and takes the keyboard; Alt up commits, Esc cancels, Down/Up open/close a tab group.
3. **Lock-safe:** `pidof hyprlock` is probed on each press; locked = inert (no window, no grab, no
   card built, so no title exists to draw). `unlocked()` (hypridle `unlock_cmd`) shows app names only for 2 s.
4. Stub: browser tab lists (a window carries `tabs` or no group), ticket default, "lock armed" signal.
   Layouts strip, list, grid are built; the choice has no UI control yet (`st.layout`).

## 2. Wallpaper picker (`modules/wallpaper`)

| Element | Source |
|---|---|
| Grid, count, skipped | `py/wp.py scan` (`WALLPAPER_DIR`, saved folder, `~/walls`), recursive, magic-byte check |
| Palette, contrast, tuned | `py/wp.py palette`: matugen `--dry-run` as `dots-theme` calls it, AA 4.5 text fit |
| Accent, warn, fail | `Theme` (dots-theme fixes them in both modes); only surface and text follow the image |
| Set Enter / Space | `py/wp.py apply`: `swww img`, `~/.cache/current-wallpaper`, `dots-theme wallpaper PATH` |
| Palette 1 / 2 / 3 | wallpaper runs `dots-theme`; current and mode change the image only; salah holds it |
| Apply to M | `swww img -o OUTPUT` (all, or one display) |
| Lock L | symlink `~/.cache/dots-lock-wallpaper` (STUB: no consumer yet, see item 4) |
| F, G, S N R | `fav`, `folder` (path prompt in the search box), `shuffle-tick` hourly, held by salah / focus |

1. Arrows preview in the card; the desktop follows after 350 ms (`swww`, no cache, no theme); Esc restores.
2. Enter sets and closes; Space sets and stays with a 10 s Undo (`revert`). Unreadable files are listed, never fail the scan.
3. Stub: suggestion tile (set by the caller, no model), tags are computed not modelled, focus-mode signal,
   the display chips (the M key and the bottom button cycle), the two-display mirror.
4. Stub: lock wallpaper. Nothing reads the link; `hyprlock.conf.tmpl` still uses `path = screenshot`.
   Follow-up for integration or lock unit: hyprlock background reads `~/.cache/dots-lock-wallpaper`
   when it exists, else falls back to `screenshot`.

## 3. Logo menu (`modules/logomenu`)

1. GO rows: `Ui.toggleCc` / `toggleSidebar`, others `qs ipc call dots.<target> toggle` (targets are integration's).
2. MODE chips: `py/recover.py mode` (`$XDG_STATE_HOME/dots-mode`); Salah (from `SalahSource`) wins and locks them.
3. FIX THE SHELL, local argv via `py/recover.py`, started detached: reload shell = `quickshell kill` then
   `dots-shell start`; reload Hyprland = `hyprctl reload`; safe mode = `dots-shell use waybar`;
   back = `dots-shell use quickshell`; log = `quickshell log` in ghostty.
4. SESSION: Lock = `loginctl lock-session`; Logout = 3 s inline countdown, Esc or Cancel stops it, then
   `loginctl terminate-session`. Salah dims Logout. No task name appears anywhere.
5. Left out vs the board: Restart bar and Restart notifications (one process, so Reload shell covers both).
6. Degraded and safe headers come from `health` (no detector yet). Row cap 17, asserted.
7. Open: bar logo right-click, hold 450 ms, `Super+Shift+Space` (`Ui.toggle("logomenu", screen, x)`).
