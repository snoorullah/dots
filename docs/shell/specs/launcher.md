# Launcher core (board `Launcher`)

Shown when `Ui.open === "launcher"`. Owner decision: Super+Space opens it, otter-launcher moves to Super+Alt+Space.
**Not wired yet**: see section 6.
Contract: `launcher-contract.md`. Modes by the modes team: `launcher-modes.md`. Tests: `tests/launcher-ui.sh`.
## 1. Board states

| State | What |
|---|---|
| Frame | 1080 x 620 card, radius 20: search row 56, chips 40, results 5fr / preview 6fr, footer 32 |
| All, empty | Recents: last 8 activated, never from a `sensitive` provider |
| All, typing | merged rows, each provider capped at `allLimit`, ranked, rows appear as each answers |
| Mode | prefix typed (`c:` `>` `=` ...) moves into an accent chip; Backspace on empty returns to All |
| Row | icon, title, sub; selected = fg at `alpha.hover`; optional group, indent, chips |
| Preview | head 20 px (or font name at 36 px), body, image, snippet fields; actions at the bottom |
| Confirm | card over the body; Enter confirms and calls `activate` again; Esc cancels |
| Closed | locked or Salah: one icon, one line, providers not queried |
| Error / empty | one error row; empty list shows the provider `hint` |

## 2. Data per element

| Element | Source |
|---|---|
| Rows, preview, actions | provider `rows` (Provider.qml); the core only draws them |
| Chips | static ordered `providers` list in `Launcher.qml`; All-only providers have no chip |
| Recents | `js/launcher_recents.py` (`~/.local/state/dots-launcher/recents.json`, 0600) |
| Apps | Quickshell `DesktopEntries`; launch = `dots-launch <id>` |
| Commands | `js/launcher_cmds.py`, `~/.config/dots-launcher/commands.json`; Run = new herdr pane |
| Math | `js/launcher_math.py` (own evaluator, `qalc` fallback if installed) |
| Clipboard | `~/.local/bin/dots-clip`: Fernet file, key 0600 in `~/.local/state/dots-clip` |

## 3. Keys (core owns the field)

`Tab` / `Shift+Tab` mode, `Ctrl+N/P` or arrows move, `Enter` action 0, `Ctrl+1..9` action n-1,
`Ctrl+J/K` pick the secondary, `Ctrl+Enter` runs it, `Esc` card, then field, then window.

## 4. Clipboard rules (owner decision 4)

1. Encrypted at rest; decrypted only in memory and in a 0700 runtime dir for image previews.
2. Skipped: sensitive MIME hints (`x-kde-passwordManagerHint`, concealed, sensitive, keepass, 1password).
3. Skipped: secret patterns (the old `dots-clip-store` list); also cleared from the live clipboard after 30 s.
4. Unpinned items are dropped at logout (`dots-clip clear` from a user unit `ExecStop`: **to be added**, section 6); pins stay.
5. Never in All, never in Recents; previews purged when the launcher closes.

## 5. Read-only or stubbed

1. Paste copies to the clipboard and says "Press Ctrl+V"; typing into the old window needs `wtype` (not done).
2. Run in pane splits the focused herdr pane (down); `<placeholder>` commands are typed, not submitted.
3. Nothing is sent; no network. All exec is argv.
4. The busy indicator is a static "Searching" note (nothing pulses).

## 6. Handoff (integration must add; none of this exists yet)

1. **Reach**: instantiate `Launcher {}` in `shell.qml`.
2. **Keys**: Super+Space sets `Ui.open = "launcher"`; move otter to Super+Alt+Space (`hyprland.lua.tmpl`).
3. **Prefix opens**: a surface that opens with a prefix sets `startMode` (e.g. `"c:"`).
4. **Clipboard unit**: add `dots-clip.service` (user): `ExecStart` x2 = `wl-paste --type text --watch %h/.local/bin/dots-clip store` and `wl-paste --type image/png --watch %h/.local/bin/dots-clip store --image`; `ExecStop=%h/.local/bin/dots-clip clear`.
5. **Autostart**: replace the `dots-clip-store` line (`hyprland.lua.tmpl` ~265) with `systemctl --user start dots-clip`. Until then history stays empty and nothing clears at logout.
6.5 **Open design call (owner)**: 12 chips need ~1300 px, card is 1080, `ModeTabs` is a plain `Row`.
Options: `Flickable` scrolling the active chip in, or icon-only past the 7th. Not applied; then add a 12-provider scene probe (chip right edge <= card - 10).
