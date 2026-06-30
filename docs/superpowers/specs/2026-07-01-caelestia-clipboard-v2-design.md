---
title: Caelestia Clipboard v2 — Redesign
date: 2026-07-01
status: approved-design
scope: Redesign of the caelestia clipboard overlay (modules/clipboard) — UX + new features
supersedes: the UI layer of 2026-06-30-caelestia-clipboard-overlay-design.md (logic.js + cliphist backing are kept)
implements-in: fork ~/src/caelestia-shell @ feat/caelestia-widgets (modules/clipboard, services, sidecar, systemd units)
---

# Caelestia Clipboard v2

## 1. Why this redesign
v1 was **feature-complete but UX-naive** — every spec feature shipped (search, filter,
pin, delete, preview, quick-pick) but arranged as a *form*, not designed as a *tool*:

- Oversized modal (hardcoded 1000×680, ~half a 1080p screen).
- Search bar is full-width and dominant — but a clipboard query is 3–5 chars, so it
  steals real estate from the one thing that matters (the list).
- A permanent ~40% preview pane that is dead/empty for the common case (short text).
- Flat typography — no weight/size/colour/position hierarchy, so the eye has no anchor.
- Type-filter chips with no label of intent and no visible cycle affordance — undiscoverable.
- Footer hints in `m3outline` at `body.small` — effectively unreadable.
- Image entries render as the literal text `binary data image/png` (no thumbnail).
- No edit, no expiry, no secret handling.

This redesign rebuilds the UI around the user's **actual** workflow and adds
edit-in-place, secret masking, and 24-hour auto-expiry.

## 2. Persona & job-to-be-done
**Keyboard-first infra engineer with ADHD.** Tiling WM (Hyprland, ~90 keybinds),
rofi/tmux/vim power user; copies shell commands, code, YAML, IDs/tokens, paths, URLs,
error snippets; distraction-averse (the zen-mode goal); design-literate.

**JTBD:** *"surface the thing I copied N items ago and paste it in a few keystrokes,
without breaking flow."* Primary path = **scan the recent list**. Secondary = fuzzy-type
from memory. Aspirational = **pins** (valued, wants to use more — the design must make
pinning frictionless and ever-present to build the habit).

## 3. The spine (mental model)
**Pin = keep forever + speed-dial. Unpinned = vanishes in 24h. Secrets = masked.**
Pin what matters; the rest evaporates. One sentence the user can hold in their head.

## 4. Goals / Non-goals
**Goals**
- Dense, scan-first **list is the hero** (~8–12 rows visible, strong selected signal).
- **Pins first-class:** always-visible top section; `⌃p` toggle; `⌃1–9` speed-dial;
  the *only* durable store (everything else is ephemeral).
- **Thin search** (type-to-filter, ~1 row), not a bar.
- **Typographic hierarchy** (weight/size/colour/position) + **readable hints**.
- **Peek** — rich preview on demand (markdown / code / image), never a permanent pane.
- **Edit-in-place** (`⌃e`).
- **Delete + undo** (`⌃d` instant + `⌃z` toast; `⌃⇧⌫` wipe with confirm).
- **Secret auto-masking** (+ reveal / manual mark / optional never-store).
- **24h auto-expiry** for unpinned entries (prune every 4h).

**Non-goals (v2)**
- Multi-select, rich-text/format-preserving editing, clipboard sync, cloud, OCR-in-clipboard
  (OCR is the separate screenshot Phase 4), per-type advanced transforms.

## 5. Layout
Compact centred popup. Width ~460px; height grows to fit (pinned + ~8–10 recent rows),
capped ~70% of screen height. No side pane, no chip row.

```
 ┌ Clipboard ───────────────────────── 23 ┐   header: title + result count
 │ 🔍 deb▏                          [img]  │   thin search line (+ filter tag when active)
 │ ── PINNED ──────────────────────────── │   section label (dim, only if pins exist)
 │ 📌 kubectl get pods -n pnats-prod   2d  │   pinned row
 │ 📌 ssh arc … pve-01                 5d  │
 │ ── RECENT ──────────────────────────── │
 │› $ docker compose up -d            12m  │   selected: accent bar + bg + brighter text
 │  📝 Everything captured: session…  18m  │   text
 │  ⟨⟩ function parseList(text){ …     25m  │   code (mono)
 │  🖼 image · 1920×1080              1h  ▦ │   image: thumbnail chip
 │  🔗 https://github.com/…           2h  │   link
 │  🔒 •••••••• · secret · 24 chars   3h  │   masked secret
 │ ─────────────────────────────────────── │
 │ ↵ paste · ⌃p pin · ⌃d del · ⇥ filter · ? │   readable hints (proper contrast)
 │ (Space = peek)                          │
 └─────────────────────────────────────────┘
```

**Row anatomy:** `[type-icon]  content (1 line, primary weight, elided)  ·  app · time (dim, right)`.
Type icons: `$` command, `⟨⟩` code, `📝` text, `🔗` link, `🖼` image (thumbnail), `🔒` secret.

## 6. Keymap
| Key | Action |
|---|---|
| type | fuzzy filter (logic.fuzzy) |
| ↑ / ↓ (or ⌃k / ⌃j) | move selection |
| ↵ | copy selected + close |
| `⌃1`–`⌃9` | paste the Nth **pinned** item (speed-dial) + close |
| `⌃p` | pin / unpin selected (jumps to PINNED) |
| `Space` | peek (rich preview overlay; Space/Esc dismiss) |
| `⌃e` | edit-in-place (editable overlay; ↵/⌃↵ copy edited, Esc cancel) |
| `⌃d` | delete selected (instant) + `⌃z` undo toast (~5s) |
| `⌃⇧⌫` | wipe all (confirm) |
| `⌃r` | reveal a masked secret (temporary, auto-rehide) |
| `⌃s` | toggle sensitive on selected (mask/unmask) |
| `⇥` | cycle type filter (all→text→code→link→image→all); tag shown in search line |
| `?` | toggle full keymap help |
| `Esc` | close |

## 7. Features

### 7.1 Pins (first-class, durable, speed-dial)
- Always-visible `PINNED` section at the top; never scrolls away.
- `⌃p` pins/unpins instantly; pinned items move to the section.
- `⌃1–9` is a **speed-dial**: paste the Nth pinned item without navigating.
- **Pins are the only durable store.** `ClipPins` persists `{raw, preview, ts, sensitive}`
  to disk (`~/.local/state/caelestia/clip-pins.json` or equivalent) so pins survive
  reboots *and* survive cliphist pruning (the pin holds the value independently of cliphist).

### 7.2 Peek (rich preview, on demand)
- `Space` opens a centred overlay rendering the selected entry **richly**:
  markdown via QML `TextEdit { textFormat: MarkdownText }`, code in mono (syntax highlight
  is a later nice-to-have), images as a full `Image`, links with the URL + title.
- Masked secrets stay masked in peek unless revealed (`⌃r`).
- Space/Esc dismiss. No permanent screen cost.

### 7.3 Edit-in-place
- `⌃e` opens the peek overlay in **edit** mode: a multiline field pre-filled with the
  content. `↵`/`⌃↵` copies the edited text (which re-enters history via the wl-paste
  watcher) and closes; `Esc` cancels. Removes the paste-somewhere→edit→recopy dance.

### 7.4 Delete + undo
- `⌃d` deletes the selected cliphist entry immediately and shows a `⌃z` **undo toast**
  (~5s); undo re-stores the entry. No modal for single delete (fast).
- `⌃⇧⌫` wipes the whole history behind a **confirm** (truly destructive).

### 7.5 Secret masking
- **Detection** (`logic.detectSensitive(text, hint) → bool`, pure + node-tested):
  - explicit clipboard hint when present (`x-kde-passwordManagerHint: secret`), passed in by the sidecar;
  - else heuristic: JWTs (`eyJ…\.…\.…`), key prefixes (`AKIA…`, `ghp_…`, `gho_…`, `sk-…`,
    `xox[baprs]-…`, `-----BEGIN … PRIVATE KEY-----`), long high-entropy tokens,
    password-shaped strings (no spaces, mixed classes, length ≥ ~12 and entropy over a threshold).
- **Render:** masked entries show `🔒 •••••••• · secret · N chars` in list **and** peek —
  never plaintext on screen. `↵` still copies the real value. (Also stops clipboard
  contents leaking into screenshots.)
- **Reveal:** `⌃r` temporarily reveals (auto-rehide after a few seconds).
- **Manual mark:** `⌃s` toggles sensitive (override false pos/neg); stored in `ClipMeta`.
- **Optional hard mode (config, default off):** the sidecar skips storing any clipboard
  carrying the password-manager hint, so true secrets never enter history.

### 7.6 Auto-expiry (24h, prune every 4h)
- Unpinned entries auto-delete **24h after copy-time**; re-copying resets the clock.
- **Pinned items are exempt** and survive (value held in `ClipPins`).
- **Mechanism:** the `clip-meta` sidecar records each copy's timestamp + app; a
  **systemd user timer** (`clip-prune.timer`, `OnCalendar`/`OnUnitActiveSec=4h`) runs a
  prune script that deletes unpinned entries whose recorded `ts` is older than the TTL —
  **even when the shell/clipboard is closed** (a real guarantee, not lazy-on-open).
- **Untimestamped legacy entries** (copied before the sidecar): backfill `ts = first-seen`
  on first prune pass, so they age out within TTL of the sidecar starting (no surprise
  bulk deletion). Configurable.
- TTL default **24h**, prune cadence **4h**, both configurable.
- Pure selection logic: `logic.isExpired(ts, now, ttlMs) → bool`.

## 8. Architecture
**modules/clipboard/**
- `Clipboard.qml` — Scope + Overlay mount + `IpcHandler{target:"clipboard"} open/close/toggle` (unchanged shell).
- `ClipboardContent.qml` — **rewrite**: header+search, PINNED/RECENT sections, list-as-hero, footer hints, key routing.
- `ClipList.qml` / `ClipEntry.qml` — dense rows with typographic hierarchy, type icons, thumbnails, mask rendering.
- `ClipPeek.qml` — **new**: the peek/edit overlay (rich render + edit mode), replaces the old `ClipPreview.qml` pane.
- `logic.js` — keep `parseList/detectType/fuzzy/relTime`; **add** `detectSensitive`,
  `maskSecret`, `isExpired`, `prunable(entries, pins, now, ttl)`. Pure, `.pragma library`,
  node-tested via the strip-pragma data:-import pattern (per
  ground rules in ground-decisions-in-docs-no-unilateral-stack-calls).

**services/**
- `Cliphist.qml` — read/copy/decode/delete/wipe + store-on-edit (existing pattern).
- `ClipPins.qml` — durable pins (persisted JSON), exposes `pins`, `toggle`, `isPinned`.
- `ClipMeta.qml` — **load-bearing now**: maps entry-hash → `{ts, app, sensitive}` from the
  sidecar's record; drives the `app · time` column, expiry, and manual-sensitive overrides.

**sidecar + units**
- `~/.config/caelestia/scripts/clip-meta-record.sh` — on each copy (run by the wl-paste
  watcher), record `{hash, ts, app (from hyprctl activewindow), hint}` to the meta store.
- `clip-prune.service` + `clip-prune.timer` (systemd user, every 4h) → prune script using
  `logic.prunable` selection + `cliphist delete`.
- Hyprland autostart: the existing `wl-paste --watch cliphist store` lines gain a parallel
  `wl-paste --watch <clip-meta-record.sh>` (or a wrapper that does both) so meta is recorded.

**config:** `~/.config/caelestia/clipboard.json` (or shell.json section): `ttlHours` (24),
`pruneHours` (4), `neverStoreSecrets` (false), card width.

## 9. Data flow
1. **Copy:** app → Wayland clipboard → `wl-paste --watch` → `cliphist store` (text) **and**
   `clip-meta-record.sh` (ts/app/hint). If hard-mode + secret hint → skip store.
2. **Open:** ClipboardContent merges `ClipPins.pins` (top) + `Cliphist.entries` (deduped),
   joins `ClipMeta` for ts/app/sensitive, applies `detectSensitive`, filters by query/filter.
3. **Prune (every 4h):** timer → prune script → `prunable(entries, pins, now, ttl)` →
   `cliphist delete` each. Pins untouched.

## 10. Risks
- **Secret heuristic** false pos/neg → mitigated by `⌃s` manual toggle + `⌃r` reveal; tune thresholds in tests.
- **No native cliphist timestamps** → sidecar is required (load-bearing). If a sidecar record
  is missing, treat as first-seen-now (safe: never deletes an unknown-age entry early).
- **nixGL GPU readback** for image thumbnails / peek image (`grabToImage`/decode) → use
  decode-to-temp-file + `Image{source:file://}` (no GPU readback); grim-style fallback if needed.
- **Markdown render** — confirm `TextEdit.textFormat: MarkdownText` is available in this Qt
  build; fallback to mono plain text.
- Pruning a pinned item's underlying cliphist entry is **safe** (pin holds the value).

## 11. Testing
- **logic.js (node):** `detectSensitive` (each pattern + entropy bound + negatives),
  `maskSecret`, `isExpired` (boundary at ttl), `prunable` (pins exempt, untimestamped handling),
  plus existing `parseList/detectType/fuzzy/relTime`.
- **Manual/visual (after rebuild→switch→restart):** layout + hierarchy legible at a glance;
  scan/↑↓/↵; `⌃p`/`⌃1–9` pins; `Space` peek (md/code/image render, not black under nixGL);
  `⌃e` edit→copy; `⌃d`+`⌃z`; `⌃⇧⌫` confirm; secret masked in list+peek, `⌃r` reveal, `⌃s` toggle;
  expiry by simulating an old `ts` then running the prune unit.

## 12. Out of scope (carry the principles forward later)
The screenshot picker, annotation editor, and pin-to-screen UIs are separate — but the same
persona, hierarchy, density, contrast, and "rich-or-nothing preview" principles should apply
when they're polished.
