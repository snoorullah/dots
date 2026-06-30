---
title: Caelestia Screenshot Core (Phase 2)
date: 2026-06-30
status: approved-design
scope: Phase 2 — capture modes + magnifier + smart post-capture; extends modules/areapicker
depends-on: 2026-06-30-caelestia-clipboard-overlay-design.md (Phase 0 Foundation)
supersedes: rofi-screenshot.sh (grim stopgap)
---

# Caelestia Screenshot Core — Phase 2

## 1. Context
caelestia's `modules/areapicker` already implements most screenshot capture:
region drag, **window-snap** (via `Hypr.toplevels`/`checkClientRects`), **freeze**
mode, native **`ScreencopyView`** capture + `CUtils.saveItem(rect)`, then
`wl-copy --type image/png` + `notify-send` (clipboard mode) or `swappy` (edit
mode). `Print`/screenshot is exposed via `CustomShortcut`s + the `picker` IPC.

Phase 2 **extends** this rather than rebuilding, and retires the interim
`rofi-screenshot.sh` grim stopgap (Phase 0/1 era). The native editor that
replaces `swappy` arrives in Phase 3.

## 2. Goals / Non-goals
**Goals**
- Add a **fullscreen / focused-monitor** capture mode (no selection).
- Add a **magnifier loupe** during region select (zoom + live pixel coords +
  edge snapping) for precise edges.
- **Smart post-capture:** always save (timestamped, `~/Pictures/Screenshots`)
  **and** copy to clipboard, with a rich notification offering
  **Open / Edit / Copy-path / Delete**.
- **Keyboard-first triggers:** `Print` → region; `Ctrl+Print` → fullscreen;
  `Alt+Print` → window; optional mode-picker overlay (reuses Phase 0 `Overlay`).
- Retire `rofi-screenshot.sh` + remove from chezmoi.

**Non-goals**
- Annotation editing (Phase 3 — keep `swappy` as the temporary "Edit" target).
- OCR / colour-picker / pin-to-screen (Phase 4).

## 3. Design
- **Capture engine:** reuse `ScreencopyView` + `CUtils.saveItem`. **Risk gate
  (§5):** verify it is not black under the nixGL wrapper; if black, fall back to
  `grim` (`grim -g "<x,y wxh>"` for region/window, `grim -o <monitor>` for
  fullscreen) behind the same `save()` interface.
- **Fullscreen mode:** a `loader` flag `fullscreen` that, on open, sets the
  selection rect to the focused monitor and immediately calls `save()` (skips
  interactive select). Focused monitor via `Hypr`/`Screens`.
- **Magnifier loupe (`modules/areapicker/Magnifier.qml`):** a small circular
  zoom of the frozen `screencopy` around the cursor, with a crosshair + a label
  showing `x,y` and current `w×h`. Visible during interactive select; hidden in
  fullscreen mode.
- **Post-capture (`save()` rework):** always write to
  `~/Pictures/Screenshots/screenshot-<ts>.png` (mkdir -p) AND `wl-copy`; then
  `notify-send` with `--action` Open (`xdg-open`), Edit (`swappy -f` for now),
  Copy-path (`wl-copy` the path string), Delete (`rm`). Reuse caelestia's
  notify pattern (`Quickshell.execDetached`).
- **Mode picker (optional overlay):** small centered `Overlay` (Phase 0) listing
  Region / Window / Fullscreen / Freeze, keyboard-selectable; bound to a single
  key (e.g. `Super+Print`). Direct binds cover the common modes without it.

## 4. Components
- Modify `modules/areapicker/AreaPicker.qml` — add `fullscreen` loader flag + IPC
  `openFullscreen()` + `CustomShortcut`s for the new modes.
- Modify `modules/areapicker/Picker.qml` — fullscreen fast-path; mount Magnifier;
  rework `save()` for save+copy+rich-notify; grim fallback behind a flag.
- Create `modules/areapicker/Magnifier.qml`.
- Create (optional) `modules/areapicker/ModePicker.qml` (uses Phase 0 `Overlay`).
- Config: `hyprland.lua` Print binds → `caelestia-shell ipc call picker …`;
  remove `rofi-screenshot.sh` (chezmoi).

## 5. Risks
- **nixGL + `ScreencopyView` = black?** Must verify on this host (the earlier
  black shots were maim/X11, not areapicker — areapicker is unverified here).
  Mitigation: grim fallback (already proven non-black, mean≈0.21) behind the
  `save()` interface; make the capture backend a single swappable function.
- **Multi-monitor coords:** `CUtils.saveItem` rect is screen-local; fullscreen
  must use the focused monitor's geometry (mirror `checkClientRects` offset math).
- **Upstream rebase:** changes touch upstream `areapicker` files (higher rebase
  surface than Phase 1's isolated module). Keep diffs minimal + well-commented.

## 6. Testing
- Pure logic (rect math for fullscreen/window geometry, filename/timestamp,
  notify action routing) → extract to `modules/areapicker/shot.js` + node tests.
- Manual: each mode produces a **non-black** PNG (assert `convert <f> -format
  '%[fx:mean]'` > 0.02 in the verify step), saved + on clipboard; notification
  actions work; magnifier tracks cursor; Print/Ctrl+Print/Alt+Print bound.

## 7. Rollout
`home-manager switch` → verify capture non-black (risk gate) → rebind Print
family → remove `rofi-screenshot.sh` from chezmoi. Keep `swappy` installed until
Phase 3.

## 8. Out of scope
Phase 3 (annotation editor, replaces the swappy "Edit" action), Phase 4
(OCR/colour-picker/pin-to-screen).
