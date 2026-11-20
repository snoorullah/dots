# barpop: the five bar popups

Boards: `MenuBarCalendar`, `MenuBarSalah`, `MenuBarWaiting`, `MenuAgentPopup`, `MenuTrayMenu`.
Each is a `common/Popout` shown when `Ui.open` equals its name, hung from `Ui.anchorX` on `Ui.screenName`.
Panel bodies (`*Panel.qml`) take one `model` and render it; `*Popout.qml` wires data to model.
Logic lives in `modules/barpop/js/*.js` and `modules/calendar/js/Cal.js` (qmltestrunner tests).

## 1. Surfaces

| Name | Component | Board shows | Data source |
|---|---|---|---|
| `calendar` | `calendar/CalendarPopout` | clock, NEXT strip, day timeline, week strip, month view | `calendar.json` (optional), prayer file |
| `salah` | `barpop/SalahPopout` | date, NEXT/NOW hero + bar, 5 prayer rows, sunrise rule | `~/.config/adhd/prayer-times.conf` |
| `waiting` | `barpop/WaitingPopout` | kind chips, triage rows (max 6), banner, footer | `Feed.attDoc` (attention.json) |
| `agent` | `barpop/AgentPopout` | NEEDS YOU cards, running, paused, done, budget | attention items `src=herdr`, `agents.json` (optional) |
| `tray` | `barpop/TrayPopout` | filter, grouped app rows, drill into menu | `Quickshell.Services.SystemTray` |

## 2. States rendered

1. **salah** normal, within 15 min (amber), window open (NOW), Friday (Jumuah), stale file (cached).
2. **waiting** default, problem first, empty, stale sources, focused row with actions.
3. **agent** needs-you cards + running, quiet (nothing needs you).
4. **tray** list, drill-in menu, empty.
5. **calendar** default, meeting soon (amber), prayer window, stale, free day, month view.

## 3. Data contracts

1. `prayer-times.conf` lines: `Fajr 05:32  # adhan 05:12 · adhan+20m · ends 06:31`. Header `# auto-generated YYYY-MM-DD`.
   Row time = adhan, `+N` = iqamah offset. NOW = adhan until iqamah + 15 min. File dated before today = cached.
2. Waiting rows: attention items with `waiting` or `kind=alert`; `task` items are not waiting.
   Chip kind: `mail`, `dm` chat, `src=herdr` agent, `alert` problem, rest unfiled (All only).
   Order: problems, red chips (age at least 1.5x rule), amber, oldest first. Rule by urgency 0/60/120/240 min.
3. `agents.json` (proposed, no writer yet): `{v:1, ts, running:[{name,task,elapsedSec,progress}], paused:[{name,why}], done:[str], budget:{used,cap}}`. Absent = sections hidden.
4. `calendar.json` (proposed, no writer yet): `{v:1, ts, events:[{id,date,start,end,title,link,worked,held}]}`. Absent = "Nothing scheduled", prayers still shown.
5. Both optional files live next to `attention.json` (`Feed.dir`).

## 4. Read-only stubs

Rendered, disabled, tooltip `read-only for now`:
Approve once, Deny, Answer, Approve all (agent). Draft, Snooze, Done (waiting). Add event, Open calendar (calendar).
Salah mode, Snooze, Tomorrow, settings gear (salah). No prayer logging, by the board.
Tray: Hide, Pin (no persisted rules yet).

## 5. Local actions that are live

1. Waiting/agent row `Jump`: `dots-jump <ref>` via `Actions.jump` (argv).
2. Waiting `Open`: `xdg-open <https url>` argv, https only.
3. Waiting footer `N more, open sidebar`: `Ui.toggleSidebar()`.
4. Tray row click: `item.activate()`; chevron drills into `QsMenuOpener`; menu entry `triggered()`.
5. Tray open window: `item.secondaryActivate()` stays unused.

## 6. Rules

1. Colours only from `Theme.color.*`; status: amber circle waiting, red diamond failed, grey question unknown, accent for selection, no green.
2. Open slides over `Theme.motion.base` with no bounce (`Popout`); nothing pulses.
3. Nothing is sent. No mail, Slack, ERP or GitHub write from any path. ERP is read-only.
4. Exec is argv arrays only.
5. Deviations from the boards: `Popout` pads 16 px, so card insets differ; no Hijri date (no calendar maths source); no keyboard map yet; AI lines omitted (off by default on the boards).
