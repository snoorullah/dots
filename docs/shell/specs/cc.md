# Spec: control centre (`modules/cc`)

Board: `Main.dc.html`, full screen. Shown while `Ui.cc`; tab is `Ui.ccTab`; `Esc` calls `Ui.toggleCc()`.

## 1. Layout (all sizes from the board)

| Region | Size | Content |
|---|---|---|
| Header | 72 px | logo, `NOW` task, Back to task `Esc`, Logout in, level bar |
| Nav | 208 px | tabs Queue, Inbox, Agents, Tasks, Time; SAVED VIEWS; SOURCES |
| Queue and Inbox | flex + 500 px detail | filter chips, Group by, sections, detail with actions |
| Agents, Tasks, Time | flex | table or card grid |
| Footer | 40 px | status line, Undo, key hints |

## 2. Queue and Inbox

- Sections, fixed order: `WAITING ON YOU`, `TODAY`, `WHILE YOU WERE AWAY`, `FROM YESTERDAY`.
- Group by `Urgency` (sections), `Source`, `Person`. Filter chips: All, Agent, Slack, Mail, GitHub, ERP, Alert.
- Row: age, status mark (amber circle waiting, red diamond failed), title, who and sub, source.
- Inbox is the queue minus Agent items. Selected row uses the raised surface, never green.
- Detail: source line, title, body, Related, meta line, actions, then a compose panel.

## 3. Data (read-only, from `modules/overview/Feed.qml`)

| Element | Source file and field |
|---|---|
| Queue items | `attention.json` items (kind `task` and `mail` excluded) |
| Item kind | feed kind: blocker=agent, review=pr, alert=alert, dm=msg, erp=ticket, untracked=capture |
| Tone | waiting=amber; alert nobody waits on=failed; else none |
| Section | waiting or failed: WAITING; age >= 24 h: YESTERDAY; arrived before `now.json` clock `sinceTs`: AWAY; else TODAY |
| NOW header, Tasks `NOW` | `now.json` task, focus |
| Tasks `Today, in order` | `attention.json` items of kind `task` |
| Agents rows | blocker items, `now.json` agent, `activity.json` today byAgent |
| Time cards, Where time went | `activity.json` buckets today, week, month, quarter |
| Heatmap, Done today | `heatmap.json`, `mirror.json` closedAt and reviewedAt |
| Sources list | `attention.json` sources states |

## 4. Actions

| Action | Kind | Behaviour |
|---|---|---|
| Open, Open review, Open pane, Jump, See analysis | local | `dots-jump` or `xdg-open`, argv only |
| Break down and start | local | `dots-overview breakdown <ref> --start` |
| Queue, Snooze, Dismiss, Remind | local | hide for this session, Undo restores; nothing is stored |
| Focus Stop, Break, Run report | local | `dots-overview focus` or `report` |
| Allow once, Deny, Reply, Send to agent, Comment, Draft reply, Make a task, Fix in repo, Send, Hand to agent | read-only stub | rendered, disabled, tooltip `read-only for now` |

Nothing is ever sent. Compose areas render; their send buttons are disabled.

## 5. States

- No file at all: list text `Nothing here. Back to your task.`; detail `Pick an item to see it here.`
- Stale or bad feed (`Feed.dim`): text dims and a `?` mark shows beside SOURCES.
- Keys: `n` or Down next, `e` or Up previous, action keys from the board, `Esc` closes.
- Motion: a 180 ms fade on open, no bounce; nothing pulses.

## 6. Not built

- Time sub-tabs Days, Focus zones, Progress, Screen and health, Reminders: card says no data source yet.
- VIP flag, Infra project filter (approximated: alert and ops items), evening recap, token and cost metrics, gap table.
