---
title: Caelestia Clipboard Overlay — Foundation + Clipboard (Phase 0 + Phase 1)
date: 2026-06-30
status: approved-design
scope: Phase 0 (Foundation) + Phase 1 (Clipboard overlay)
supersedes: rofi-clipboard.sh (greenclip), rofi-screenshot.sh (maim) — see Migration
---

# Caelestia Clipboard Overlay — Phase 0 + Phase 1

## 1. Context & problem

The desktop migrated **i3/X11 → Hyprland/Wayland (caelestia)** but the `Super+C`
clipboard menu and `Print` screenshot still call old **X11** rofi scripts:

- `rofi-clipboard.sh` queries **greenclip** (X11 clipboard daemon) — it cannot
  see the Wayland clipboard, so the menu shows stale/partial history. The real,
  complete history (364+ entries, text + images) lives in **cliphist**, fed by
  `wl-paste --type {text,image} --watch cliphist store` (started in
  `hyprland.lua`).
- `rofi-screenshot.sh` used **maim/xclip/xdotool** (X11) → captured the empty
  Xwayland root = **black** images. *(Already mitigated by a grim/slurp stopgap
  — see §9.)*

caelestia-shell (Quickshell/QML) already ships primitives we will build on:
`modules/areapicker/` (screenshot select/freeze, IPC-driven) and a bar
`modules/bar/popouts/ClipWrapper.qml` (clipboard popout). We want richer,
keyboard-first **overlay** widgets that fully replace the rofi scripts.

This is the first of a phased effort. **This spec covers Phase 0 + Phase 1
only.** Phases 2–4 (screenshot capture, annotation editor, OCR/color-picker/
pin-to-screen) are out of scope here (§12) and get their own specs.

## 2. Goals / Non-goals

**Goals**
- A native, keyboard-first **clipboard overlay** in caelestia, opened by
  `Super+C`, that fully replaces `rofi-clipboard.sh` + greenclip.
- Reuse caelestia's design system (colours/rounding/fonts) so it looks native.
- Establish reusable **Foundation** (fork wiring, overlay primitive, IPC) that
  Phase 2+ (screenshot) will reuse.
- Features: image thumbnails + preview pane; pin/favourites + delete/clear;
  type filters + smart detection (URL/colour/code); fuzzy search + keyboard nav;
  per-entry source-app + timestamp via a metadata sidecar.

**Non-goals**
- Screenshot capture / annotation / OCR (Phases 2–4).
- Auto-paste/keystroke injection (copy-to-clipboard only; optional ydotool
  toggle deferred — risky in terminals).
- Cloud sync, cross-device history.

## 3. Phase 0 — Foundation

### 3.1 Fork wiring (Nix)
- `~/dotfiles/flake.nix`: change the `caelestia` input from
  `github:caelestia-dots/shell` to **`path:/home/devsupreme/src/caelestia-shell`**
  (the existing clean clone). The HM module + package both come from this input,
  so pointing it at the clone gets our custom QML automatically.
- Dev loop: edit QML in `~/src/caelestia-shell` → `home-manager switch` → shell
  restarts with changes. The nixGL wrapper (`caelestia-shell-nixgl`) is unchanged.
- Maintenance: `~/src/caelestia-shell` tracks upstream `origin`; rebase our
  module commits on upstream periodically; push to a personal GitHub fork for
  backup.

### 3.2 Design-system reuse
Custom modules import existing caelestia QML — **no new theming**:
- `qs.components` (StyledRect, StyledText, StyledTextField, etc.)
- `qs.services` `Colours` (active scheme) and appearance scales from
  `~/.config/caelestia/shell.json` (font/padding/rounding `scale`).

### 3.3 Shared overlay primitive
New `modules/utils/Overlay.qml`: a centered modal with dim+blur backdrop,
caelestia open/close animations, focus grab, and `Esc`-to-close. Consumed by the
clipboard overlay now and the screenshot widgets later.

### 3.4 IPC + keybind + retiring old tooling
- Add an `IpcHandler` (mirroring `modules/areapicker/AreaPicker.qml`) exposing
  `caelestia-shell ipc call clipboard open` (and `toggle`).
- `hyprland.lua`: rebind `mod .. " + C"` from `rofi/rofi-clipboard.sh` to
  `caelestia-shell ipc call clipboard open`.
- Retire **greenclip**: stop the daemon, remove from autostart, and remove
  `rofi-clipboard.sh` from the chezmoi source (`ubuntu-dots`). The cliphist
  `wl-paste --watch` lines in `hyprland.lua` **stay**.

## 4. Phase 1 — Clipboard overlay UX

Centered, keyboard-first, two-pane (list + live preview):

```
┌────────────────────────  Clipboard  ───────────────────────┐
│  [ Search…                          ]   All Text Img Link ▾ │
├───────────────────────────────┬─────────────────────────────┤
│ 📌 PINNED                      │   ┌───────────────────────┐ │
│  1  ssh prod key…             │   │  preview of selected:  │ │
│ ─────────────────────────     │   │  full text / code mono │ │
│  2  Do you want me to leave…  │   │  / image at size /     │ │
│ ▸3  ▢ image 1920×1080 5.5k    │   │  colour swatch         │ │
│  4  #1e90ff ███              │   └───────────────────────┘ │
│  5  https://github.com/… 🔗   │   src: kitty · 2m ago       │
└───────────────────────────────┴─────────────────────────────┘
 Enter copy · ⇧Enter plain · p pin · d del · ⌃⇧Del wipe · Tab filter
```

**Keys:** type = fuzzy search · `j/k`/↑↓ = move · `Enter` = copy + close ·
`Shift+Enter` = copy as plain text · `1–9` = quick-pick top entries ·
`Tab` = cycle filter · `p` = pin/unpin · `d`/`Del` = delete entry ·
`Ctrl+Shift+Del` = wipe history · `Esc` = close.

**Entry types & smart detection** (regex on decoded content, lazy):
- text → first line, truncated; monospace when it looks like code
- image → thumbnail (id + dimensions + size)
- URL (`^https?://`) → link icon + "Open" action (`xdg-open`)
- hex colour (`^#?[0-9a-fA-F]{6,8}$`) → colour swatch
- `src: <app> · <relative time>` from the metadata sidecar (§6); absent for
  entries copied before the sidecar existed (graceful).

**Action semantics:** selection runs `cliphist decode <id> | wl-copy`
(copy-to-clipboard, then close — you paste with `Ctrl+V` / `Ctrl+Shift+V`).
`Shift+Enter` strips to `text/plain`.

## 5. Components & data flow

**QML (under `~/src/caelestia-shell/modules/clipboard/`)**
- `Clipboard.qml` — IPC entry + wraps `Overlay`.
- `ClipList.qml` — virtualized `ListView` (pins merged on top).
- `ClipEntry.qml` — one row (type-aware rendering).
- `ClipPreview.qml` — right pane; decodes the selected entry on demand.
- `SearchField.qml`, `FilterTabs.qml`.

**Services (`modules/clipboard/services/` or `services/`)**
- `Cliphist.qml` — wraps `cliphist list` (parse `id\tpreview`), `cliphist decode`
  (lazy, per selected/visible row), `cliphist delete`, `cliphist wipe`.
- `Pins.qml` — JSON store `~/.local/state/caelestia/clip-pins.json`
  (cliphist has **no native pin**); stores pinned entries' content (so pins
  survive cliphist wipes); merged on top of the list.
- `ClipMeta.qml` — reads the sidecar (§6).

**Flow:** `ipc clipboard open` → `Overlay` shows → `Cliphist.list()` →
render (pins + history, filtered) → on select, decode → `ClipPreview` + meta
join → `Enter` → decode → `wl-copy` → close.

## 6. Metadata sidecar (source-app + timestamp)

cliphist stores neither timestamp nor source app, so we add a small recorder:

- New watcher(s) alongside the cliphist ones (in `hyprland.lua`), **mirroring the
  cliphist text+image split** so binary images are handled correctly:
  `wl-paste --type text  --watch <recorder>` and
  `wl-paste --type image --watch <recorder>` (recorder reads content on stdin;
  for images it hashes the raw bytes).
- On each clipboard event the recorder computes `sha256` of the content, reads
  the focused app via `hyprctl activewindow -j` (`.class`), and upserts
  `~/.local/state/caelestia/clip-meta.json`:
  `{ "<sha256>": { "ts": <unix>, "app": "<class>" } }`.
- The overlay joins **lazily**: when an entry is decoded for preview, hash it and
  look up meta → show `src: <app> · <relative time>`. No whole-list decode, so
  no performance hit. Pre-existing entries simply show no src/time.
- Bounded: prune meta entries with no matching cliphist id on open (best-effort).

## 7. Error handling & edge cases
- `cliphist` missing/empty → friendly empty state ("Clipboard history is empty").
- image decode failure → placeholder glyph, entry still selectable.
- very large text entries → truncate preview (e.g., 100 KB) with a notice.
- pin store missing/corrupt → treat as empty, recreate; never block the overlay.
- meta JSON corrupt → ignore, recreate.
- overlay opened twice → IPC `open` focuses the existing instance (no dupes).

## 8. Performance
- 364+ entries: virtualized `ListView`; decode thumbnails/preview only for
  visible/selected rows; debounce fuzzy search; cache decoded thumbnails by id
  for the session.

## 9. Migration & rollout
- **Screenshot stopgap (DONE 2026-06-30):** `rofi-screenshot.sh` ported to
  grim/slurp/wl-copy (live + chezmoi source) so `Print` works now; it will be
  superseded by the Phase 2 widget.
- Phase 0+1 rollout: flip the flake input → add modules → `home-manager switch`
  → rebind `Super+C` → stop/disable greenclip → remove `rofi-clipboard.sh` from
  chezmoi. Keep `wl-paste --watch cliphist store` watchers.
- Rollback: revert the flake input to `github:caelestia-dots/shell` +
  `home-manager switch`; re-point `Super+C` if needed.

## 10. Testing
- **Unit-testable logic:** `cliphist list` parsing, pin add/remove/merge,
  smart-detect regexes, meta join — extracted into pure JS/QML helpers and
  tested with a small `qmltest` (or node) harness.
- **Manual UX checklist:** open/close, search, filter tabs, navigate, copy,
  copy-as-plain, pin/unpin persistence, delete, wipe, image thumbnail + preview,
  URL open, colour swatch, src/time appears for new copies.
- QML UI itself isn't easily automated; the service layer carries the test
  weight, UI is verified manually.

## 11. Risks & open questions
- **Upstream rebase drift:** importing `qs.components`/`qs.services` couples us to
  upstream module paths; rebases may need small fixups. Mitigation: keep custom
  code isolated under `modules/clipboard/` + `modules/utils/Overlay.qml`.
- **nixGL + Quickshell image rendering:** thumbnails rely on QML image loading
  under nixGL; if readback/rendering misbehaves, fall back to a file-path
  `Image` (decode to a temp file) instead of inline data.
- **`wl-paste --watch` exec semantics:** verify the recorder reliably receives
  content on stdin for both the text and image watchers (§6), and that binary
  image hashing matches what cliphist stored (so the meta join hits).
- Open: keep `src/time` if the sidecar proves noisy? (default: keep, per
  approval).

## 12. Out of scope (future phases, own specs)
- **Phase 2:** screenshot capture (region/window/fullscreen/freeze + magnifier) +
  smart post-capture actions, replacing the grim stopgap.
- **Phase 3:** native QML annotation editor (arrows/text/blur/crop/steps).
- **Phase 4:** OCR (tesseract), screen colour picker, pin-to-screen.
- Note: terminals (incl. Claude Code) can't paste images; screenshot→Claude
  workflow will be save-to-file + path reference (addressed in Phase 2).
