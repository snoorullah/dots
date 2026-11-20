// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The Alt+Tab life cycle as a pure state machine. The shell turns three inputs into calls:
// the Tab bind (press), the Alt release (release), and a timer (tick). Each returns the next
// state and the one thing the shell must do.
//   idle -> pending (first press) -> shown (150 ms later, still held) -> idle (release / cancel)
//   a release while pending is a quick flip: previous window, nothing was ever drawn.
.pragma library

var FLIP_MS = 150

function start() { return { phase: "idle", t0: 0, dir: 1 } }

function press(f, now, dir) {
  if (f.phase === "idle") return { f: { phase: "pending", t0: now, dir: dir }, act: { type: "pending" } }
  if (f.phase === "pending") return { f: { phase: "pending", t0: f.t0, dir: dir }, act: { type: "none" } }
  return { f: f, act: { type: "move", d: dir } }
}

function tick(f, now) {
  if (f.phase === "pending" && now - f.t0 >= FLIP_MS)
    return { f: { phase: "shown", t0: f.t0, dir: f.dir }, act: { type: "show", d: f.dir } }
  return { f: f, act: { type: "none" } }
}

function release(f, now) {
  if (f.phase === "pending") return { f: start(), act: { type: "flip", d: f.dir } }
  if (f.phase === "shown") return { f: start(), act: { type: "commit" } }
  return { f: f, act: { type: "none" } }
}

function cancel(f) {
  return { f: start(), act: { type: f.phase === "shown" ? "hide" : "none" } }
}
