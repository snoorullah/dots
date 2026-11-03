# Shell: specification

## 1. Hard rules

These are enforced in code outside any model. A prompt cannot change them.

| # | Rule |
|---|---|
| 1 | Nothing is sent, replied to or forwarded for the owner without their click on that message |
| 2 | Agents can read and propose. They cannot approve, reject or merge a PR, change a cluster, or read secret values |
| 3 | Rules and workflows can change this PC only. No webhooks, and no chat channels as an agent's way out |
| 4 | Text from mail, chat and tickets is untrusted data. Hidden text is stripped before any model reads it |
| 5 | Agents run sandboxed, with no credentials, a cost cap and a visible list of what they read |
| 6 | Company and personal data are backed up separately |
| 7 | Read tracking stays off, because it spies on recipients |

**Attention rules.** Show, don't nag. Anything waiting stays visible until handled, even after its toast is dismissed. Interruptions batch to breakpoints unless they pass a verified VIP or failure check. Every interruption says why it reached you, and offers a key to change that.

## 2. Foundations

| Token | Value |
|---|---|
| Display | Bricolage Grotesque, for numbers and headings of 20 px or more |
| Interface | JetBrains Mono, 13 px, labels 12 px |
| Surfaces | Follow the wallpaper or the chosen theme |
| Waiting | Amber, with a shape |
| Failed | Red, with a shape |
| Unknown | Hollow `?`, never shown as fine |
| Accent | Blue, for selection, primary action and progress |
| Healthy | Shows nothing. There is no green |
| Buttons | 30 px main, 28 px small |
| Radius | 6 chip, 10 row, 14 to 22 card, rounded rather than squiggly |
| Motion | You opened it: a slide under 200 ms. It arrived itself: a soft fade. Only the equalizer moves on its own |
| Glass | `hyprglass` if compatible, otherwise native blur |
| Logos | Real app logos, themed with `gowall` |

## 3. Bar

Three groups, with the clock fixed in place.

| Group | Contents |
|---|---|
| **Left** | Logo (opens the control centre); profiles; workspaces and window logos; current task; detour chip |
| **Centre** | Clock, date, next salah |
| **Right** | Waiting symbols; failure chips; music; today's numbers; logout; bell |

- **Profiles, as icons:** Agents `sparkle`, Dev `code`, Web `globe`, Comms `chat-circle`, Review `git-pull-request`, Notes `notebook`, Other `stack`.
- **Waiting symbols, with age, oldest first, over three becomes `+n`:** agent `sparkle`, VIP `star`, alert `warning`, review `git-pull-request`, VIP mail `envelope-simple`, ticket `ticket`.
- **Music:** art, song, artist and album, then a thin equalizer reading real audio output. Paused holds still and dims.
- **Today's numbers:** PRs merged, tickets closed, XP.
- **Bell:** a dot, no number. Opens the system panel. Wi-Fi, Bluetooth and volume live there; a real problem still gets its own chip.

## 4. Moments

| Surface | Behaviour |
|---|---|
| Toast | Reason, actions, "not important". Dismissing never loses it |
| Quick capture | Type and go; a background agent adds project, tags and people |
| Re-nudge | Soft, at 10 minutes, then every 30 |
| Return chip, detour timer | Counts up when you leave your task; one key returns you |
| Recap on return | One line on what you were doing |
| OSD | Small volume and brightness pills |

## 5. Control centre

Full screen and sidebar, showing the same data. Left rail: tabs, saved views, source health.

| Tab | Contents |
|---|---|
| **Queue, Inbox** | One queue from agents, mail, chat, GitHub, tickets and alerts. Filters, group by urgency, source or person. Reply, send to agent, snooze, break down and start, jump |
| **Agents** | State, working on, last action, while you were away, runs, tokens, cost |
| **Tasks** | Today in order, board, all tasks with filters. Duplicates merged across systems. Waiting on others, captures, unticketed work, done-line |
| **Time** | See below |

`Super+Shift+I` opens the Time tab.

| Time sub-tab | Contents |
|---|---|
| Today | Logout, week, month, timeline, salah, next, time by project, item, agent or app, done today, focus ring, evening recap |
| Week | Daily bars, week, month and quarter totals, by project, by item |
| Days | Login, logout, lunch, misc, net, target. Editable, exports CSV, nothing is sent |
| Heatmap | 119 days, total, days worked, average, best day and week, streak |
| Focus zones | Scored focus blocks, what broke them, division of effort |
| Progress | Level, XP sum, earned, lost, factors, limits, streaks, badges |
| Report | Daily report, touchpoints, browser time |
| Screen and health | Screen time, check-ins, water and walk reminders, weekly suggestion |
| Reminders | Alarms, reminders, meetings |

**Progress limits:** daily loss stops at 100, you can't fall below your level's start, no losses on leave or sick days, only measured events count, one toggle turns it all off.

**Reminders:** one soft toast with one key. Held during focus blocks. Water every 90 minutes, a walk after 60 minutes at the desk; a lock of 5 minutes or more resets the walk timer.

## 6. Mail

No inbox as the first screen. Most mail is machine alerts, so the first question is who you owe.

| View | Contents |
|---|---|
| **Today** | "You owe three people." One sentence per ask, a deadline, what to say in a click. Agenda, owed to you, handled for you |
| **Inbox** | Search with `from:`, `to:`, `subject:`, `has:attachment`, `after:`, `label:`, `in:`; filters; folders; labels; split inbox; AI brief; draft with confidence; instant replies; why it's here; sender verification |
| **Reply zero** | To reply, needs action, awaiting, FYI |
| **Calendar** | Week, briefs, event from mail, find a time, booking links; salah and focus held |
| **Assistant** | Ask or tell, approvals waiting, agents, memory |
| **Rules** | Plain-English rules, test on 30 days, why it fired, version history |
| **Workflows** | Trigger, agent steps, your approval, run log, cost cap |
| **Clean up** | Bulk unsubscribe, digest, deep clean with preview, cold mail |
| **Analytics, Settings** | Volume, response time, agent activity; snippets, style, knowledge, accounts |

**Compose:** Cc, Bcc, snippets, send later, reminders, attachments, AI write, shorter, warmer, grammar, translate, 20 second undo.

**Say, don't write:** pick what to say, the agent writes it, you send it.
**Do it first:** Claude Code does the work the mail asks for, opens a draft PR and prepares the answer.
**Machine mail is never mail:** alerts go to Infra, GitHub to Review, tickets to Tasks, invites to Calendar, newsletters to a digest. Audit two at random, and the raw folders stay available.

**Actions rules can take:** label, archive, mark read, star, move, digest, draft, snooze, remind, make task, add event, notify the bar, start an agent.
**Actions they can't:** send, reply, forward, delete, webhook.

**Workflows shipped:** alert to incident, do the work then draft, scheduling, meeting brief, follow up, evening digest, attachment filing, weekly tune-up.

**Refused from the reference products:** auto send, webhooks, chat-channel assistants, read tracking, meeting recorder, team comments, mobile apps.

## 7. Review (GitHub)

| View | Contents |
|---|---|
| To review, Your PRs, Agent PRs | Thread, files, checks, commits, line comments, viewed marks, pending review |
| Issues | Comment, start a task, send to agent, close |
| Actions | Runs, logs, re-run failed, send a failure to an agent |
| Repos, Security | Branch state, dependency and secret alerts |

**Merge:** squash, merge commit or rebase, with optional branch delete. Blocked with a stated reason on failing or running checks, draft, requested changes or no approval. You can't approve your own PR.

**Build must add:** creating PRs and issues, label and assignee editing, search, notifications.

## 8. Infra

One app for the whole platform: DevOps, DevSecOps, delivery and supply chain. It replaces the ArgoCD UI, Argonaut, Kargo, the Argo Workflows and Argo Events UIs, the Forgejo admin screens and k9s. It does not replace Grafana. PR work lives in Review.

| Group | View | Contents |
|---|---|---|
| Now | Overview | What failed and needs you, every node, capacity, recent changes |
| Now | Alerts, Audit | Deduped alerts with reasons; who changed what, with the dry run they saw |
| Delivery | Pipelines | CI and Argo Workflows: runs, step graph, logs, retry, templates, cron |
| Delivery | Events | Argo Events: sensors, sources, event log, replay |
| Delivery | Apps | Sync state, tree, diff, manifest, parameters, events, history, sync options, rollback, pause, projects, repos, sync windows |
| Delivery | Promote | Kargo: stages, freight, verification, approve, promote, roll back |
| Delivery | Releases | Status per environment, changelog, rollback, release calendar and windows |
| Delivery | Environments | Every app in every environment, drift, PR previews |
| Delivery | Tenants | Tenant apps, versions, quotas, staged upgrades, onboarding |
| Cluster | Resources | All kinds, logs, exec, events, YAML, restart, scale, delete, port-forward |
| Cluster | Nodes, Network, Config | Capacity, cordon, drain; ingress to pods, certificates; ConfigMaps, secrets |
| Cluster | Metrics | Range, service, key charts, quick query, link to Grafana |
| Source and supply | Forge | Forgejo: repos, branch rules, mirrors, runners, access |
| Source and supply | Registry | Containers, charts and packages: versions, usage, cleanup |
| Source and supply | Supply chain | Signatures, SBOMs, provenance, admission policy, vulnerabilities, dependency updates |
| Source and supply | Security | Policy, who can do what, secret age and rotation, compliance benchmarks |

**Every change:** a dry run first, and an audit entry. **Production:** type the object's name. **Wrong cluster:** a warning when the `kubectl` context differs from the one on screen. **Secrets:** hidden; reveal needs your password and clears after 30 seconds.

A palette (`:`) jumps to anything.

## 9. Lock and session

**Lock:** clock, date, away chip, logout timer, waiting count, salah, music, picture, username, password. No task names. An optional timeline shows only logins, prayers, breaks and logout.

**Session:** lock, log out (ends the day), suspend, reboot, shut down, back up then shut down. Blocked with a reason while a long command runs.

**Password prompt:** says what is asking. If an agent asked, it says so and defaults to Deny.

## 10. Launcher

One launcher, `Super+Space`. Modes: all, clipboard `c:`, dictionary and grammar `d:`, files `f:`, fonts and icons `t:`, commands `>`, math `=`.
Clipboard history is encrypted, skips sensitive items and clears at logout unless pinned.

## 11. System and popups

- **System panel:** sliders, ten toggles, media, notification log.
- **Bluetooth:** devices, pairing code.
- **Media popup:** art, progress, controls.
- **Right-click menus:** window and desktop.
- **Screenshot:** region, copy, annotate, read text, to agent, to task, record.

## 12. Windows

| Feature | Behaviour |
|---|---|
| Profiles | Profiles to workspaces to windows, opened at startup |
| Tiling assistant | Six layouts, drag zones, a suggestion by window count, remembered per profile |
| Grouped tabs | Logo and title; drag out to split; restored after reboot |
| Restore | Layouts, apps, panes; agents resume paused; best guess, with one-key undo |
| Scratchpad | Note, terminal, snippet, math, ask; per project; turn into a task; survives restarts |

## 13. Notes

Plain Markdown in the vault, which Obsidian can still open. Write, sketch, history as local commits, linked items. Local-model summarise, find questions, make task. Includes learnings, reading list and wiki.

## 14. Modes and themes

**Modes:** focus, meeting, salah, heavy work, winding down, off duty. One at a time; salah wins. Meeting time keeps counting as worked.

**Routines:** when this, do that, on this PC only.

**Themes:** from wallpaper by default, plus fixed palettes as one small file each. Amber and red never change.

## 15. Overlays and utilities

| Feature | Behaviour |
|---|---|
| Recording | Toolbar and a bar marker |
| Live draw | Pen, highlighter, arrow, box, text, eraser; Esc clears |
| Keypress display | Off by default; never shown in a password field |
| Widgets | Performance, mixer, note, pinned image, crosshair; off until pinned |
| Screen corners | Rounded, ignored by the mouse |
| Cheatsheet | Keybinds, keyboard, commands, workspaces, tools; opens on what you are using |
| Utils | Screenshot, colour picker, record, draw, mic mute, wallpaper, theme, performance |

## 16. Retired from Obsidian

The control panel moves here, and Obsidian stays a notes app.

| Old page | New home |
|---|---|
| Control Center cards | Control centre |
| Time, Days, Timesheet, Focus Zones | Time tab |
| Daily report, Touchpoints, Browser | Time, Report |
| Progress, Streaks, Badges | Time, Progress |
| Agents away, runs, metrics | Agents tab |
| Tickets | Tasks tab |
| Review queue, Repos, Security | Review |
| Infra, Alerts | Infra |
| Learnings, Reading list, Wiki | Notes |
