// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// argv builders for the switcher's Hyprland actions. Hyprland 0.56 runs a Lua config and
// takes hl.dsp.* expressions as the dispatch payload (services/Hypr.qml does the same for
// focus). Every value is validated before it joins a string; each result is an argv array.
.pragma library

function ws(n) {
  var id = parseInt(n)
  return id > 0 && String(id) === String(n).trim() ? id : -1
}
function addrOk(a) { return /^0x[0-9a-f]{1,16}$/.test(String(a)) }

function focusExpr(id) { return 'hl.dsp.focus({ workspace = "' + id + '" })' }
function focusWinExpr(addr) { return 'hl.dsp.focus({ window = "address:' + addr + '" })' }
function moveExpr(id, follow) { return 'hl.dsp.window.move({ workspace = "' + id + '", follow = ' + (follow ? "true" : "false") + ' })' }

function focusWs(n) {
  var id = ws(n)
  return id < 0 ? null : ["hyprctl", "dispatch", focusExpr(id)]
}

function focusWin(addr) {
  return addrOk(addr) ? ["hyprctl", "dispatch", focusWinExpr(addr)] : null
}

// the active window, or the window at addr (focus it first, in one batch so they stay in order)
function moveWin(addr, n, follow) {
  var id = ws(n)
  if (id < 0) return null
  if (!addr) return ["hyprctl", "dispatch", moveExpr(id, follow)]
  if (!addrOk(addr)) return null
  return ["hyprctl", "--batch", "dispatch " + focusWinExpr(addr) + " ; dispatch " + moveExpr(id, follow)]
}

// hyprctl prints "ok" per dispatch; anything else means Hyprland refused it
function ok(text) {
  var lines = String(text || "").trim().split("\n").filter(function (l) { return l !== "" })
  return lines.length > 0 && lines.every(function (l) { return l.trim() === "ok" })
}
