// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The "Restore yesterday's layout?" prompt model, from `dots-layout status`. Pure.
// Agents come back paused: a restored agent pane is a plain shell in the same directory.
.pragma library
.import "../../wsswitch/js/Model.js" as Model
.import "../../bar/js/Profiles.js" as Profiles

function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

function clock(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  function two(v) { return (v < 10 ? "0" : "") + v }
  return two(d.getHours()) + ":" + two(d.getMinutes())
}

// status: the `layout` object of dots-layout status; on: { id: bool } overrides of the defaults
function build(status, on) {
  if (!status) return { show: false, rows: [], parts: [], canRestore: false, saved: "", warn: "", title: "Restore yesterday\u2019s layout?" }
  var profiles = {}
  ;(status.clients || []).forEach(function (c) { if (Number(c.workspace) > 0) profiles[Profiles.profileOf(c.workspace)] = true })
  var labels = []
  ;(status.apps || []).forEach(function (cls) {
    var l = Model.appOf(cls).label
    if (labels.indexOf(l) < 0) labels.push(l)
  })
  var apps = labels.length === 0 ? "none" : labels.slice(0, 4).join(", ") + (labels.length > 4 ? " +" + (labels.length - 4) : "")
  var rows = [
    { id: "layout",   label: "Layouts and groups",             n: status.windows, value: Object.keys(profiles).length + " profiles, " + plural(status.windows, "window", "windows"), def: true },
    { id: "apps",     label: "Apps",                           n: labels.length, value: apps, def: true },
    { id: "panes",    label: "herdr panes and directories",    n: status.panes, value: plural(status.panes, "pane", "panes"), def: true },
    { id: "agents",   label: "Agents, resumed paused",         n: status.agents, value: status.agents + ", you press go", def: true },
    { id: "finished", label: "Finished agents",                n: status.finished, value: status.finished + ", as plain shells", def: false }
  ]
  var chosen = on || {}
  rows.forEach(function (r) {
    r.disabled = !(r.n > 0)
    r.on = !r.disabled && (chosen[r.id] !== undefined ? !!chosen[r.id] : r.def)
    if (r.disabled) r.value = "none"
  })
  var parts = rows.filter(function (r) { return r.on }).map(function (r) { return r.id })
  // placing windows (layout) means nothing without the apps that open them
  if (parts.indexOf("layout") >= 0 && parts.indexOf("apps") < 0) parts = parts.filter(function (p) { return p !== "layout" })
  return {
    show: true, title: "Restore yesterday\u2019s layout?", saved: "Last saved at " + clock(status.saved_at),
    rows: rows, parts: parts, canRestore: parts.length > 0,
    warn: "Best guess: apps reopen by name, so a window may land in the wrong slot. One key undoes it."
  }
}

// keyboard: enter restores, esc starts clean, 1..5 toggles a row
function nav(m, key) {
  if (key === "enter") return m.canRestore ? { act: { type: "restore", parts: m.parts } } : {}
  if (key === "escape") return { act: { type: "clean" } }
  var d = /^[1-5]$/.exec(String(key))
  if (d) { var r = m.rows[Number(key) - 1]; return r && !r.disabled ? { toggle: r.id } : {} }
  return {}
}
