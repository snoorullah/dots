# Quickshell shell (qs-dots)

A small desktop shell for Hyprland: bar, notifications, OSD, media, quick panel,
calendar. It stands beside waybar, never on top of it.

> `dots-shell use quickshell` and `dots-shell use waybar` are the whole switch.

---

## 1. The switch

| command | does |
|---|---|
| `dots-shell status` | prints `waybar` or `quickshell` |
| `dots-shell use quickshell` | stops waybar, swaync, swayosd; starts the shell |
| `dots-shell use waybar` | the reverse |
| `dots-shell toggle` | flips (Super+Alt+Q) |
| `dots-shell start` | what Hyprland autostart runs |

The choice lives in `~/.local/state/dots-shell/active`. Default is `waybar`.
No systemd, no `chezmoi apply`, reversible in one command.

Why both cannot run: Quickshell's server and swaync both want
`org.freedesktop.Notifications`. The shell asks the bus first and, if another daemon
owns it, logs one line and stays out. The bell then shows a hollow `?`.

---

## 2. What is on screen

```
left   [workspaces]
centre [clock · salah]
right  [attn · tracking · ops · ctx · caffeine · bell · volume · tray]
```

Nominal means zero width, not dim. On a quiet machine the right slab is volume
and tray only.

| rule | how it shows |
|---|---|
| two accents | amber = someone waits or a state I hold open; red = failed |
| onset, not recolour | a chip grows from width 0 over `motion.base`; nothing pulses |
| stale source | a hollow `?` at `fgFaint`, never a spinner |
| hover | a neutral lift, never a colour |
| height | `30`, identical to waybar, so the switch shifts nothing |

---

## 3. Keybind twins

A zero-width chip has no click target, so each conditional one has a call.

| surface | twin |
|---|---|
| lamp test (everything lit 1.2 s) | Super+Shift+T, `qs ipc call dots.bar lamp` |
| calendar | `qs ipc call dots.bar calendar` |
| media | `qs ipc call dots.bar media` |
| caffeine | `qs ipc call dots.bar caffeine` |
| ctx | `qs ipc call dots.bar ctx` |
| quick panel | `qs ipc call dots.quick toggle` |
| notifications, DND | `qs ipc call dots.notif toggle` / `dnd` |
| overview | Super+Alt+I, `qs ipc call dots.overview toggle` |
| ops | `dots-ops status` |

> Super+I is still the zen-bar toggle (waybar). The build spec called it free; it was not.

---

## 4. Theme

`dots-theme` is the only writer of `~/.local/state/dots-theme/tokens.json`.

| command | does |
|---|---|
| `dots-theme preset` | fixed palette from `.chezmoidata/palette.yaml` (default) |
| `dots-theme wallpaper [PATH]` | matugen on the wallpaper, same keys |
| `dots-theme wallpaper --recolour` | gowall fits the wallpaper to the palette first |
| `dots-theme emit` | re-renders the hypr, ghostty, swaync, hyprlock colour files |

Status colours (amber, red, green) stay on the preset in both modes.
Waybar's CSS is templated from the palette and never reads a generated file.
The shell follows `tokens.json` live; before the file exists it uses built-in
defaults and retries every 3 s until it appears.

`emit` writes files nothing includes yet:
`~/.config/hypr/colors.conf`, `~/.config/ghostty/dots-theme.conf`,
`~/.config/swaync/dots-theme.css`, `~/.config/hypr/hyprlock-colors.conf`.
Wiring them in is a separate, visible change.

---

## 5. Tests

| script | proves |
|---|---|
| `tests/theme.sh` | both producers emit schema-valid tokens with one key set |
| `tests/shell.sh` | lint, hyprland config, `dots-shell`, then the live shell |
| `tests/qs-harness.sh` | the headless recipe the above use |
| `tests/pixel.py` | pixel assertions, shared with the overview UI |

`tests/shell.sh` needs `quickshell`, `qmllint` (Qt 6), `Hyprland`, `grim` and
`magick`. Missing tools print `SKIP`. `QS_IDLE_SECS=10` shortens the idle window.

The harness runs a private Hyprland and a private session bus, so it never
touches the live notification daemon. Never run it on the live bus.

---

## 6. Findings worth keeping

1. `hyprctl eval 'hl.dsp.focus(...)'` builds a dispatcher and does nothing.
   `hyprctl dispatch 'hl.dsp.focus({ workspace = "4" })'` switches. The shell uses that.
2. An IPC function named `show` is unreachable with arguments: the CLI reads
   `ipc call t show x` as its own `ipc show`. The OSD call is `display`.
3. matugen 4 nests roles as `colors.<role>.dark.color` and refuses a multi-colour
   image without `--prefer`.
4. An unmapped layer window is never polished, so a `Column` inside it never learns
   its height. The toast stack lays itself out by hand.
5. `qmllint` cannot resolve a few Quickshell types. Each false positive carries an
   inline `qmllint disable`; the suite passes `--uncreatable-type disable
   --signal-handler-parameters disable` for the other two.
6. `(gl quickshell)` is in `nix/home.nix` as the spec asks. It was not run on the
   nvidia machine: the harness used nixpkgs' plain build on the software renderer.
