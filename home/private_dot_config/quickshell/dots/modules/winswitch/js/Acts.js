// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// argv builders for the switcher's Hyprland actions. Hyprland 0.56 runs a Lua config and takes
// hl.dsp.* expressions as the dispatch payload. Every address is validated before it joins a
// string; each result is an argv array, never a shell line.
.pragma library

function addrOk(a) { return /^0x[0-9a-f]{1,16}$/.test(String(a)) }

function focusExpr(addr) { return 'hl.dsp.focus({ window = "address:' + addr + '" })' }

function focusWin(addr) {
  return addrOk(addr) ? ["hyprctl", "dispatch", focusExpr(addr)] : null
}

// focus it, then close the active window: one batch so the two stay in order
function closeWin(addr) {
  if (!addrOk(addr)) return null
  return ["hyprctl", "--batch", "dispatch " + focusExpr(addr) + " ; dispatch hl.dsp.window.close()"]
}

function scratchpad(addr) {
  if (!addrOk(addr)) return null
  return ["hyprctl", "--batch", "dispatch " + focusExpr(addr) + ' ; dispatch hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })']
}

// hyprctl prints "ok" per dispatch; anything else means Hyprland refused it
function ok(text) {
  var lines = String(text || "").trim().split("\n").filter(function (l) { return l !== "" })
  return lines.length > 0 && lines.every(function (l) { return l.trim() === "ok" })
}

function pinsArgv(script, verb, a, b) {
  var v = ["set", "unset", "prune", "list", "current", "ticket"]
  if (v.indexOf(verb) < 0) return null
  var out = ["python3", script, verb]
  if (a !== undefined) out.push(String(a))
  if (b !== undefined) out.push(String(b))
  return out
}

// titles and ids only: nothing else about a window ever reaches the model
function rankArgv(script, question, wins) {
  var list = (wins || []).map(function (w) { return { id: w.addr, title: w.title, app: w.app } })
  return ["python3", script, String(question), JSON.stringify(list)]
}
