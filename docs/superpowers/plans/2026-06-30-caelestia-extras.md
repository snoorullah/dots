# Caelestia Extras Implementation Plan (Phase 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Three independent features — any order.

**Goal:** OCR-region-to-clipboard, a screen colour picker, and pin-to-screen floating captures — closing the caelestia screenshot/clipboard roadmap.

**Architecture:** OCR reuses the Phase 2 picker capture + tesseract; colour picker wraps the installed `hyprpicker` with a caelestia toast; pin-to-screen is a native floating `StyledWindow`. 

**Tech Stack:** Quickshell QML, tesseract (added via home-manager), hyprpicker, wl-clipboard, notify-send.

## Global Constraints
- Reuse Phase 0 foundation + Phase 2 capture backend (whatever Task 2 of Phase 2 chose — native vs grim). Build via `home-manager switch --flake ~/dotfiles`. Commit per task. New QML isolated under `modules/pin/`.

---

### Task 1: OCR region → clipboard
**Files:** Modify `~/dotfiles/home.nix` (`home.packages += tesseract`); Modify `modules/areapicker/AreaPicker.qml` (+`ocr` flag + IPC `openOcr`), `modules/areapicker/Picker.qml` (`save()` OCR branch); Modify `hyprland.lua` (keybind).
- [ ] **Step 1:** Add `pkgs.tesseract` to `home.packages` in `home.nix`; `home-manager switch`; verify `tesseract --version` + `tesseract --list-langs` includes `eng`.
- [ ] **Step 2:** Add `property bool ocr` to the picker `LazyLoader` + `IpcHandler.openOcr()` (sets `ocr=true`); in `Picker.qml` `save()` completion, when `loader.ocr`: run `Quickshell.execDetached(["sh","-c","tesseract "+path+" - --psm 6 | wl-copy && notify-send -a caelestia 'OCR copied' \"$(wl-paste | head -1)\""])` instead of the image copy.
- [ ] **Step 3:** Bind `Super+Shift+O` → `caelestia-shell ipc call picker openOcr`.
- [ ] **Step 4: Verify** — open a window with known text, `Super+Shift+O`, select it, then `wl-paste` → contains the expected words.
- [ ] **Step 5: Commit** `feat(extras): OCR region to clipboard (tesseract)`.

---

### Task 2: Screen colour picker (wrap hyprpicker)
**Files:** Modify `hyprland.lua` (keybind); optional `modules/osd` toast or reuse caelestia notify.
- [ ] **Step 1:** Bind `Super+Shift+P` → `caelestia-shell ipc call picker openColor` **or** (simpler) a direct exec: `hl.dsp.exec_cmd("sh -c 'hyprpicker -a -f hex && notify-send -a caelestia -i color \"Colour copied\" \"$(wl-paste)\"'")`. Prefer the direct exec (no areapicker change) unless a native swatch toast is wanted.
- [ ] **Step 2 (optional native swatch):** add a small caelestia toast component that reads `wl-paste`, shows a `StyledRect { color: hex }` + the hex for ~3s. Skip if the notify icon suffices.
- [ ] **Step 3: Verify** — `Super+Shift+P`, click a known colour, `wl-paste` == expected hex; toast/notification shows it.
- [ ] **Step 4: Commit** `feat(extras): screen colour picker (hyprpicker + caelestia toast)`.

---

### Task 3: Pin-to-screen floating window
**Files:** Create `modules/pin/Pin.qml`, `modules/pin/PinWindow.qml`; Modify `shell.qml`.
**Interfaces:** IPC `pin.open(path)` + `pin.closeAll()`; supports multiple pins.
- [ ] **Step 1:** `Pin.qml` — Scope holding a `property var pins: []` (paths) + `IpcHandler { target:"pin"; function open(path){ pins = [...pins, path] } function closeAll(){ pins = [] } }` + a `Variants { model: root.pins }` of `PinWindow`.
- [ ] **Step 2:** `PinWindow.qml` — a `StyledWindow` (WlrLayer.Top, keyboardFocus None) sized to the image; `Image { source:"file://"+modelData }`; a `MouseArea` drag moves the window (`WlrLayershell` margins or `anchors` offset); a corner resize handle scales; a close `IconButton`; an opacity slider on hover. Always-on-top.
- [ ] **Step 3:** Register in `shell.qml` (`import "modules/pin"` + `Pin {}`).
- [ ] **Step 4: Verify** — `caelestia-shell ipc call pin open <some.png>` → floating image appears on top; drag/resize/close work; open a second pin → both coexist.
- [ ] **Step 5: Commit** `feat(extras): pin-to-screen floating captures`.

---

### Task 4: Wire entry points
**Files:** Modify Phase 2 `Picker.qml` notify (add "Pin" action); `hyprland.lua` (pin-last keybind).
- [ ] **Step 1:** Add a `--action=pin=Pin` to the Phase 2 post-capture notification; route → `caelestia-shell ipc call pin open <path>`.
- [ ] **Step 2:** Bind a key (e.g. `Super+Shift+Print`) → capture (fullscreen/region) then `pin open` the result.
- [ ] **Step 3: Verify** — capture → notification "Pin" → floating pin appears; keybind pins a fresh capture.
- [ ] **Step 4: Commit** `feat(extras): pin/OCR/colour entry points + finalize`.

---

## Self-review notes
- Spec coverage: OCR=Task1, colour=Task2, pin=Task3, wiring=Task4.
- Soft spots: `WlrLayer.Top` + drag-to-move semantics for a floating layer window (may need `anchors` + margin math rather than a free move; check Quickshell layershell positioning); tesseract `--psm` choice per content; whether hyprpicker needs `--no-fancy` under the wrapper.
- All three are independent — partial delivery (e.g. just OCR) is fine.
