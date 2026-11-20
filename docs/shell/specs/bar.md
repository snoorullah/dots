# Bar spec

Board: `Bar.dc.html` (tokens: `Foundations.dc.html`). Code: `modules/bar/`.
Three rounded pills (40 high, ground at `alpha.panel`, hairline) on a transparent strip.

---

## 1. Structure

1. `Bar.qml`: PanelWindow, wiring only. Keeps `property var notifs`. Reads services, builds one `model`.
2. `BarView.qml`: presentation. Takes `model`, emits `toggleRequested(name, x)`, `logoClicked()`.
3. `js/BarModel.js`: all logic (ages, ordering, +n, salah runway, workspace apps, faults). qmltestrunner covers it.
4. `js/Eq.js`: equalizer bar heights from time. `IconRegistry.qml` is never instantiated (feeds the icon generator).

## 2. Elements and data

| Element | Source | Click |
|---|---|---|
| Logo (crescent, accent on raised) | static | `Ui.toggleCc()` |
| Profile icons (7, active filled) | STUB: static list, active only if the workspace name matches | none |
| Workspaces + app logos | `Hypr.workspaces`, `Hyprland.toplevels`, desktop-entry icon | `Hypr.focus(id)` |
| Task text | `Feed.task` (`ref` + `desc`), else tracker helper | none |
| Detour chip | STUB: no source, `detour` string only from fixtures | none |
| Clock, date | `SystemClock` | `calendar` |
| Salah `Isha 24m` | `waybar-salah.sh` text, runway computed | `salah` |
| Waiting symbols + age | `Feed.attentionItems`, oldest first, max 3 then `+n` | `waiting`, agent kind `agent` |
| Fault chip | `OpsState` fail, else stale (`Feed.degraded`/`OpsState.stale`) hollow `?` | `system` |
| Music, 36 bars | `Mpris.active`; hidden with no player | `media` |
| Metrics (2-3) | `Feed.today`: tasks done, worked time. PRs and XP: STUB (fixtures only) | `system` |
| Logout chip | STUB: no source | none |
| Tray | `SystemTray.items`; zero width when empty | `tray` |
| Bell + dot (no count) | `notifs` held/count/quiet | `center` |

## 3. States (one fixture each)

1. quiet: no waits, no fault. 2. waiting: three symbols with ages.
3. detour + review wait, other profile. 4. failed: red diamond + text.
5. workspace names on hover (non-active keep logos only). 6. stale: grey `?` chip.
7. paused: bars still, 0.55 opacity, song dimmed. 8. overflow: 5 waits give 3 + `+2`.

## 4. Rules

- Amber circle waiting, red diamond failed, grey `?` unknown, accent for selection. No green.
- Only equalizer bars move (20 fps timer, stopped when paused/hidden). Arrivals fade `motion.fade`.
- Bar is 48 px (pill 40 + 8) where the old bar was 30; the waybar fallback is a different height.
- Nothing is sent. Every action is a local toggle or a focus. Exec is argv only.
- The amber dot between clock and date follows the board; recommend neutral (needs approval).
