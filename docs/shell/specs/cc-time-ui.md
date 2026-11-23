# Spec: Time tab pages

Code: `modules/cc/pages/TimePage.qml`, `pages/time/*.qml` (one file per sub-tab), `js/Metrics.js`
(pure view-model, tested by `tst/tst_metrics.qml`). Data: `metrics.json`
(`docs/shell/specs/cc-time-kpis.md`). Keys: `docs/shell/specs/cc-keys.md`. QML draws, Metrics.js shapes,
the daemon computes.

---

## 1. Data flow

1. `TimePage` reads `~/.local/state/dots-overview/metrics.json` with one `FileView` (`metricsPath`,
   watched), parses it once with `Metrics.parse` into `missing | invalid | version | ok`.
2. Each sub-tab gets `parsed`, the keyboard state `ks` and `inList`. No tab reads a file or execs.
3. A key the daemon left out is never drawn as 0. The tab says **which source is missing**:
   `Metrics.emptyText(parsed, section)` plus the daemon's own `sources.<section>.reason`.
4. Stale (older than 10 minutes) turns the "updated" stamp amber. A future `ts` counts as fresh.

---

## 2. Sub-tabs

| Tab | Shows | Reads |
|---|---|---|
| Today | unchanged (activity.json, mirror.json); keys `s` focus, `b` break, `p P` grouping | overview files |
| Week | 4 cards vs last week, 7 bars stacked by zone, target line, zone legend, selected day | `days`, `zones.byDay`, `periods.week` |
| Days | newest first: in/out, worked vs target, focus, breaks, tasks, 14-day sparkline; Enter opens the day | `days` |
| Heatmap | weeks x weekdays grid, month totals, week by week, trends, ratios, streaks, punctuality, best/lowest day | `days`, `improve` |
| Focus zones | 7 or 30 day ranking, 14 days, 12 weeks, projects with agent share, live zone | `zones` |
| Progress | 19 KPI cards: value, previous, change with arrow, 30-day sparkline, for the period | `periods`, `days` |
| Report | the period written as text; copy or save as `~/powerhouse/reports/time-<period>-<day>.md` | `periods`, `improve` |
| Screen and health | screen time, late night, sessions; 14-day health grid (private) | `screen`, `health` |
| Reminders | due, scheduled, next prayer; `s` hides, `d` marks handled, for this session only | `reminders` |
| Agents | runs, prompts, active, waiting on you, tokens, list price cost estimate, each against the previous period; tokens by kind; tables by agent, ticket, model; 30 days; subagent share; live counts. `p` `P` today/week/month, `Enter` or `o` jumps to a live agent | `agent-metrics.json` (spec: cc-agent-metrics.md) |

Colour is tokens only: `accent` good, `waiting` bad, dim neutral, never green. Zone colours are six
alpha steps of `accent`, `waiting` and `fgDim` (`Metrics.series`).

---

## 3. Keys on the Time pages

Resolved by `js/Keys.js`; the view offers the result to `TimePage.handleKey(res, st)` first.

| Key | Week | Days | Heatmap | Zones | Progress | Report | Reminders |
|---|---|---|---|---|---|---|---|
| `h l` | day | - | week | - | card | - | - |
| `j k` | zone legend | day | weekday | zone | card row | - | row |
| `p P` | newer, older week | - | - | 7, 30 days | period | period | - |
| `Enter` | day detail | open or close detail | day detail | - | - | save file | - |
| other | | `Up Down` scroll detail | | | | `c` copy | `s` `d` |

`Metrics.nav` is the whole cursor logic (clamps, card rows, detail), `Metrics.hints` the footer line;
a test resolves every hint key through `Keys.resolve` so a hint cannot name a dead key.

---

## 4. Privacy and writes

1. Screen time and health are drawn only here. The report never contains them.
2. Nothing leaves the machine. Copy sets the local clipboard; Save writes one file with `FileView`.
   There is no network in these files. The one exec path is `r` (or the button) on Report, which
   calls `Actions.report()` to start the local daily-report command with a fixed argv; the
   tab itself runs no `Process`.
3. Reminders are read from `task export`. `s` and `d` hide a row in this session; the task list is
   never written.

---

## 5. Tests

1. `tst/tst_metrics.qml`: parse states, empty texts, formats, week stacking and totals, day detail,
   heat grid, months, KPI tone, improvement shapes, zones, health, reminders, report text, `nav`.
2. `tst/mkmetrics.py` writes `fixtures/metrics`, `metrics-partial`, `metrics-empty` (made-up names).
3. `tests/cc-ui.sh` renders every sub-tab at 1600x1000, 1920x1080 and 640 high, the empty and
   partial states, the opened day and the keyboard rings; `check.py` asserts geometry and content.

---

## 5. Keyboard scroll

1. Report and Screen and health: `j k`, `PageUp PageDown`, `g G` scroll the panels.
2. Week and Heatmap: `J K` scroll the side panels; `j k` still moves the cursor.
3. Days detail: `Up Down`. Report: `r` runs the daily report, `c` copies, `Enter` saves.
