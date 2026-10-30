# Shell: build plan

> Ship one surface at a time. Each phase stays usable, and the current shell keeps working until its replacement passes.

## Principles

1. **Waybar stays as the fallback** until the new bar has passed a full working week.
2. **Read before write.** Each app ships read-only first. Actions come in a later step, behind their gate.
3. **One data daemon, many views.** Surfaces read shared state files. None polls a service itself.
4. **Generated from real config.** Keybinds and cheatsheets come from live config, so they can't go stale.
5. **Public repo.** Discovery at runtime, private values in unmanaged files, enforced by `tests/lint.sh`.

## Phases

| # | Phase | Delivers | Done when |
|---|---|---|---|
| 0 | Foundations | Tokens, fonts, Phosphor icons, glass, themed app logos, state contract, send gate | Fixture scenes render; the gate test refuses every outbound call |
| 1 | Bar | Profiles, workspaces, logos, clock, salah, waiting symbols, metrics, music, bell | One week as the daily bar with Waybar off |
| 2 | Moments | Toasts with why, quick capture, return chip, detour timer, OSD | No toast can be lost; every interruption shows its reason |
| 3 | Control centre | Queue, Inbox, Agents, Tasks, Time, sidebar | Everything in the current overview panel is reachable |
| 4 | Lock and session | Lock screen, session menu, password prompt, away picker | Unlock works with the shell crashed |
| 5 | Launcher and system | Launcher, system panel, Bluetooth, media, right-click menus | Replaces the current launcher and quick panel |
| 6 | Windows | Profiles, tiling assistant, grouped tabs, restore, scratchpad | Reboot restores layout, apps and panes; agents stay paused |
| 7 | Mail | Read side, then drafts, then send behind the gate | One week of triage with the old client closed |
| 8 | Calendar | Read, then RSVP, then booking links | Briefs arrive 30 minutes before meetings |
| 9 | Review | Read, then comment and review, then merge | A full day of reviews without opening the browser |
| 10 | Infra | Cluster and Apps first, then Pipelines, Events, Promote, Releases, Environments and Tenants, then Forge, Registry, Supply chain and Security. Read first, then actions behind dry run and typed confirm | A full on-call day and a full release without the old tools |
| 11 | The rest | Notes, modes, routines, themes, overlays, recording | Each listed feature in `spec.md` works |
| 12 | Retire | Remove Waybar and the Obsidian control panel | Nothing still reads their data |

**Order rationale:** phases 0 to 3 give daily value with low risk. Mail, Review and Infra are large apps, so each gets its own branch and review.

## Verification

| Check | How |
|---|---|
| Layout | QML scene tests with fixture state, one per state on the boards |
| Public repo | `tests/lint.sh` on every change |
| Gates | Tests that attempt each refused action from an agent, and expect refusal |
| Prompt injection | Fixture mail carrying hidden text and instructions; the agent must not act on it |
| Performance | Bar idle under 1% CPU; panels open under 200 ms |
| Real use | Each phase's "done when" above, on the real desktop |

## Risks

| Risk | Answer |
|---|---|
| `hyprglass` breaks on a Hyprland update | Falls back to native blur; pin by Hyprland version |
| Restoring windows is best guess | One key undoes it; agents resume paused |
| Local model misreads asks and promises | Measure on a labelled sample first; everything stays a suggestion |
| Cluster writes from a GUI | Dry run first, typed name on production, full audit log |
| Scope: Mail, Review and Infra are each products | Ship read-only versions first, and stop if the old tool stays better |

## Decisions already made

| Topic | Decision |
|---|---|
| Type | Bricolage Grotesque for large numbers and headings; JetBrains Mono for the rest |
| Icons | Phosphor Regular; no Nerd Font glyphs, as lint requires |
| Dynamic Island | No |
| Control centre | Sidebar and full screen, one keybind each |
| Bar labels | Logos; the active workspace keeps its name; others on hover |
| Notifications on the bar | One bell with a dot, no count |
| Grafana | Not replaced; Infra covers daily checks and links out |
| Infra scope | The whole platform: delivery, source, supply chain and security in one app |
| Lock screen | Minimal, with no task names |

## Open

1. Owner approval of the design.
2. Keyboard changes are documented and on hold, so keybinds in the spec are placeholders.
3. Whether to read the mail Sent folder, which promise tracking needs.
4. Mail send and calendar permissions from the mail provider.
5. Licence: Inbox Zero is AGPL, so it was used for ideas only. Reusing its code needs a decision.
