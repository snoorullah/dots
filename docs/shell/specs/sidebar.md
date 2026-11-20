# Sidebar spec

Board: `Sidebar.dc.html`, left card. The control centre queue, compact, at the screen edge.

---

## 1. What it shows (top to bottom, 460 wide)
1. **Header**: moon-stars logo, `NOW` caption, current task title, `next:` line.
2. **Tabs**: Queue, Inbox, Agents, Work, Time. One active (raised bg).
3. **List**: grouped rows, scrolls. Groups: `WAITING ON YOU`, `TODAY`, `WHILE YOU WERE AWAY`, `FROM YESTERDAY`.
4. **Footer**: selected title plus Reply, Agent, Queue, Snooze, Expand.
5. **systemSlot**: `Loader` for `../system/SystemPanel.qml`, opened by a gear in the header.

## 2. Row (min 52, grid 44 / 14 / rest)
- Age mono 12 right aligned; mark: amber circle waiting, red diamond failed, else none.
- Title 13/18 weight 500, one line, elided.
- Sub line 12/16 dim: `actor` then source icon then source name.
- Selected: raised background. Hover: wash.

## 3. States
| State | Look |
|---|---|
| Empty | dim line "Nothing in the queue" |
| Stale feed (`Feed.dim`) | ages and titles faint, unknown mark in header |
| Selected | raised row, footer shows its title |
| Nothing selected | footer says "Pick an item", actions disabled |
| System open | list and footer replaced by `systemSlot` |
| System file missing | slot shows "System panel not installed" |

## 4. Data per element
| Element | Source |
|---|---|
| Header title, next | `Feed.task` (`ref`, `desc`), `Feed.nextItems[0]` |
| Rows | `Feed.attentionItems` + `Feed.nextItems` (attention.json, read-only) |
| Group | `waiting`/failed alert, else age under 1 day = today, else yesterday; `away: true` = while away |
| Tab filter | `js/SideModel.js` by `kind` and `src` |
| Source name and icon | `src` then `kind` fallback |
| Age | `Fmt.age(ageSec)` from overview js |

## 5. Actions
| Button | Behaviour |
|---|---|
| Expand | local: opens the control centre on the current tab (`Ui.toggleCc`) |
| Row double click | local: `dots-jump <ref>` via `Actions.jump` |
| Reply, Agent, Queue, Snooze | rendered, disabled, tooltip "read-only for now" |

Nothing is sent: no mail, Slack, ERP or GitHub write.
## 6. Window and motion
- Right edge `PanelWindow`, overlay layer, shown while `Ui.sidebar`; Escape and outside click close it.
- Slide in 180 ms, `easeOut`, no bounce. Rows fade in 240 ms. Nothing pulses.

## 7. Stubbed or deviating

- `away` is read from the item if the writer sets it; no item has it yet, so that group is normally empty.
- Gear button for the system slot is not on the board (the board draws System as a separate card).
- Logo is the `moon-stars` Phosphor glyph, not the brand SVG.
- New icon names need `tools/gen-phosphor-qml.py` rerun at integration.
