# Caelestia Screenshot Core Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Extend caelestia's `areapicker` into a full keyboard-first screenshot tool (region/window/fullscreen + freeze + magnifier + smart post-capture), retiring the grim stopgap.

**Architecture:** Build on the existing `modules/areapicker` (already does region/window/freeze + `ScreencopyView` capture + save/copy/notify). Add a swappable capture backend (native screencopy, grim fallback), a fullscreen fast-path, a magnifier loupe, and a richer post-capture notification. Pure geometry/format logic in `shot.js` (node-tested).

**Tech Stack:** Quickshell QML (`ScreencopyView`, `CUtils.saveItem`, `Hypr`, `Screens`), grim (fallback), wl-clipboard, notify-send, node (logic tests).

## Global Constraints
- Reuse Phase 0 foundation (`2026-06-30-caelestia-clipboard-overlay-design.md`): fork at `~/src/caelestia-shell`, `Overlay.qml` primitive, build via `home-manager switch --flake ~/dotfiles`.
- Capture must be **non-black** — every capture verify step asserts `convert <f> -format '%[fx:mean]'` ≥ 0.02.
- Keep changes to upstream `areapicker` files minimal + commented (rebase surface).
- Edit drives: `~/.config/hypr/hyprland.lua` (+ chezmoi) for binds; retire `rofi-screenshot.sh` from chezmoi.
- Branch `feat/caelestia-clipboard-overlay` (or a new `feat/caelestia-screenshot`); commit per task.

---

### Task 1: Capture/geometry logic (`shot.js`) — TDD
**Files:** Create `~/src/caelestia-shell/modules/areapicker/shot.js`, `modules/areapicker/shot.test.mjs`
**Interfaces:** Produces `monitorRect(mon)`, `clampRect(r, screen)`, `shotPath(now)`, `notifyArgs(path, copied)`.

- [ ] **Step 1: Failing tests** — `monitorRect({x,y,width,height,scale})` → screen-local `{x:0,y:0,w,h}`; `shotPath(0)` → `…/Pictures/Screenshots/screenshot-19700101-000000.png`; `notifyArgs(path,true)` includes `--action=open=Open` etc. (write concrete asserts).
- [ ] **Step 2: Run `node --test` → FAIL.**
- [ ] **Step 3: Implement `shot.js`** (pure functions; `.pragma library` + ESM export as in Phase 1 logic.js).
- [ ] **Step 4: `node --test` → PASS.**
- [ ] **Step 5: Commit** `feat(shot): geometry + filename + notify-arg helpers + tests`.

---

### Task 2: Swappable capture backend + nixGL risk gate
**Files:** Modify `modules/areapicker/Picker.qml` (the `save()` function, lines ~74-89)
**Interfaces:** Produces `function capture(rect, outPath, cb)` — default native (`CUtils.saveItem(screencopy, outPath, rect, cb)`); env/flag `CAELESTIA_SHOT_GRIM=1` → `grim` path.

- [ ] **Step 1: Extract `capture(rect, outPath, cb)`** wrapping the existing `CUtils.saveItem(screencopy, tmpfile, Qt.rect(...), cb)` call; have `save()` call `capture()`.
- [ ] **Step 2: Add grim fallback** inside `capture()`: when `Quickshell.env("CAELESTIA_SHOT_GRIM") === "1"`, run `Quickshell.execDetached(["sh","-c", "grim -g '"+x+","+y+" "+w+"x"+h+"' "+outPath])` then `cb(outPath)`.
- [ ] **Step 3: RISK GATE — verify native capture non-black.** Build (`home-manager switch`), trigger a region shot, then:
  `f=$(ls -t ~/Pictures/Screenshots/*.png | head -1); convert "$f" -format '%[fx:mean]\n' info:`
  Expected ≥ 0.02. **If ~0 (black):** set `CAELESTIA_SHOT_GRIM=1` in the shell env (home.nix `home.sessionVariables` or the launcher wrapper), rebuild, re-verify ≥ 0.02, and make grim the default backend.
- [ ] **Step 4: Commit** `refactor(picker): swappable capture backend (native + grim fallback)` (note in the message which backend verified non-black on this host).

---

### Task 3: Fullscreen / focused-monitor mode
**Files:** Modify `modules/areapicker/AreaPicker.qml` (loader flag + IPC + shortcut), `modules/areapicker/Picker.qml` (fast-path)
**Interfaces:** Consumes `shot.js` `monitorRect`. Produces IPC `picker.openFullscreen()`.

- [ ] **Step 1:** Add `property bool fullscreen` to the `LazyLoader`; add `IpcHandler` `function openFullscreen(): void { fullscreen=true; freeze=false; closing=false; activeAsync=true }`; add `CustomShortcut { name: "screenshotFullscreen" }` mirroring the existing ones.
- [ ] **Step 2:** In `Picker.qml` `Component.onCompleted`, if `loader.fullscreen`: set rect = focused monitor (`monitorRect(Hypr.monitorFor(screen)…)`), then `save()` immediately (skip interactive select); ensure magnifier/select UI is hidden.
- [ ] **Step 3:** Build; `caelestia-shell ipc call picker openFullscreen`; verify a full-monitor PNG saved + non-black (≥0.02) + on clipboard.
- [ ] **Step 4: Commit** `feat(picker): fullscreen/focused-monitor capture mode`.

---

### Task 4: Magnifier loupe
**Files:** Create `modules/areapicker/Magnifier.qml`; Modify `Picker.qml` (mount it)
**Interfaces:** Consumes the `screencopy` item + `root.mouseX/mouseY`, `rsx/rsy/sw/sh`.

- [ ] **Step 1:** `Magnifier.qml` — a circular `StyledClippingRect` (~140px) near the cursor showing a `ShaderEffectSource`/zoom of `screencopy` centered on cursor (zoom ~6×), a crosshair, and a `StyledText` label `x,y  w×h` from the picker's properties. Use `Colours.palette.*` for the ring.
- [ ] **Step 2:** Mount in `Picker.qml` (visible when interactive, i.e. `!loader.fullscreen`); offset so it stays on-screen near `mouseX,mouseY`.
- [ ] **Step 3:** Build; region-select; verify the loupe tracks the cursor and shows live coords/size.
- [ ] **Step 4: Commit** `feat(picker): magnifier loupe with live coords`.

---

### Task 5: Smart post-capture (save + copy + rich notification)
**Files:** Modify `Picker.qml` `save()` callback; uses `shot.js` `shotPath`/`notifyArgs`
**Interfaces:** Consumes Task 1 helpers.

- [ ] **Step 1:** Rework the `save()` completion callback: copy to `~/Pictures/Screenshots/screenshot-<ts>.png` (mkdir -p via `shot.js`), `wl-copy --type image/png < path`, then `notify-send` with `notifyArgs(path,true)` (`--action=open=Open`, `edit=Edit`, `copy=Copy path`, `delete=Delete`). Route the chosen action: open→`xdg-open`, edit→`swappy -f <path>` (temporary until Phase 3), copy→`wl-copy <path-string>`, delete→`rm <path>`.
- [ ] **Step 2:** Build; take a shot; verify file saved, clipboard has the image (`wl-paste -l | grep image`), notification shows; click each action and confirm behavior.
- [ ] **Step 3: Commit** `feat(picker): save + copy + actionable notification`.

---

### Task 6: Keyboard triggers + retire grim stopgap
**Files:** Modify `~/.config/hypr/hyprland.lua` (+ chezmoi); optional `modules/areapicker/ModePicker.qml`
**Interfaces:** none (final wiring).

- [ ] **Step 1 (optional): `ModePicker.qml`** — a centered Phase 0 `Overlay` listing Region/Window/Fullscreen/Freeze; arrows+Enter → the matching `picker` IPC call; bind `Super+Print` to it.
- [ ] **Step 2: Binds** in `hyprland.lua` (replace line 147's `rofi/rofi-screenshot.sh`):
  - `Print` → `caelestia-shell ipc call picker open`
  - `Ctrl+Print` → `caelestia-shell ipc call picker openFullscreen`
  - `Alt+Print` → `caelestia-shell ipc call picker open` (window-snap is interactive within it)
  Run `hyprctl reload`.
- [ ] **Step 3:** Verify each bind captures non-black + saves + copies.
- [ ] **Step 4: Retire the stopgap** — `git -C ~/ubuntu-dots rm private_dot_config/rofi/scripts/executable_rofi-screenshot.sh`; remove the live `~/.config/rofi/scripts/rofi-screenshot.sh`.
- [ ] **Step 5: Commit** (dotfiles + ubuntu-dots) `feat(screenshot): caelestia-native capture; retire rofi/grim stopgap`.

---

## Self-review notes
- Spec coverage: §3 fullscreen=Task3, magnifier=Task4, post-capture=Task5, capture engine + risk gate=Task2, triggers/retire=Task6; §6 logic tests=Task1.
- Soft spots to resolve at impl: exact `CUtils.saveItem` signature already confirmed in `Picker.qml:76`; `ShaderEffectSource` vs `qs.components.effects` for the loupe zoom (check `components/effects/`); `Hypr.monitorFor`/offset math (mirror `checkClientRects`); whether `notify-send --action` callback is captured via `Quickshell.execDetached` stdout or a `Process` (use `Process` with `StdioCollector` to read the chosen action key).
- **Hard dependency:** Task 2 risk gate decides the capture backend for all later tasks.
