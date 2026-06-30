---
title: Caelestia Annotation Editor (Phase 3)
date: 2026-06-30
status: approved-design
scope: Phase 3 — native QML annotation editor (post-capture)
depends-on: Phase 0 Foundation, Phase 2 screenshot-core (capture + post-capture)
replaces: the temporary "Edit → swappy" action from Phase 2
---

# Caelestia Annotation Editor — Phase 3

## 1. Context & decision
Phase 2 captures + saves + copies, with a temporary "Edit → `swappy`" action.
Phase 3 replaces that with a **native QML annotation editor** so the experience
stays inside caelestia (consistent theme, keybinds, no external window).

**Decision: native QML, not satty/swappy wrap.** Rationale: the project goal is
native caelestia widgets; an external editor breaks that. `satty` remains a
documented escape hatch only if a specific tool proves infeasible under nixGL
(see §6 risks).

This is the largest phase. It is **sub-sequenced** (3a / 3b) so each part is
shippable; the plan reflects this.

## 2. Goals / Non-goals
**Goals (3a):** an editor overlay that loads the captured PNG onto a canvas with
a tool palette + colour/size picker; tools: **select/move, arrow, rectangle,
ellipse, line, freehand pen**; **undo/redo**; **export** (flatten → save + copy
+ notify, reusing Phase 2 post-capture).
**Goals (3b):** **text**, **highlighter** (semi-transparent), **blur/pixelate
redact**, **crop**, **numbered step markers**.
**Non-goals:** layers/groups, vector re-editing after export, OCR/colour-picker
(Phase 4), multi-image sessions.

## 3. Architecture
- **Entry:** Phase 2's notification "Edit" action and a keybind both call
  `caelestia-shell ipc call editor open <path>`; optional "annotate after
  capture" flag.
- **Window:** dedicated `StyledWindow` overlay (mirrors areapicker layering) —
  larger working area than a centered modal; reuses Phase 0 theming.
- **Canvas model:** the base `Image` (captured PNG) + an ordered **annotation
  model** (`ListModel`/JS array of shape objects `{type, x, y, x2, y2, points,
  color, width, text, ...}`). A drawing layer renders shapes (per-shape
  `Item`/`Shape` or a single `Canvas`); the live tool draws into the same model.
- **Undo/redo:** an append-only command stack over the annotation model
  (`push`/`undo`/`redo`); pure logic in `editor.js` (node-tested).
- **Tools:** a `ToolController` (current tool, colour, stroke width) drives a
  `MouseArea` over the canvas; each tool maps press/move/release → model edits.
- **Blur/redact:** a `ShaderEffect` (gaussian/pixelate) sampling the base image,
  masked to the redaction rects, composited beneath strokes.
- **Crop:** adjustable rect that sets the export bounds (non-destructive until
  export).
- **Text:** an in-canvas `TextInput` placed on click, committed to a text shape.
- **Export:** `editorRoot.grabToImage(result => result.saveToFile(path))` over
  the crop rect → then Phase 2's save+copy+notify. **Fallback (§6):** if
  `grabToImage` is black/wrong under nixGL, composite server-side: emit the shape
  model as ImageMagick `convert -draw`/`-blur` ops against the base PNG.

## 4. Components
- `modules/editor/Editor.qml` — Scope + LazyLoader + window + IPC (`target:
  "editor"`, `open(path)`).
- `modules/editor/EditorCanvas.qml` — base image + drawing layer + tool MouseArea.
- `modules/editor/Toolbar.qml` — tool buttons (MaterialIcon), colour + width pickers (reuse `qs.components.controls`).
- `modules/editor/shapes/` — `Arrow.qml`, `Box.qml`, `Ellipse.qml`, `Line.qml`,
  `Pen.qml` (3a); `TextShape.qml`, `Highlight.qml`, `Blur.qml`, `StepMarker.qml` (3b).
- `modules/editor/editor.js` — pure: command stack (undo/redo), hit-testing for
  select/move, arrow geometry, step-number assignment, ImageMagick op-emit
  (fallback). node-tested.
- `services/` — none new (reuse Phase 2 save/copy/notify helpers).
- Config: keybind for editor; Phase 2 "Edit" action → `editor open`.

## 5. UX
Toolbar (top): tools + colour swatch + width slider + undo/redo + crop + export
(✓) + cancel (✗). Canvas centered, zoom-to-fit with optional zoom. Keys:
`v/a/r/e/l/p/t/h/b/c/s` tool hotkeys, `Ctrl+Z`/`Ctrl+Shift+Z` undo/redo,
`Enter`=export, `Esc`=cancel, number keys cycle step markers. Colour palette from
`Colours.palette` + a few presets (red/yellow/green/blue/black/white).

## 6. Risks
- **nixGL + `grabToImage`/`ShaderEffect`:** GPU readback may be black/incorrect
  (same family as the screencopy risk). **Gate in 3a:** verify a flattened export
  is non-black; if not, switch export to the **ImageMagick server-side composite**
  path (model already serializable via `editor.js`), and implement blur as
  `convert -region <rect> -blur` instead of a shader.
- **Scope creep:** 3b tools (esp. blur + crop + text) are individually nontrivial;
  each is its own task with its own verify so partial delivery is fine.
- **Upstream rebase:** new isolated `modules/editor/` — low coupling (good).

## 7. Testing
- `editor.js` pure logic (undo/redo stack, hit-test, arrow/step geometry, IM op
  emit) → node tests.
- Manual per tool: draw → appears → undo removes → redo restores → export
  produces a non-black PNG containing the annotation (assert mean ≥ 0.02 and
  eyeball), saved + copied.

## 8. Out of scope
Phase 4 (OCR, colour picker, pin-to-screen).
