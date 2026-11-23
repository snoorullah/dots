# Spec: Time tab metrics (`metrics.json`)

Contract between the daemon (`dots-overview`, new `metrics` step, fast cycle) and the
control-centre Time pages. Python computes everything; QML only draws.

---

## 1. File

| Item | Value |
|---|---|
| Path | `~/.local/state/dots-overview/metrics.json` |
| Writer | `dots_overview/metrics.py`, atomic write via `atomic.py`, mode `0600` |
| Version | `"v": 1`. Readers ignore a higher `v` and show the empty state. |
| Stamp | `"ts"` unix seconds, `"tz"` IANA name, `"today"` `YYYY-MM-DD` |
| Day | A day is the work session day (`attendance_day`), never midnight. |
| Inputs | Opened read-only (`mode=ro`). Nothing is written back. Nothing leaves the machine. |
| Missing source | The key is **omitted**. Never `0`, never a guess. UI shows "no data". |

Units: `*Min` minutes (int), `*Sec` seconds (int), `*Ts` unix seconds, `*Pct` 0-100 (float, 1 dp),
`*Count` int, `day` `YYYY-MM-DD`.

Top-level keys: `v`, `ts`, `tz`, `today`, `days`, `periods`, `improve`, `zones`, `screen`,
`health`, `reminders`, `sources`.

---

## 2. `days` (per-day series, last 120 days, oldest first)

One object per day with a `day_class`. Non-working days are kept (`kind` says so) so the
heatmap has no holes.

| Field | Unit | Source |
|---|---|---|
| `day` | date | `day_class.day` |
| `kind` | enum | `day_class.kind` |
| `targetMin` | min | `day_class.target_minutes` |
| `workedMin` | min | `v_day_worked.net_minutes` (span minus deduction) |
| `spanMin` | min | `v_day_span.span_minutes` |
| `loginTs`, `logoutTs` | unix | `v_day_span.first_unix`, `last_unix` |
| `breaks` | `{label: min}` | `away_label` (`end_unix - start_unix`, grouped by `key`) |
| `deductionMin` | min | `v_day_deduction.deduction_minutes` |
| `focusMin` | min | sum of `focus_span` (`end_unix - start_unix`) with a `ticket_token` |
| `deepWorkMin` | min | longest-run rule, section 4 |
| `agentOnlyMin` | min | `ticket_minutes.agent_minutes` summed for the day |
| `humanMin` | min | `ticket_minutes.human_minutes` summed for the day |
| `salahOnTime`, `salahTotal` | count | `salah_log` rows `enforcement` in `logged`,`declared` vs all non-`disabled` |
| `contextSwitches` | count | `focus_span` rows whose `ws_label` or `ticket_token` differs from the previous row |
| `interruptions` | count | `prompt_log` rows `outcome='shown'` plus `salah_log.nudged_unix` not null |
| `tasksDone` | count | `task export` `end` within the day |
| `prsMerged`, `prsReviewed` | count | `mirror.json` refs: `closedAt` (state merged), `reviewedAt` |
| `ticketsClosed` | count | `mirror.json` refs with `src` ticket and `closedAt` |
| `commits` | count | `git log --since --until --author=<git user.email>` over repos under `~/work` and the chezmoi source |
| `screenSec` | sec | ActivityWatch `aw-watcher-window` + `aw-watcher-afk` (not-afk), see section 8 |
| `topApps` | `[{app, sec}]` max 5 | same window bucket, grouped by app |
| `meetingMin` | min | **no source today**: omit |

---

## 3. `periods`

Keys `today`, `week`, `month`, `quarter`. Week starts Monday, ranges are in session days.
Each KPI is `{ "value": n, "prev": n, "delta": n, "deltaPct": n }`.
`prev` is the same-length period before (yesterday, last week, last month, last quarter).
`delta = value - prev`. `deltaPct` is omitted when `prev` is 0.

| KPI key | Meaning | Derived from |
|---|---|---|
| `workedMin` | net worked | `days.workedMin` |
| `targetMin` | expected | `days.targetMin` |
| `attainmentPct` | worked / target | both |
| `focusMin`, `deepWorkMin`, `agentOnlyMin`, `humanMin` | as section 2 | sums |
| `breakMin` | total breaks | `days.deductionMin` |
| `daysWorked` | days with `workedMin > 0` | count |
| `avgLoginMin`, `avgLogoutMin` | minutes since local midnight | mean of `loginTs`, `logoutTs` |
| `salahOnTimePct` | on time / total | sums |
| `contextSwitches`, `interruptions` | sums | sums |
| `tasksDone`, `prsMerged`, `prsReviewed`, `ticketsClosed`, `commits` | sums | sums |
| `screenSec` | sum | sums |

Also per period: `topProjects` `[{project, min}]` and `topApps` `[{app, sec}]`, max 6 each
(from `term_day.project` and `zones`). The existing `activity.json` `buckets` stays for the
bar and is not replaced.

---

## 4. `improve`

| Field | Definition |
|---|---|
| `trend7`, `trend30` | `{ "workedMin": slope, "focusMin": slope, "deepWorkRatioPct": slope }`, least-squares slope per day over working days only, plus `dir` in `up`,`flat`,`down` (flat when `abs(slope) < 1% of mean`) |
| `streaks` | `{ "targetMet": n, "onTimeLogin": n, "salahOnTime": n, "best": {...same keys} }`, current run counted back from the latest finished working day |
| `bestDay`, `worstDay` | `{day, workedMin}` over the last 30 working days with `workedMin > 0` |
| `punctuality` | `{ "targetLoginMin": n, "avgLateMin": n, "onTimeDays": n, "days": n }`; target from daemon config `loginTarget`, lateness from `login_log.late_minutes` (first_of_day = 1) |
| `deepWorkRatioPct` | `deepWorkMin / workedMin` (7 and 30 day windows) |
| `focusCompletionPct` | **no source today** (focus sessions are live only in `focus.json`): omit |
| `interruptionsPerHour` | `interruptions / (workedMin / 60)` |
| `timeToFirstFocusMin` | per day: `first focus_span.start_unix - loginTs`, then 7 and 30 day median |

Deep work: a run of `focus_span` rows on the same `ticket_token`, gaps under 5 minutes
joined, run length at least 45 minutes. `deepWorkMin` is the sum of such runs.

---

## 5. `zones`

| Field | Source |
|---|---|
| `current` | `focus.json` `zone`, `state` (live, not history) |
| `byDay` | `{day: [{zone, min}]}` last 30 days |
| `byWeek` | `[{week, zones: [{zone, min}]}]` last 12 weeks |
| `projects` | `[{project, min, agentMin}]` from `term_day` (`seconds`, grouped by `project`) |

`zone` is `focus_span.ws_label`. If it is empty the span is `"unzoned"`. Zone and project
names are data and must never appear in code or fixtures.

---

## 6. `screen` and `health` (private, control centre only)

`screen`: `{ "todayActiveSec", "todayIdleSec", "weekActiveSec", "lateNightSec" (22:00-05:00),
"longestStretchMin", "bySession": [...] }`. Source: ActivityWatch `aw-watcher-afk` status.

`health` (`private.db`): `checkpoints` `[{day, slot, score, outcome}]` last 14 days from
`health_checkpoint`; `scoreAvg7`; `doses` `[{day, ts}]` from `med_dose`;
`doseToFirstCheckpointMin`. Must not be logged, put on the bar, the lock screen or in
notifications. The file mode is `0600`.

---

## 7. `reminders`

| Field | Source |
|---|---|
| `due` | `task export` pending with `due` set, soonest first, max 10: `{id, desc, due, overdue}` |
| `scheduled` | same, `scheduled` set |
| `salahNext` | `{prayer, iqamahTs}` from today's `salah_log` or the prayer times the daemon already has |
| `timetrack` | **no source today**: omit |

`desc` goes through the existing id-to-human naming (`names.py`).

---

## 8. `sources`

`sources` maps each section to `ok`, `partial` or `missing` plus a one-line reason, so a
page can say why it is empty. ActivityWatch is read only from `localhost:5600`; if it is
down, `screen*`, `topApps` and `screenSec` are omitted and `sources.aw = "missing"`.

---

## 9. Page binding

| Time sub-tab | Reads |
|---|---|
| Today | `periods.today`, `days[-1]` |
| Week | `periods.week`, last 7 of `days` (bar graph of `workedMin` vs `targetMin`) |
| Days | `days` |
| Heatmap | `days.workedMin`, `kind` |
| Focus zones | `zones` |
| Progress | `periods.*`, `improve` |
| Report | `periods.*`, `improve` |
| Screen and health | `screen`, `health` |
| Reminders | `reminders` |

---

## 10. Tests

1. Unit tests per KPI against a temp `work.db` and `private.db` built from fixtures
   with made-up names only.
2. Golden `metrics.json` for the fixture; schema check that no key is `null` or `NaN`.
3. Missing-source test: drop AW and a table, assert the keys are omitted.
4. A grep test that no company, person or host name occurs in the output.
