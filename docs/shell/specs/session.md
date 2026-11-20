# Session spec (boards: `System.dc.html` session and password cards, `ExpStartReturn.dc.html` step-out and return rows, `Lock.dc.html` footer)

Away picker, session menu, polkit prompt. Nothing is sent. Code: `modules/session/`.
---
## 1. What the boards show

| Element | Board detail |
|---|---|
| Lock footer | `Super+Esc step out`, `Super+L lock` (hyprlock draws it; this team owns the key's target) |
| Away picker | six choices, salah first near an iqamah, Enter takes the first, Esc cancels |
| Return rows | `WHILE YOU WERE AWAY`: Declared or Detected, Agent (amber), Mail |
| Session card | 360 wide, caption `SESSION`, 2-col grid of six 58 px buttons, blocked note below |
| Password card | caption `PASSWORD NEEDED`, title, asked-by, field, Allow (accent) and Deny |

## 2. States

1. Picker: rows idle, one selected (accent wash), salah-first, empty-prayer.
2. Session: all live, or blocked (reboot, log out, shut down grey, note says why).
3. Back up then shut down: disabled with a plain reason, never a fake action.
4. Password: idle, wrong password (error line), agent-flagged (Deny is focused).
5. Return rows: declared (`Lunch break, set by you`) or detected (`Idle, no input`).
6. Danger (shut down, Deny of an agent) uses `Theme.color.failed`. No green. Nothing pulses.

## 3. Data per element

| Element | Source |
|---|---|
| Picker rows | `py/session.py choices` (keys fixed to `timetrack/away.py` CHOICES) |
| Salah label | `timetrack away --prayer` |
| Picking | `py/session.py declare KEY`: `timetrack away --declare KEY`, then `loginctl lock-session` |
| Declare failure | `notify-send`, lock anyway (same as `executable_timetrack-away-pick`) |
| Lock, log out | `loginctl lock-session`, `loginctl terminate-session <id>` |
| Suspend, reboot, off | `systemctl suspend`, `reboot`, `poweroff` |
| Blocked note | `py/session.py blocker`: `herdr pane list` + `herdr pane process-info` |
| Declared row | `away-intent.json` (read only, same file the lock label reads) |
| Password prompt | `Quickshell.Services.Polkit` `PolkitAgent` (exists in quickshell 0.3.1) |

## 4. Read-only, stubbed, gaps

1. Picker never invents a data path: only the two argv above.
2. Esc in the picker locks nothing and records nothing.
3. Log out in the menu ends the session; the day-end record is clockd's, not written here.
4. `Back up, then shut down`: no backup command exists, disabled `no backup command yet`.
5. Polkit "asked by command" and "from pane N" are not in the polkit API: the card shows the
   action message and id; the agent hint uses herdr (an agent pane is working), else is hidden.
6. Return rows: Agent and Mail come in as props (no source owned here), hidden when absent.
7. Shell, hyprlock and keybind wiring belong to integration (see result `wiring`).

## 5. Logic and tests

- `py/session.py`: choices, declare, blocker. `tst/test_session.py` (unittest, fake binaries on PATH).
- `js/Session.js`: icon and key-hint model, session buttons, text. `tst/tst_session.qml`.
- QML draws and emits; `AwayPicker`, `SessionMenu`, `PolkitPrompt` hold the Process and agent objects.
- `tests/session-ui.sh`: unittest, qmltestrunner, qmllint, static rules, offscreen PNG per state, probes.

Blocker check: pending until `session.py blocker` finishes (2 s per herdr call, 5 s overall).
Log out, Reboot, Shut down and Back up stay off with "Checking running commands...".
If herdr cannot be read the result is `unchecked`: buttons go live and the card says so.
