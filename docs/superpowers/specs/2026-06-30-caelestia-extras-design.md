---
title: Caelestia Screenshot Extras (Phase 4)
date: 2026-06-30
status: approved-design
scope: Phase 4 — OCR-to-clipboard, screen colour picker, pin-to-screen
depends-on: Phase 0 Foundation, Phase 2 screenshot-core (capture + notify)
---

# Caelestia Extras — Phase 4

Three small, independent features. Each is shippable alone.

## 1. OCR a region → clipboard
- **Flow:** region select (reuse Phase 2 picker in an `ocr` mode, or
  `grim -g "$(slurp)"` to a temp PNG) → `tesseract <png> - --psm 6` → `wl-copy`
  the text → caelestia notify/toast ("OCR copied: <first line>…").
- **Dep:** `tesseract` is **not installed** — add `tesseract` (+ `tesseract-ocr-eng`
  data) via home-manager `home.packages` (reproducible) in `~/dotfiles`.
- **Entry:** keybind (e.g. `Super+Shift+O`) → `caelestia-shell ipc call picker
  openOcr` (picker captures the rect, hands the PNG to the OCR step) or a small
  `caelestia ocr` script.
- **Risk:** capture backend = whatever Phase 2 Task 2 chose (native vs grim);
  reuse it so OCR isn't black.

## 2. Screen colour picker
- **Decision: wrap `hyprpicker`** (already installed, Wayland-native, robust) —
  not a native screencopy picker (avoids the nixGL readback risk and re-uses a
  battle-tested tool). `hyprpicker -a -f hex` picks a pixel and auto-copies the
  hex.
- **caelestia integration:** a keybind (e.g. `Super+Shift+P`) runs hyprpicker;
  on completion show a caelestia toast/notification with the hex **and a colour
  swatch** (read the copied value from `wl-paste`), so it feels native even
  though capture is hyprpicker.
- **Nice-to-have:** also append to a small recent-colours list (JSON) surfaced in
  the toast; optional, low priority.

## 3. Pin-to-screen
- **Flow:** keep a captured image as a **floating, always-on-top** window on the
  desktop (Windows-Snip-style "pin").
- **Component:** `modules/pin/PinWindow.qml` — a `StyledWindow` on a normal/top
  layer (NOT exclusive keyboard) showing the PNG; **draggable** (move on drag),
  **resizable** (corner handle), **opacity** control, **close** button; supports
  **multiple** pins (a `Variants`/model of open pins).
- **Entry:** Phase 2 notification gains a **"Pin"** action → `caelestia-shell ipc
  call pin open <path>`; also a keybind to pin the last capture.

## Components
- `modules/pin/PinWindow.qml` + `modules/pin/Pin.qml` (Scope/IPC `target:"pin"`,
  `open(path)`), registered in `shell.qml`.
- Scripts/IPC: OCR step (picker `openOcr` or `caelestia` cli `ocr`); colour-picker
  keybind wrapper.
- Config: `home.packages += tesseract`; `hyprland.lua` keybinds + Phase 2 "Pin"
  notify action.

## Testing
- OCR: OCR a known text image → clipboard matches (string contains expected words).
- Colour: pick a known on-screen colour → `wl-paste` == expected hex; toast shows swatch.
- Pin: pin a capture → floating window appears, drag/resize/close work, stays on top.

## Out of scope
None remaining — Phase 4 closes the roadmap (Phases 0–4).
