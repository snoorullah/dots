// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Tiling assistant model. Six layout presets for the focused workspace, the one that fits the
// window count, and the Hyprland messages that apply one. Pure: tests need no compositor.
//   rects:  the thumbnail, fractions of the card [x, y, w, h]
//   layout: the Hyprland layout the preset needs on the workspace (master or dwindle)
//   msgs:   hl.dsp.layout messages sent after the layout is set
.pragma library

var list = [
  { id: "main-stack",  name: "Main + stack",  key: 1, layout: "master",  msgs: ["orientationleft", "mfact exact 0.6"],
    fit: [3, 4, 5, 6], rects: [[0, 0, 0.70, 1], [0.72, 0, 0.28, 0.47], [0.72, 0.53, 0.28, 0.47]] },
  { id: "half",        name: "Half and half", key: 2, layout: "master",  msgs: ["orientationleft", "mfact exact 0.5"],
    fit: [2], rects: [[0, 0, 0.49, 1], [0.51, 0, 0.49, 1]] },
  { id: "three-cols",  name: "Three columns", key: 3, layout: "master",  msgs: ["orientationcenter", "mfact exact 0.34"],
    fit: [], rects: [[0, 0, 0.32, 1], [0.34, 0, 0.32, 1], [0.68, 0, 0.32, 1]] },
  { id: "wide-centre", name: "Wide centre",   key: 4, layout: "master",  msgs: ["orientationcenter", "mfact exact 0.6"],
    fit: [], rects: [[0, 0, 0.16, 1], [0.18, 0, 0.64, 1], [0.84, 0, 0.16, 1]] },
  { id: "grid",        name: "Grid",          key: 5, layout: "dwindle", msgs: [],
    fit: [], rects: [[0, 0, 0.49, 0.47], [0.51, 0, 0.49, 0.47], [0, 0.53, 0.49, 0.47], [0.51, 0.53, 0.49, 0.47]] },
  { id: "code-review", name: "Code + review", key: 6, layout: "master",  msgs: ["orientationleft", "mfact exact 0.56"],
    fit: [], rects: [[0, 0, 0.56, 1], [0.58, 0, 0.42, 1]] }
]

function find(id) {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// the preset to suggest for n tiled windows
function suggest(n) {
  if (n < 2) return ""
  if (n === 2) return "half"
  if (n === 4) return "grid"
  return "main-stack"
}

// inp: { n windows on the workspace, selected id, remembered id (the profile's last use) }
function build(inp) {
  var n = Math.max(0, Number(inp.n) || 0)
  var sug = suggest(n)
  var sel = find(inp.selected) ? inp.selected : (find(inp.remembered) ? inp.remembered : (sug || "main-stack"))
  var presets = list.map(function (p) {
    return { id: p.id, name: p.name, key: p.key, rects: p.rects, on: p.id === sel, fits: p.id === sug, remembered: p.id === inp.remembered }
  })
  var chosen = find(sel)
  var count = n + (n === 1 ? " window" : " windows") + " in this workspace."
  return {
    presets: presets, n: n, selected: sel, suggested: sug,
    canApply: n >= 2,
    count: count,
    lead: n < 2 ? "Nothing to tile." : (sel === sug ? chosen.name : (find(sug) ? find(sug).name : chosen.name)),
    tail: n < 2 ? "" : (sel === sug ? "fits." : "fits better."),
    name: chosen.name
  }
}

// keyboard: 1..6 picks, left/right/up/down moves in the 3x2 grid, enter applies
function nav(m, key) {
  var i = -1
  for (var k = 0; k < m.presets.length; k++) if (m.presets[k].on) i = k
  var d = /^[1-6]$/.exec(String(key))
  if (d) return { selected: m.presets[Number(key) - 1].id }
  if (key === "enter") return m.canApply ? { act: { type: "apply", id: m.selected } } : {}
  var step = { left: -1, right: 1, up: -3, down: 3 }[key]
  if (step === undefined) return {}
  var j = i + step
  if (j < 0 || j >= m.presets.length || ((key === "left" || key === "right") && Math.floor(j / 3) !== Math.floor(i / 3))) return {}
  return { selected: m.presets[j].id }
}

// the argv lists that apply a preset to workspace ws, in order
function steps(id, ws) {
  var p = find(id), n = parseInt(ws)
  if (!p || !(n > 0) || String(n) !== String(ws).trim()) return null
  var out = [["hyprctl", "eval", 'hl.workspace_rule({ workspace = "' + n + '", layout = "' + p.layout + '" })']]
  p.msgs.forEach(function (msg) { out.push(["hyprctl", "dispatch", 'hl.dsp.layout("' + msg + '")']) })
  return out
}
