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

// ---- layout sets (dots-layout) and the launcher ------------------------------------------
// `tool` is the dots-layout path the caller resolved (HOME/.local/bin/dots-layout). Its replies are
// one JSON line, not "ok": use okJson/reply for those.
function profileOk(name) { return /^[A-Za-z0-9_-]{1,40}$/.test(String(name)) }

// bring back the last saved windows of one profile's workspaces (apps only, placed by workspace)
function backSet(tool, wsIds) {
  var ids = (wsIds || []).map(ws).filter(function (n) { return n > 0 })
  if (!tool || ids.length === 0 || ids.length !== (wsIds || []).length) return null
  return [tool, "restore", "--apply", "--parts", "layout,apps", "--workspaces", ids.join(",")]
}
function undoSet(tool) { return tool ? [tool, "undo"] : null }
function startSet(tool, name, n) {
  var id = ws(n)
  return tool && profileOk(name) && id > 0 ? [tool, "startup", "--workspace", String(id), "--name", String(name)] : null
}
// the launcher takes the text through its IPC target; the query is one argv element, never a string
// same argv form as logomenu: quickshell ipc -p <shellDir> call dots.launcher query <text>
function launcherQuery(q, qsDir) {
  var t = String(q || "").slice(0, 200)
  return t === "" || !qsDir ? null : ["quickshell", "ipc", "-p", String(qsDir), "call", "dots.launcher", "query", t]
}
function reply(text) {
  try { return JSON.parse(String(text || "").trim().split("\n").pop()) } catch (e) { return null }
}
function okJson(text) { var r = reply(text); return !!r && r.ok === true }
