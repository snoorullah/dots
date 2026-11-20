// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The logo menu's model. Pure: the QML side hands in health, mode, salah and the UI state.
//   health: { state: "ok" | "degraded" | "safe", fix: "reload" | "hypr" | "", up: "2d 4h" }
//   salah:  { on, ends: "13:42", next: "Asr 16:05" }
//   st:     { sel, query, logout: 0..3, ai, focusNote, focusSeen, toast }
// Rows are local actions only: open a surface, run a recovery argv, lock, log out. Nothing here
// lists a task name, and nothing is sent anywhere.
.pragma library

var ROW_CAP = 17
var MODES = ["Focus", "Meeting", "Salah", "Heavy work", "Winding down", "Off duty"]
var LOGOUT_SECONDS = 3

var DEFS = {
  control:    { label: "Control centre", icon: "gauge", key: "G", combo: "Super+C", act: { type: "ui", fn: "cc" } },
  sidebar:    { label: "Sidebar", icon: "columns", key: "", combo: "Super+A", act: { type: "ui", fn: "sidebar" } },
  launcher:   { label: "Launcher", icon: "magnifying-glass", key: "", combo: "Super+Space", act: { type: "ipc", target: "dots.launcher", fn: "toggle" } },
  scratchpad: { label: "Scratchpad", icon: "push-pin", key: "S", combo: "Super+`", act: { type: "ipc", target: "dots.scratchpad", fn: "toggle" } },
  notes:      { label: "Notes", icon: "note-pencil", key: "N", combo: "Super+N", act: { type: "ipc", target: "dots.notes", fn: "toggle" } },
  cheatsheet: { label: "Cheatsheet", icon: "list-bullets", key: "", combo: "Super+/", act: { type: "ipc", target: "dots.keys", fn: "toggle" } },
  reload:     { label: "Reload shell", icon: "arrow-clockwise", key: "R", combo: "", act: { type: "recover", name: "reload-shell" }, done: "Shell reloaded" },
  hypr:       { label: "Reload Hyprland", icon: "arrow-counter-clockwise", key: "H", combo: "", act: { type: "recover", name: "reload-hypr" }, done: "Hyprland reloaded" },
  safe:       { label: "Safe mode", icon: "shield", key: "B", combo: "", act: { type: "recover", name: "waybar" }, done: "Safe mode on. Plain bar." },
  log:        { label: "Show shell log", icon: "terminal-window", key: "", combo: "", act: { type: "recover", name: "log" }, done: "Local journal only. Nothing leaves this machine." },
  back:       { label: "Back to full shell", icon: "arrow-counter-clockwise", key: "", combo: "", act: { type: "recover", name: "full-shell" }, done: "Full shell back" },
  lock:       { label: "Lock", icon: "lock", key: "L", combo: "", act: { type: "recover", name: "lock" }, done: "Locking" },
  logout:     { label: "Logout", icon: "sign-out", key: "Q", combo: "Shift+", act: { type: "logout" } },
  settings:   { label: "Settings", icon: "gear", key: "", combo: "", act: { type: "ui", fn: "settings" } }
}

var GO = ["control", "sidebar", "launcher", "scratchpad", "notes", "cheatsheet"]
var FIX = ["reload", "hypr", "safe", "log"]
var POOL = GO.concat(FIX, ["lock", "logout", "settings"])

function uptimeText(ms) {
  var m = Math.max(0, Math.floor(ms / 60000))
  var d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), mm = m % 60
  if (d > 0) return "up " + d + "d " + h + "h"
  if (h > 0) return "up " + h + "h " + mm + "m"
  return "up " + mm + "m"
}

function row(id, o) {
  var d = DEFS[id]
  var hot = !!o.hot
  return { id: id, label: d.label, icon: d.icon, key: d.key, combo: hot ? "Enter" : d.combo, hot: hot,
           selected: o.sel === id, act: d.act }
}

function sec(o) {
  var s = { kind: "", rows: [], chips: [], label: "", text: "", tone: "", sub: "" }
  for (var k in o) s[k] = o[k]
  return s
}

function build(inp) {
  var h = inp.health || { state: "ok", fix: "", up: "" }
  var st = inp.st || { sel: "", query: "", logout: 0 }
  var salah = inp.salah || { on: false }
  var mode = salah.on ? "Salah" : (inp.mode || "Heavy work")
  var degraded = h.state === "degraded"
  var safe = h.state === "safe"
  var q = String(st.query || "").trim().toLowerCase()

  var head
  if (degraded) head = { t: h.fix === "hypr" ? "Hyprland not responding" : "Shell not responding", icon: "warning", tone: "warn", r: h.up ? "up " + h.up : "" }
  else if (safe) head = { t: "Safe mode", icon: "shield", tone: "dim", r: "plain bar" }
  else if (salah.on) head = { t: "Salah active", icon: "mosque", tone: "accent", r: salah.next ? "then " + salah.next : "" }
  else head = { t: "Shell ok", icon: "moon", tone: "accent", r: h.up ? "up " + h.up : "" }

  var fixIds = FIX.slice()
  if (degraded && h.fix) fixIds = [h.fix].concat(fixIds.filter(function (x) { return x !== h.fix }))
  if (safe) fixIds = ["log"]

  var secs = []
  var order = []                                 // selectable row ids, top to bottom
  var sel = st.sel
  var pickFirst = function (ids) { if (!sel || ids.indexOf(sel) < 0) sel = ids[0] || "" }

  if (q) {
    var ids = POOL.filter(function (id) { return DEFS[id].label.toLowerCase().indexOf(q) >= 0 })
    order = ids
    pickFirst(ids)
    secs.push(sec({ kind: "filter", text: st.query }))
    if (!ids.length) secs.push(sec({ kind: "empty", text: "Nothing here. Esc" }))
    else secs.push(sec({ kind: "rows", rows: ids.map(function (id) { return row(id, { sel: sel }) }) }))
  } else {
    var goIds = safe ? [] : GO
    var all = (safe ? ["back"] : goIds).concat(fixIds, safe ? [] : ["lock", "logout"])
    order = all
    var pre = degraded && h.fix ? h.fix : (safe ? "back" : "control")
    if (!sel || order.indexOf(sel) < 0) sel = pre
    if (safe) {
      secs.push(sec({ kind: "rows", rows: [row("back", { sel: sel })] }))
      secs.push(sec({ kind: "note", text: "Plain bar only. Scratchpad, notes and timers are paused, not lost.", tone: "warn" }))
    } else {
      secs.push(sec({ kind: "label", label: "GO" }))
      secs.push(sec({ kind: "rows", rows: GO.map(function (id) { return row(id, { sel: sel }) }) }))
      secs.push(sec({ kind: "label", label: "MODE" }))
      secs.push(sec({ kind: "modes", chips: MODES.map(function (m) {
        return { t: m, on: m === mode, locked: salah.on && m !== "Salah" }
      }) }))
      if (salah.on) secs.push(sec({ kind: "note", text: "Salah wins. Modes locked" + (salah.ends ? ", ends " + salah.ends : "") + ".", tone: "accent" }))
      else if (st.focusNote && mode === "Focus") secs.push(sec({ kind: "note", text: "Focus breaks through: agent, VIP, critical, salah.", tone: "accent" }))
    }
    secs.push(sec({ kind: "rule" }))
    secs.push(sec({ kind: "label", label: "FIX THE SHELL" }))
    secs.push(sec({ kind: "rows", rows: fixIds.map(function (id) { return row(id, { sel: sel, hot: degraded && id === h.fix }) }) }))
    if (degraded) {
      secs.push(sec({ kind: "ask", text: "Why is the shell red?", sub: "local" }))
      if (st.ai) secs.push(sec({ kind: "note", text: inp.hint || "Hint: the shell stopped answering. Reload it, then check the log.", tone: "accent" }))
    }
    secs.push(sec({ kind: "rule" }))
    secs.push(sec({ kind: "label", label: "SESSION" }))
    if (st.logout > 0) secs.push(sec({ kind: "countdown", text: st.logout + "... " + Math.max(st.logout - 1, 0) + "...", n: st.logout }))
    else secs.push(sec({ kind: "session", rows: [row("lock", { sel: sel }), row("logout", { sel: sel })], sub: salah.on ? "after salah" : "" }))
    secs.push(sec({ kind: "rule" }))
    secs.push(sec({ kind: "foot", text: "Settings" }))
  }

  var rowCount = 0
  secs.forEach(function (s) { rowCount += s.rows.length })

  return {
    head: head, secs: secs, order: order, sel: sel, mode: mode, degraded: degraded, safe: safe, salah: !!salah.on,
    filtering: q !== "", query: st.query || "", logout: st.logout || 0, rowCount: rowCount,
    toast: st.toast || "", logoutDim: !!salah.on,
    countdownText: st.logout > 0 ? countdownText(st.logout) : ""
  }
}

function countdownText(n) {
  var out = []
  for (var i = n; i >= 1; i--) out.push(i + "...")
  return out.join(" ")
}

function tickLogout(n) { return n > 0 ? n - 1 : 0 }

// ---- keys ------------------------------------------------------------------------------------
// returns { st: patch, side: { type, ... } | null }
function nav(m, st, key, shift, rowId) {
  var p = {}
  var i = m.order.indexOf(m.sel)
  var n = m.order.length
  var go = function (id) { p.sel = id; return { st: p, side: null } }
  var run = function (id) {
    var d = DEFS[id]
    if (!d) return { st: p, side: null }
    if (id === "logout") {
      if (m.salah) { p.toast = "Logout waits until salah ends"; return { st: p, side: null } }
      p.logout = LOGOUT_SECONDS
      return { st: p, side: { type: "countdown" } }
    }
    if (d.act.type === "recover" && d.done) p.toast = d.done
    return { st: p, side: { type: "act", id: id, act: d.act } }
  }
  if (m.logout > 0) {
    if (key === "esc") { p.logout = 0; p.toast = "Logout cancelled"; return { st: p, side: { type: "countdown-stop" } } }
    return { st: p, side: null }
  }
  if (key === "esc") {
    if (m.filtering) { p.query = ""; return { st: p, side: null } }
    return { st: p, side: { type: "close" } }
  }
  if (key === "up" || key === "k") return n ? go(m.order[(i - 1 + n) % n]) : { st: p, side: null }
  if (key === "down" || key === "j") return n ? go(m.order[(i + 1) % n]) : { st: p, side: null }
  if (key === "home") return n ? go(m.order[0]) : { st: p, side: null }
  if (key === "end") return n ? go(m.order[n - 1]) : { st: p, side: null }
  if (key === "enter") return (rowId || m.sel) ? run(rowId || m.sel) : { st: p, side: null }
  if (key.length === 1 && !m.filtering) {
    var up = key.toUpperCase()
    if (up === "Q" && shift) return run("logout")
    for (var id in DEFS) if (DEFS[id].key === up && up !== "Q" && m.order.indexOf(id) >= 0) return run(id)
    // any other printable key starts the filter
    if (/^[a-z0-9 ]$/i.test(key)) { p.query = key; p.sel = ""; return { st: p, side: null } }
  }
  return { st: p, side: null }
}

function modeArgv(script, name) {
  return MODES.indexOf(name) >= 0 && name !== "Salah" ? ["python3", script, "mode", "set", name] : null
}

function recoverArgv(script, name) {
  var ok = ["reload-shell", "reload-hypr", "waybar", "full-shell", "log", "lock", "logout"]
  return ok.indexOf(name) >= 0 ? ["python3", script, name] : null
}

function ipcArgv(qsDir, target, fn) {
  if (!/^dots\.[a-z]+$/.test(target) || !/^[a-z]+$/.test(fn)) return null
  return ["quickshell", "ipc", "-p", qsDir, "call", target, fn]
}
