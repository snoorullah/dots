# System panel spec (boards: `System.dc.html`, `SystemMenus.dc.html`)

Replaces `modules/quick` later. Shown when `Ui.open === "system"`. Nothing is sent.
---
## 1. What the boards show

| Element | Board detail |
|---|---|
| Header | `up Nh · <host>`, gear button, red power button |
| Meters | three 30 px pills: brightness, volume, mic (click or drag) |
| Tiles | 2-col, 48 px, split: main toggles, 32 px arrow opens the menu |
| Media row | art disc, title, artist, prev / play-pause / next |
| Log | `NOTIFICATIONS, N LOGGED`, last four |
| Menu card | icon, name, back; rows: head toggle item choice slider actions note swatches monitors |
| Session | 6 buttons (lock, log out, suspend, reboot, shut down, back up then shut down) |
| Right-click | window menu and desktop menu (component only) |
| Media card | 440x160 art, title, progress, controls (component only) |

## 2. States

1. Tile on = accent fill, off = faint wash. Arrow opens the menu, right-click too.
2. Menu open replaces the quick view in the same popout; back returns.
3. No service data = tile off with a plain sub label, never a fake value.
4. Danger (power, close, shut down) uses `Theme.color.failed`. No green.
5. Menu swap fades over `motion.fade`; nothing pulses.

## 3. Data per element

| Element | Source |
|---|---|
| Wi-Fi tile, toggle | `Net.wifi`, `Net.setWifi`; list from `nmcli -t dev wifi list` |
| Bluetooth | `Bt.powered`, `Bt.setPowered`; devices from the adapter |
| Quiet | `notifs.dnd` when a NotifServer is passed |
| VPN | `nmcli -t connection show --active` (type vpn or wireguard) |
| Tailscale | `tailscale status --json`; absent binary = "not installed" |
| Mic | `wpctl get-volume @DEFAULT_AUDIO_SOURCE@`, `wpctl set-mute` |
| Night light | `NightLight.on/available/kelvin`, `NightLight.toggle` |
| Stay awake | `Caffeine.on`, `Caffeine.toggle` |
| Performance | `powerprofilesctl get`; set via `dots-ops perf-mode on/off`, `powerprofilesctl set power-saver` |
| Theme | `Theme.source`; `dots-theme wallpaper` / `dots-theme preset` |
| Volume, brightness | `Audio`, `Brightness` |
| Media | `Mpris.active` |
| Session | `loginctl lock-session`, `loginctl terminate-session`, `systemctl suspend/reboot/poweroff` |
| Uptime | `/proc/uptime` via `cat` argv |

## 4. Stubbed or read-only

1. **Password prompt**: out of scope, not built.
2. Rows with no local backend render disabled, tooltip `not wired yet`.
3. Anything that would send or write remotely (send screenshot to agent): disabled, `read-only for now`.
4. Light and follow-time theme, back up then shut down, pairing, join network, QR: disabled.
5. A blocked session (long job) greys reboot, log out, shut down and says why.
6. Right-click menu and media card are components; placing them is integration.

## 5. Logic and tests

- `js/Parse.js`: parsers and formatters, pure, `tst/tst_parse.qml`.
- `js/Menus.js`: board data model and argv builders, pure, `tst/tst_menus.qml`.
- QML only draws the model and emits `activated(act)`; `SystemPanel` maps acts to services or argv.
- `tests/system-ui.sh`: qmllint, qmltestrunner, offscreen PNG per board state, geometry probes.
