# Overview UI

The Quickshell surface for the work overview.
A pill in the bar, a dropdown card, a full panel, a focus timer, a heatmap.
Read-only on `~/.local/state/dots-overview/`. Writes nothing itself.

Lives in `home/private_dot_config/quickshell/dots/modules/overview/`.

---

## 1. What you see

| surface | when | size |
|---|---|---|
| pill | right slab of the bar | zero width and height when nominal |
| card | left click on the pill, `Super+I` | `380` wide, max `520`, notch `8x4` |
| panel | right click, `Super+Shift+I` | `920x640`, pages below |

Pill states, all of them at once if they apply.

1. **ring + mm:ss** a focus block is running
2. **red count** an alert failed and nobody waits
3. **amber count** someone waits on me
4. **hollow `?`** data stale (over 180 s), wrong `v`, or unreadable

Nominal renders nothing.
Missing files count as "no data", not as `?`.
Mail is never drawn: that source is unavailable by decision.

Panel pages: `today`, `week`, `attention`, `focus`, `heatmap`, `item`.
Month and quarter are totals on the Week page.

---

## 2. Contract with the other tracks

**From T1** six files, all `v: 1`.
`now`, `activity`, `attention`, `heatmap`, `mirror`, `meta`.

**From T2** a `Theme` singleton at `modules/theme/Theme.qml`.
Assumed shape mirrors `tokens.json`:

```
Theme.color.{surface,surfaceContainerHigh,outline,fg,fgDim,fgFaint,accent,accentFg,amber,red}
Theme.alpha.{panel,wash,hover,divider}     Theme.radius.{chip,panel,card,pill}
Theme.space.{xs,s,m,l,xl,xxl,xxxl}         Theme.motion.{fast,base,slow}
Theme.font.{sans,mono,icon}  Theme.font.size.{caption,bodyS,body,title,headline,display}
Theme.bar.height
```

> Only `Look.qml` names `Theme.*`. If T2 exposes tokens differently, edit that one file.

**To T2** the API in `docs/contracts/qml-api.md`.

```
OverviewPill   attnWaiting attnFailed stale screenName   cardRequested() panelRequested(page)
OverviewHost   toggleCard() openPanel(page) close() lamp(ms)   anchorScreen anchorX anchorBottom
```

The pill writes its own position into `Feed.anchor*`.
The host reads it from there, so T2 wires only the two signals.
The bar must be a full-width layer at screen `x=0`: `anchorX` is window x.

IPC, target `dots.overview`: `toggle`, `panel <page>`, `focus <start|stop|break>`.

---

## 3. Writes

Only `Actions.qml`, only `Quickshell.execDetached` of an argv array.

| button | argv |
|---|---|
| Break down & start | `dots-overview breakdown <ref> --start` |
| Jump | `dots-jump <ref>` |
| Write brief | `dots-overview report` |
| Start / Stop / Break | `dots-overview focus start`, `stop`, `break` |

`<ref>` falls back to the item `id`.
A ref starting with `-` is refused.
No shell, no `Process`, no `sh -c`: `tests/overview-ui.sh` greps for them.

---

## 4. Files that differ from the spec

| spec | here | why |
|---|---|---|
| `State.qml` | `Feed.qml` | `State` collides with the QtQuick type and silently resolves to it |
| (none) | `Look.qml` | the single place that reads `Theme.*` |
| (none) | `parts/Txt.qml`, `Glyph.qml`, `RefTable.qml` | shared text, icon, table |

---

## 5. Cost

No polling of files: `FileView { watchChanges: true }` on six files.
Two timers, neither reads a file.

1. 30 s: re-evaluate staleness. Without it a dead writer never goes stale.
2. 1 s: only while a focus ring is on screen.

Card and panel windows exist only while open (`LazyLoader`), freed 160 ms after close.
Pages are loaded one at a time.

---

## 6. Tests

```
bash tests/overview-ui.sh          # needs quickshell + Qt6 qmltestrunner/qmllint
KEEP=1 bash tests/overview-ui.sh   # keep the PNGs, prints the directory
```

No compositor, no T1, no T2.
It renders the real components on Qt's offscreen platform with a stub Theme.
The stub derives its colours with the same `mix()` as the real `theme/Tokens.qml`, and the suite
asserts key for key that the two agree (`REAL_THEME_DIR` points at a checkout until T2 is merged).
The card footer is pinned below the scroller with a bottom fade; the heatmap page sizes its cells
to the page and keeps the 235x95 compact grid as the part's default.
Fixtures: `tst/fixtures/`, regenerate with `python3 tst/mkfixtures.py`.

1. `qmltestrunner` on `js/Fmt`, `js/Ledger`, `js/Model`
2. `qmllint` on a generated qmldir tree
3. static rules: no PUA codepoint, argv-only exec, `Theme.*` only in `Look.qml`, diff scope
4. the eight pixel assertions of the spec, plus live reload and lamp test
5. stub `dots-overview` and `dots-jump` on `PATH` record the exact argv

> `tst/` ships to `~/.config` unless `.chezmoiignore` lists it. That file is not T3's.

---

## 7. Licence

`js/*.js` carry `SPDX-License-Identifier: MIT` and the repo owner's copyright line.
They are fresh implementations, inspired by tally-screentime (MIT).
