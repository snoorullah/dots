// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// argv builders for the windows module. Hyprland 0.56 runs a Lua config and takes hl.dsp.*
// expressions as the dispatch payload, the same style as wsswitch/js/Dispatch.js and
// services/Hypr.qml. Every value is validated before it joins a string; each result is an argv.
// `tool` is the dots-layout path the caller resolved (HOME/.local/bin/dots-layout).
.pragma library

function addrOk(a) { return /^0x[0-9a-f]{1,16}$/.test(String(a)) }
function nameOk(n) { return /^[a-z0-9_-]{1,40}$/.test(String(n)) }
function profileOk(n) { return /^[A-Za-z0-9_-]{1,40}$/.test(String(n)) }

function focusExpr(addr) { return 'hl.dsp.focus({ window = "address:' + addr + '" })' }

// ---- scratchpad: one special workspace per profile --------------------------------------
function special(profile) { return "scratch-" + String(profile || "").toLowerCase() }
function scratchToggle(profile) {
  var s = special(profile)
  return profileOk(profile) && nameOk(s) ? ["hyprctl", "dispatch", 'hl.dsp.workspace.toggle_special("' + s + '")'] : null
}

// ---- groups -----------------------------------------------------------------------------
function groupToggle() { return ["hyprctl", "dispatch", "hl.dsp.group.toggle()"] }
function groupNext() { return ["hyprctl", "dispatch", "hl.dsp.group.next()"] }
function groupPrev() { return ["hyprctl", "dispatch", "hl.dsp.group.prev()"] }
// focusing a member of a group makes it the group's active tab
function focusTab(addr) { return addrOk(addr) ? ["hyprctl", "dispatch", focusExpr(addr)] : null }
function closeTab(addr) {
  return addrOk(addr) ? ["hyprctl", "--batch", "dispatch " + focusExpr(addr) + " ; dispatch hl.dsp.window.close()"] : null
}

// ---- dots-layout ------------------------------------------------------------------------
function status(tool) { return tool ? [tool, "status"] : null }
function restore(tool, parts) {
  var ok = ["layout", "apps", "panes", "agents", "finished"]
  var p = (parts || []).filter(function (x) { return ok.indexOf(x) >= 0 })
  return tool && p.length > 0 && p.length === (parts || []).length ? [tool, "restore", "--apply", "--parts", p.join(",")] : null
}
function dismiss(tool) { return tool ? [tool, "dismiss"] : null }
function undo(tool) { return tool ? [tool, "undo"] : null }
function noteGet(tool, profile) { return tool && profileOk(profile) ? [tool, "note", "get", "--profile", profile] : null }
// the text is one argv element (the tool caps it at 64 KB), so nothing is parsed and no stdin is needed
function noteSet(tool, profile, text) {
  var t = String(text === undefined ? "" : text)
  return tool && profileOk(profile) && t.length <= 65536 ? [tool, "note", "set", "--profile", profile, "--text", t] : null
}
function noteSave(tool, profile) { return tool && profileOk(profile) ? [tool, "note", "save", "--profile", profile] : null }
function prefGet(tool, profile) { return tool && profileOk(profile) ? [tool, "pref", "get", "--profile", profile] : null }
function prefSet(tool, profile, value) { return tool && profileOk(profile) && nameOk(value) ? [tool, "pref", "set", "--profile", profile, "--value", value] : null }

// ---- replies ----------------------------------------------------------------------------
// hyprctl dispatch prints "ok" per dispatch; eval prints nothing useful on success, so only an error word fails it
function ok(text) {
  var lines = String(text || "").trim().split("\n").filter(function (l) { return l !== "" })
  return lines.length > 0 && lines.every(function (l) { return l.trim() === "ok" })
}
function okEval(text) { return !/error|invalid|fail|unknown/i.test(String(text || "")) }
function reply(text) {
  try { return JSON.parse(String(text || "").trim().split("\n").pop()) } catch (e) { return null }
}
function okJson(text) { var r = reply(text); return !!r && r.ok === true }
