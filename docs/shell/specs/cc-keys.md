# Spec: control centre keyboard model

Code: `modules/cc/js/Keys.js` (pure, tested by `tst/tst_keys.qml`). The view calls
`Keys.resolve(ev, state)` for every key press and runs the returned action. No page
may bind a key of its own; add it to `Keys.js` and its test.

---

## 1. Input and result

`ev` is `{ key, text, shift, ctrl, alt }` (Qt key code plus the produced text).
`state` is `{ page, sub, zone, mode, kind, pending, filterActive }`.

| State field | Values |
|---|---|
| `page` | `queue`, `inbox`, `agents`, `tasks`, `time` |
| `sub` | Time sub-tab: `today week days heatmap zones progress report screen reminders agents` |
| `zone` | `list`, `detail`, `tabs` (Time sub-tab strip), `panel`, `filter`, `help` |
| `mode` | panel kind: `snooze`, `reply`, `agent`, or empty |
| `kind` | selected item kind: `agent msg alert pr ticket mail capture`, empty if none |
| `pending` | `g` after a first `g` press |

Result `{ action, arg, pending }`. `action` empty means not handled, let the key through.
`none` means handled, do nothing (the key is swallowed).

---

## 2. Global keys

| Key | Action | Arg |
|---|---|---|
| `1` to `5` | `tab` | queue, inbox, agents, tasks, time |
| `Tab`, `Shift+Tab` | `pane` | next, previous pane of the page |
| `[`, `]` | `subtab` on Time, else `chip` | previous, next |
| `j` `k`, `n` `e`, `Down` `Up` | `move` | +1, -1 |
| `g g`, `G` | `top`, `bottom` | `Home` and `End` too |
| `PageDown` `PageUp`, `Ctrl+d` `Ctrl+u` | `page` | +1, -1 |
| `Enter` | `pane detail`, else `primary` | open or primary action |
| `Esc` | see ladder | |
| `/` | `filter.open` | |
| `?` | `help.open` | |
| `u` | `undo` | the last done or snooze |
| `{` `}` | `view` | previous, next saved view (Queue, Inbox) |
| `=` | `group` | next Group by (Queue, Inbox) |
| `Ctrl+g` | `panel.grant` | agent panel only: toggle the one-reply grant (Space would type) |

Panes per page: Queue and Inbox `list`, `detail`. Time `tabs`, `list`. Agents and Tasks
have one pane.

Esc ladder, first match wins:

1. help open: close help
2. panel open: close panel
3. filter field: leave the field, keep the text
4. detail zone: back to the list
5. Time, list zone: back to the sub-tab strip (`pane tabs`)
6. filter text set: clear it
7. otherwise: leave the control centre (`cc.close`)

---

## 3. Per zone

1. **Text entry** (`filter`, reply or agent panel). Every key types. Exceptions:
   `Esc`; `Enter` in the filter; `Ctrl+u` clears the filter; `Ctrl+Enter` submits a panel.
2. **Snooze panel.** `1` to `4` pick (30 minutes, after this task, tonight, tomorrow),
   `j` `k` move, `Enter` picks the highlighted, `Esc` closes. Other keys swallowed.
3. **Help.** `?` or `Esc` close, `j` `k` scroll. Other keys swallowed.
4. **Time sub-tab strip.** `h` `l` or `Left` `Right` change sub-tab, `Enter` or `j`
   drops into the page body.
5. **Time body.** `h` `l` move column or day (Week, Heatmap), `p` `P` next, previous period.
6. **Queue and Inbox list.** `l` or `Right` moves to the detail pane when an item is selected.
7. **Queue and Inbox detail.** `Down` `Up` scroll, `h` or `Left` back to the list.

---

## 4. Action keys (from the board)

Live in the **detail** zone on Queue and Inbox, and in the **list** zone on pages with
no detail pane. In the Queue list `j` and `g` navigate, so Jump and Send to agent are
reached with `Enter` first. That is the one deliberate departure from a flat keymap.

| Kind | Keys |
|---|---|
| agent | `a` allow once, `d` deny, `o` open pane, `s` snooze |
| msg | `r` reply, `g` send to agent, `q` queue, `s` snooze, `o` open |
| alert | `v` see analysis, `f` fix in repo, `q` queue, `s` snooze |
| pr | `o` open review, `g` send to agent, `q` queue, `s` snooze |
| ticket | `c` comment, `g` send to agent, `q` queue, `s` remind, `o` open |
| mail | `r` draft reply, `g` send to agent, `q` queue, `s` snooze |
| capture | `t` make a task, `g` send to agent, `x` dismiss |
| all queue kinds | `b` break down and start, `j` jump to source |

Pages without a detail pane (not on the board, proposed):

| Page | Keys |
|---|---|
| Agents | `o` open pane |
| Tasks | `b` break down and start, `o` open |
| Time, Report | `c` copy report |
| Time, Reminders | `s` snooze, `d` done |
| Time, Agents | `o` or `Enter` jump to the agent's pane, `p` `P` period |
| Agents page | `o` open pane, `t` Time, Agents tab |

Action names are `act.<name>`: `allow deny open snooze reply agent queue analysis fix
comment task dismiss breakdown jump copy done`. Existing never-send rules still apply:
`reply` and `comment` open a draft panel, nothing is sent from a key press alone.

---

## 5. Help overlay

`?` shows every key valid on the current page and zone, grouped Go, Move, Find, Time,
Actions. `Keys.helpRows(state)` builds it from the same tables `resolve` uses, and a test
asserts every action key appears. The footer hint line shows the five most useful keys for
the page; the overlay is the full list.

---

## 6. Focus ring

One rule, everywhere. Colours are tokens, never hex.

| Element | Rule |
|---|---|
| Focused row, chip, button, sub-tab | 2 px ring, 2 px offset, token `accent` |
| Pane holding focus | 1 px `accent` border; other panes keep their normal border |
| Pointer-only focus | no ring (`Keys.ring(kind, focused, keyboard)` returns `visible: false`) |
| Selected row | raised surface as today; the ring sits on top, never green |

The view tracks `keyboard` as true after any key press and false after a mouse press.
Every interactive element must be reachable by key: if it has a click handler it has an
action key or a place in the `Tab` and arrow order, and the same `Keys.js` test covers it.

---

## 7. Tests

`tst/tst_keys.qml` covers: tokens, digits, pane cycling, brackets, move keys, `gg` and
`G`, Enter, the Esc ladder, text-entry pass-through, snooze numbers, help swallow, every
board action key for every kind on both pages, Time columns and sub-tabs, help covers
every action key, and the focus-ring rule.

---

## 8. Status

1. Every mouse-only control now has a key: Group by (`=`), saved views (`{` `}`), Undo (`u`),
   the grant checkbox (`Ctrl+g`), Cancel (`Esc`).
2. Time Today: `p` `P` step Where time went, `s` starts or stops focus, `b` takes a break,
   `j` `k` scroll. Other sub-tabs: `h l j k p P Enter c s d` through `Metrics.nav`.
3. Focus rings: the Time strip, the Today body, `=` and `{ }` choices all draw the accent ring
   after a key press and none after a mouse press.
4. Footer hints match the keys: on Time, `Esc` in the body goes to the strip, `Esc` on the strip
   leaves.
