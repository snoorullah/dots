# Caelestia Annotation Editor Implementation Plan (Phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. **Sequenced 3a (Tasks 1–6) then 3b (Tasks 7–12)** — 3a is shippable on its own.

**Goal:** A native QML post-capture annotation editor (draw/text/highlight/blur/crop/steps + undo/redo), replacing Phase 2's temporary swappy "Edit" action.

**Architecture:** A dedicated `StyledWindow` overlay loads the captured PNG into `EditorCanvas`; a `ToolController` + `MouseArea` edit an ordered annotation model rendered as QML shapes; undo/redo is a command stack; export flattens via `grabToImage` (ImageMagick composite fallback under nixGL). Pure logic in `editor.js` (node-tested).

**Tech Stack:** Quickshell QML (`StyledWindow`, `Shape`/`Canvas`, `ShaderEffect`, `grabToImage`), ImageMagick (`convert`, fallback), wl-clipboard, node (logic tests).

## Global Constraints
- Reuse Phase 0 foundation + Phase 2 post-capture (save+copy+notify helpers, `shot.js`).
- Shape model object: `{id, type, x, y, x2, y2, points:[], color, width, text, n}` (superset; tools use the fields they need). Keep this schema identical across all tasks.
- Export must be **non-black** (verify `convert <f> -format '%[fx:mean]'` ≥ 0.02). Task 6 risk gate picks `grabToImage` vs ImageMagick-composite backend for ALL later tasks.
- New code isolated under `modules/editor/`. IPC `target: "editor"`. Build via `home-manager switch --flake ~/dotfiles`. Commit per task.

---

## Phase 3a — editor shell, canvas, draw tools, undo/redo, export

### Task 1: `editor.js` logic — TDD
**Files:** Create `modules/editor/editor.js`, `modules/editor/editor.test.mjs`
**Interfaces:** `CommandStack()` → `{push(model), undo()->model, redo()->model, canUndo, canRedo}`; `hitTest(model, x, y)->id|null`; `arrowHead(x,y,x2,y2)->points`; `nextStep(model)->int`; `toMagickArgs(model, baseRect)->[args]` (fallback compositor).
- [ ] **Step 1:** Failing tests for undo/redo round-trips, hit-test on a box, arrowHead geometry, nextStep increment, `toMagickArgs` emits `-draw`/`-blur` for sample shapes.
- [ ] **Step 2:** `node --test` → FAIL.
- [ ] **Step 3:** Implement (pure; `.pragma library` + ESM export).
- [ ] **Step 4:** `node --test` → PASS.
- [ ] **Step 5:** Commit `feat(editor): pure logic (undo/redo, hit-test, geometry, magick-emit) + tests`.

### Task 2: Editor window + IPC + base image
**Files:** Create `modules/editor/Editor.qml`; Modify `shell.qml`
**Interfaces:** IPC `editor.open(path: string)`; loads `path` into an `Image`.
- [ ] **Step 1:** `Editor.qml` — Scope + LazyLoader + `Variants(Screens.screens)` + `StyledWindow` (WlrLayer.Overlay, keyboardFocus Exclusive) + `IpcHandler { target:"editor"; function open(path){ root.path=path; activeAsync=true } function close(){…} }`. Body = `Image { source: "file://"+root.path; fillMode: PreserveAspectFit }` placeholder.
- [ ] **Step 2:** Register in `shell.qml` (`import "modules/editor"` + `Editor {}`).
- [ ] **Step 3:** Build; `caelestia-shell ipc call editor open <some.png>` → image shows fullscreen overlay; `close` dismisses.
- [ ] **Step 4:** Commit `feat(editor): overlay window + IPC + base image`.

### Task 3: `EditorCanvas` + `ToolController` + annotation model
**Files:** Create `modules/editor/EditorCanvas.qml`, `modules/editor/ToolController.qml`
**Interfaces:** `ToolController` props `tool, color, width`; `EditorCanvas` holds `property var model: []`, `signal changed()`; a `MouseArea` routes press/move/release to the active tool (no tools yet — just records a transient shape for "pen" to prove the pipeline).
- [ ] **Step 1:** Implement canvas (base image zoom-to-fit + a drawing layer `Repeater` over `model`) + `MouseArea` that, for `tool==="pen"`, appends a points-shape live.
- [ ] **Step 2:** Build; select pen (temp default), drag → a freehand stroke renders.
- [ ] **Step 3:** Commit `feat(editor): canvas + tool controller + model (pen proof)`.

### Task 4: Toolbar (tools, colour, width, undo/redo, export/cancel)
**Files:** Create `modules/editor/Toolbar.qml`; Modify `EditorCanvas`/`Editor` to host it + wire undo/redo to `editor.js CommandStack`.
- [ ] **Step 1:** Toolbar with `IconButton`s (MaterialIcon) for each tool, a colour swatch row (presets + `Colours.palette`), a width `StyledSlider`, undo/redo, crop, export (✓), cancel (✗). Bind selection to `ToolController`. Wire `Ctrl+Z`/`Ctrl+Shift+Z` + buttons to the command stack (push on each completed edit).
- [ ] **Step 2:** Build; switch tools via toolbar + hotkeys; undo/redo removes/restores the pen stroke from Task 3.
- [ ] **Step 3:** Commit `feat(editor): toolbar + colour/width + undo/redo`.

### Task 5: Draw tools — arrow, rectangle, ellipse, line
**Files:** Create `modules/editor/shapes/{Arrow,Box,Ellipse,Line}.qml`; Modify `ToolController`/`EditorCanvas` to handle each.
- [ ] **Step 1:** Each tool: press sets `x,y`; move updates `x2,y2` (live preview); release commits a shape `{type,...,color,width}` + `stack.push`. Render via `Shape`/`ShapePath` (arrow uses `editor.js arrowHead`).
- [ ] **Step 2:** Build; draw each of the 4 shapes; verify live preview + commit + undo.
- [ ] **Step 3:** Commit `feat(editor): arrow/box/ellipse/line tools`.

### Task 6: Export + RISK GATE + wire Phase 2 "Edit"
**Files:** Modify `Editor.qml` (export); Modify Phase 2 `Picker.qml` notify "edit" action → `editor open`.
**Interfaces:** Consumes Phase 2 save/copy/notify + `editor.js toMagickArgs`.
- [ ] **Step 1:** Export via `editorRoot.grabToImage(r => r.saveToFile(outPath))` over the crop rect (full image for now), then Phase 2 save+copy+notify.
- [ ] **Step 2: RISK GATE** — export an annotated shot; `convert <out> -format '%[fx:mean]\n'` ≥ 0.02 AND the annotation is visibly present. **If black/wrong:** switch export to ImageMagick composite using `editor.js toMagickArgs(model, baseRect)` against the base PNG; re-verify. Record which backend in the commit.
- [ ] **Step 3:** Point Phase 2's notification `edit` action at `caelestia-shell ipc call editor open <path>` (replace `swappy -f`).
- [ ] **Step 4:** Build + end-to-end: capture → notification Edit → annotate → export → saved+copied non-black.
- [ ] **Step 5:** Commit `feat(editor): export (+nixGL fallback) + wire Phase 2 Edit action`.

---

## Phase 3b — text, highlighter, blur/redact, crop, steps

### Task 7: Text tool
**Files:** `modules/editor/shapes/TextShape.qml`; Modify controller.
- [ ] Click places a `TextInput`; on commit (Enter/blur) store `{type:"text",x,y,text,color}`; render as `StyledText`. Undo-able. Build+verify+commit `feat(editor): text tool`.

### Task 8: Highlighter
**Files:** Modify shapes/controller.
- [ ] Like pen/box but semi-transparent wide stroke (`color` at ~0.35 alpha, `multiply`-ish look). Build+verify+commit `feat(editor): highlighter`.

### Task 9: Blur / pixelate redact
**Files:** `modules/editor/shapes/Blur.qml`; Modify export.
- [ ] Drag a rect → a `ShaderEffect` (gaussian or pixelate) sampling the base image, clipped to the rect, beneath strokes. **Honor Task 6 gate:** if export backend is ImageMagick, emit `-region <rect> -blur 0x8` (or `-scale` pixelate) via `toMagickArgs`; if shader-export works, ensure the shader is captured by `grabToImage`. Build+verify (redacted region unreadable in export)+commit `feat(editor): blur/redact`.

### Task 10: Crop
**Files:** Modify `EditorCanvas`/`Editor` export.
- [ ] Crop tool draws an adjustable rect (handles); non-destructive; export uses the crop rect as bounds (both `grabToImage` source rect and IM `-crop`). Build+verify (export dimensions == crop)+commit `feat(editor): crop`.

### Task 11: Numbered step markers
**Files:** `modules/editor/shapes/StepMarker.qml`; uses `editor.js nextStep`.
- [ ] Click places an auto-incrementing numbered circle; renumber on undo/delete. Build+verify+commit `feat(editor): numbered step markers`.

### Task 12: Keybind + finalize
**Files:** `~/.config/hypr/hyprland.lua` (+chezmoi).
- [ ] Bind a key (e.g. `Super+Shift+S` or a mode-picker entry) → capture-then-`editor open`. Confirm swappy is no longer referenced (remove from deps if desired). Build+verify+commit `feat(editor): keybind + finalize; drop swappy edit path`.

---

## Self-review notes
- Spec coverage: 3a shell/canvas/toolbar/draw/undo/export = Tasks 2–6; 3b text/highlight/blur/crop/steps = Tasks 7–11; logic+tests = Task 1; risk gate = Task 6; wiring = Task 6/12.
- Soft spots (resolve at impl): `Shape`/`ShapePath` availability in this Quickshell build (else use `Canvas`); `grabToImage` rect API; `ShaderEffect` sampling the base `Image` under nixGL (Task 6/9 gate decides shader vs IM); `TextInput` focus within an exclusive-keyboard layer.
- **Hard dependency:** Task 6 risk gate determines the export/blur backend for Tasks 9–11.
