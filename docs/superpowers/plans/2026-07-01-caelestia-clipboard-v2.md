# Caelestia Clipboard v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Spec: `docs/superpowers/specs/2026-07-01-caelestia-clipboard-v2-design.md`.

**Goal:** Rebuild the caelestia clipboard overlay around scan-first retrieval, with pins-as-speed-dial, on-demand rich peek, edit-in-place, delete+undo, secret masking, and 24h auto-expiry.

**Architecture:** Pure logic in `modules/clipboard/logic.js` (node-tested). UI in `modules/clipboard/` (ClipboardContent rewrite + ClipList/ClipEntry + new ClipPeek). State in `services/` (Cliphist, ClipPins durable, ClipMeta load-bearing). Timestamps + expiry driven by a `clip-meta` sidecar + a systemd user prune timer.

**Tech Stack:** Quickshell QML (Qt6), `.pragma library` JS, node `--test`, cliphist + wl-clipboard, systemd user units, grim (thumbnail fallback).

## Global Constraints
- JS logic files = **`.pragma library` + plain `function` decls** (NOT ESM `export`/CommonJS). Tests load via strip-pragma `data:`-module import (see existing `logic.test.mjs`). Ref: memory `ground-decisions-in-docs-no-unilateral-stack-calls`.
- Any Hyprland keybind/script invoking the shell uses the **full path** `$HOME/.nix-profile/bin/caelestia-shell` (Hyprland's PATH lacks `~/.nix-profile/bin`).
- Secret masking applies **everywhere** (list + peek + edit pre-fill stays masked until reveal).
- TTL default **24h**; prune cadence **4h**; both configurable. Pins are exempt from expiry.
- Each landing requires the cycle: `nix build` the fork → `home-manager switch` (activate needs `/nix/var/nix/profiles/default/bin` on PATH) → restart shell (`pkill -9 -f 'quicksh[e]ll'` + `setsid -f … ~/.nix-profile/bin/caelestia-shell`). Re-lock dotfiles flake to the new rev.
- Commit per task on `feat/caelestia-widgets` (fork `shaiknoorullah/shell`).

---

### Task 1: `logic.js` pure additions (TDD)
**Files:** Modify `modules/clipboard/logic.js`; Modify `modules/clipboard/logic.test.mjs`
**Interfaces (produces):**
- `detectSensitive(text, hint) -> bool`
- `maskSecret(text) -> string`  // e.g. `"•••••••• · secret · 24 chars"`
- `isExpired(tsMs, nowMs, ttlMs) -> bool`
- `prunable(entries, pinnedRawSet, nowMs, ttlMs) -> string[]`  // raws to delete

- [ ] **Step 1 — failing tests.** Add to `logic.test.mjs` (extend the strip-pragma loader's export list):
  - `detectSensitive`: true for JWT `eyJabc.eyJdef.sig`, `AKIA1234567890ABCD`, `ghp_` + 36 chars, `sk-` + 40, `-----BEGIN OPENSSH PRIVATE KEY-----`, a 32-char high-entropy token, and any input with `hint === "secret"`; false for `"hello world"`, a URL, a short word, a normal sentence.
  - `maskSecret("abcdefghijklmnopqrstuvwx")` contains `"secret"` and the char count `24`, and does **not** contain the raw text.
  - `isExpired(0, ttl+1, ttl) === true`; `isExpired(0, ttl-1, ttl) === false`.
  - `prunable`: given 3 entries (one pinned, one older than ttl, one fresh), returns only the unpinned-and-expired raw.
- [ ] **Step 2 — run, expect FAIL:** `node --test modules/clipboard/logic.test.mjs`.
- [ ] **Step 3 — implement** the four functions (pure; entropy via Shannon over char set; mask = bullets + ` · secret · ${n} chars`).
- [ ] **Step 4 — run, expect PASS** (all suites green).
- [ ] **Step 5 — commit** `feat(clip): logic for secret-detection, masking, expiry, prune (+tests)`.

### Task 2: ClipMeta sidecar + service
**Files:** Create `~/.config/caelestia/scripts/clip-meta-record.sh`; Modify `services/ClipMeta.qml`; Modify Hyprland autostart (`~/.config/hypr/hyprland.lua`).
**Interfaces:** meta store JSON `~/.local/state/caelestia/clip-meta.json`: `{ "<sha256(raw)>": { ts, app, hint, sensitive? } }`. `ClipMeta.metaFor(raw) -> {ts, app, sensitive}`; `ClipMeta.setSensitive(raw, bool)`.
- [ ] **Step 1:** `clip-meta-record.sh` reads stdin (the clipboard text via `wl-paste --watch`), computes sha256, captures `ts=$(date +%s)`, `app` from `hyprctl activewindow -j` (class), the password-manager hint if available, and upserts the JSON entry (jq).
- [ ] **Step 2:** add an autostart line paralleling the existing cliphist watchers: `wl-paste --type text --watch ~/.config/caelestia/scripts/clip-meta-record.sh` (and image variant). Use full paths.
- [ ] **Step 3:** `ClipMeta.qml` (Singleton) loads the JSON (FileView/Process), exposes `metaFor`, `setSensitive` (writes back), reactive on file change.
- [ ] **Step 4 — verify:** copy something; confirm a JSON entry with ts+app appears.
- [ ] **Step 5 — commit** `feat(clip): clip-meta sidecar + ClipMeta service (ts/app/sensitive)`.

### Task 3: systemd prune timer
**Files:** Create `~/.config/systemd/user/clip-prune.service`, `clip-prune.timer`; Create `~/.config/caelestia/scripts/clip-prune.sh`.
- [ ] **Step 1:** `clip-prune.sh` — read cliphist list + meta JSON + pins JSON, compute prunable (mirror `logic.prunable`; TTL from config, default 24h), `cliphist delete` each; backfill missing ts as now.
- [ ] **Step 2:** `clip-prune.timer` `OnUnitActiveSec=4h` + `OnBootSec=10m`, `Persistent=true`; `clip-prune.service` Type=oneshot runs the script.
- [ ] **Step 3:** `systemctl --user enable --now clip-prune.timer`.
- [ ] **Step 4 — verify:** seed a meta ts 25h old for a test entry, run `systemctl --user start clip-prune.service`, confirm it's gone and pinned items survive.
- [ ] **Step 5 — commit** `feat(clip): 24h auto-expiry via systemd prune timer (4h cadence)`.

### Task 4: ClipPins durable persistence
**Files:** Modify `services/ClipPins.qml`
- [ ] **Step 1:** ensure pins persist to `~/.local/state/caelestia/clip-pins.json` (`{raw, preview, ts, sensitive}`), loaded on start, written on `toggle`. Confirm a pinned value survives a cliphist wipe + reboot (independent store).
- [ ] **Step 2 — verify:** pin an entry, `cliphist wipe`, reopen → pin still present + copyable.
- [ ] **Step 3 — commit** `feat(clip): durable pin persistence (survives wipe/prune/reboot)`.

### Task 5: ClipboardContent rewrite (layout)
**Files:** Modify `modules/clipboard/ClipboardContent.qml`
- [ ] **Step 1:** new layout — compact card (`width: Math.min(460, parent.width*0.5)`, height fits content capped `parent.height*0.7`); ColumnLayout: header (title + count), thin search line (+ filter tag), `PINNED` section (visible iff pins), `RECENT` section (the scrollable hero), footer hints (readable: `m3onSurfaceVariant`+).
- [ ] **Step 2:** merged model = pins (top) + history; join ClipMeta; apply `detectSensitive`; fuzzy filter; Tab cycles filter with a header tag.
- [ ] **Step 3 — build/switch/restart; verify** card is compact, hierarchy legible, hints readable, no dead pane.
- [ ] **Step 4 — commit** `feat(clip): v2 layout — compact, pinned-section, list-as-hero, readable hints`.

### Task 6: ClipList + ClipEntry (rows, hierarchy, thumbnails, masking)
**Files:** Modify `modules/clipboard/ClipList.qml`, `modules/clipboard/ClipEntry.qml`
- [ ] **Step 1:** dense row: `[type-icon] content(primary weight, elided) · app·time(dim, right)`; selected = accent left-bar + bg + brighter; pinned = 📌 + subtle tint. Type icons per `detectType` (+command/secret).
- [ ] **Step 2:** image entries → thumbnail (decode via `cliphist decode` to temp file → `Image{source:file://}`, NO grabToImage — avoids nixGL black). Secret entries → `maskSecret` text + 🔒.
- [ ] **Step 3 — build/verify** ~8–12 rows visible, image thumbnails render, secrets masked, scan rhythm clear.
- [ ] **Step 4 — commit** `feat(clip): dense rows w/ type icons, thumbnails, masking, typographic hierarchy`.

### Task 7: ClipPeek (rich preview + edit)
**Files:** Create `modules/clipboard/ClipPeek.qml`; remove `modules/clipboard/ClipPreview.qml`; Modify `ClipboardContent.qml` (host the peek)
- [ ] **Step 1:** centred overlay; render by type — markdown via `TextEdit{textFormat:MarkdownText}` (fallback mono if unavailable), code mono, image full `Image`, link url+title. Masked secret stays masked until `⌃r`.
- [ ] **Step 2:** edit mode — `TextArea` pre-filled (masked secrets require reveal first); `↵`/`⌃↵` → `Cliphist.copy(edited)`; `Esc` cancel.
- [ ] **Step 3 — build/verify** `Space` peeks (md/code/image non-black), `⌃e` edits→copies.
- [ ] **Step 4 — commit** `feat(clip): ClipPeek overlay — rich preview + edit-in-place`.

### Task 8: Interactions / keymap
**Files:** Modify `modules/clipboard/ClipboardContent.qml` (key routing)
- [ ] **Step 1:** wire the full keymap (spec §6): ↑↓/⌃jk nav, ↵ copy, `⌃1–9` paste Nth pin, `⌃p` pin toggle, `Space` peek, `⌃e` edit, `⌃d` delete + `⌃z` undo toast (~5s, re-store), `⌃⇧⌫` wipe (confirm dialog), `⌃r` reveal (temp), `⌃s` sensitive toggle (`ClipMeta.setSensitive`), `⇥` filter cycle, `?` help, `Esc` close.
- [ ] **Step 2 — build/verify** each binding end-to-end (esp. delete+undo, speed-dial, reveal).
- [ ] **Step 3 — commit** `feat(clip): full keymap — pins speed-dial, edit, delete+undo, reveal/mark, filter`.

### Task 9: Config + keybind
**Files:** Create `~/.config/caelestia/clipboard.json` (defaults); Modify config reads; (`hyprland.lua` `Super+C → clipboard toggle` already wired)
- [ ] **Step 1:** config: `ttlHours:24, pruneHours:4, neverStoreSecrets:false, cardWidth:460`. Wire reads in ClipboardContent + prune script + sidecar.
- [ ] **Step 2 — commit** `feat(clip): clipboard config (ttl, prune, never-store, width)`.

### Task 10: Build, switch, ship, verify
- [ ] **Step 1:** `nix build` fork `#with-cli`; re-lock dotfiles flake to new rev; `home-manager switch`; restart shell.
- [ ] **Step 2 — full manual pass:** scan/nav/copy; pins + `⌃1–9`; peek (md/code/image non-black under nixGL); edit; delete+undo; wipe confirm; secret masked+reveal+mark; expiry (seed old ts → run prune unit). Confirm card is compact + legible.
- [ ] **Step 3 — commit** `chore(clip): ship v2 (build + lock + verified)`.

---

## Self-review
- **Spec coverage:** layout=T5, rows/hierarchy/thumbnails/mask=T6, peek+edit=T7, keymap/pins/delete/reveal=T8, secrets=T1+T6+T8, expiry=T1+T2+T3, durable pins=T4, config=T9, ship=T10. ✓
- **Risks carried:** nixGL image render → decode-to-file not grabToImage (T6); markdown availability → mono fallback (T7); secret heuristic tuning → tests + manual toggle (T1/T8); legacy untimestamped entries → backfill-now (T3).
- **Type consistency:** `detectSensitive/maskSecret/isExpired/prunable` signatures fixed in T1 and consumed unchanged in T3/T6/T7/T8.
