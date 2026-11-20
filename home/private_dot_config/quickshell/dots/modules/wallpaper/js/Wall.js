// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The wallpaper picker's model. Pure: the QML side hands in the scan result, the current
// wallpaper, the palettes it has asked for, and the UI state.
//   items: [{ name, path, rel, ok, fav }]            from py/wp.py scan
//   pals:  { path: { surface, text, ratio, tuned, tunedText, tags } }   from py/wp.py palette
//   st:    { sel, query, extract, untuned, monitor, toast, loading, aiOpen, undoOk }
// dots-theme fixes the accent and the status colours in both modes, so a candidate palette only
// changes the surface and the text; the mini shell takes accent and warn from Theme.
.pragma library

var COLS = 4
var MONITOR_ALL = "All monitors"

var MODES = [
  { key: "1", name: "Wallpaper" },
  { key: "2", name: "Current" },
  { key: "3", name: "Mode" }
]

var LEGEND = [["Arrows", "preview"], ["Enter", "set"], ["Space", "set, stay"], ["Esc", "revert"], ["1 2 3", "palette"],
              ["S N R", "shuffle"], ["F", "favourite"], ["G", "folder"], ["M", "monitor"], ["L", "lock"]]

function initial() {
  return { sel: "", query: "", extract: 0, untuned: false, monitor: 0, toast: false, loading: false,
           aiOpen: true, keys: false, folderPrompt: false }
}

function thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

function matches(it, q, pals) {
  if (!q) return true
  var p = pals[it.path]
  return (it.rel + " " + (p && p.tags ? p.tags.join(" ") : "")).toLowerCase().indexOf(q) >= 0
}

function indexOfPath(list, path) {
  for (var i = 0; i < list.length; i++) if (list[i].path === path) return i
  return -1
}

function inForce(m, extract, selPal, curPal, untuned) {
  // returns { src, surface, text, ratio, tuned, tunedActive }
  if (extract === 2) return { src: "mode", surface: "", text: "", ratio: 8.1, tuned: false, active: false }
  if (extract === 1) return { src: "current", surface: curPal ? curPal.surface : "", text: curPal ? curPal.text : "", ratio: curPal ? curPal.ratio : 8.1, tuned: false, active: false }
  if (!selPal) return { src: "wallpaper", surface: "", text: "", ratio: 0, tuned: false, active: false, unknown: true }
  var tuned = !!selPal.tuned
  return { src: "wallpaper", surface: selPal.surface, text: (tuned && !untuned) ? selPal.tunedText : selPal.text,
           ratio: (tuned && !untuned) ? 4.5 : selPal.ratio, tuned: tuned, active: tuned }
}

function build(inp) {
  var st = inp.st || initial()
  var pals = inp.pals || {}
  var items = inp.items || []
  var folder = inp.folder || { name: "", count: items.length, skipped: 0, exists: true }
  var cur = inp.cur || ""
  var monitors = [MONITOR_ALL].concat(inp.monitors || [])
  var q = String(st.query || "").toLowerCase()
  var list = items.filter(function (it) { return matches(it, q, pals) })
  var empty = !folder.exists || items.length === 0

  var si = indexOfPath(list, st.sel)
  if (si < 0) si = Math.max(0, indexOfPath(list, cur))
  var selItem = list.length ? list[Math.min(si, list.length - 1)] : null
  var selPath = selItem ? selItem.path : ""
  var previewing = !!selItem && selPath !== cur && !empty

  var curItem = items[indexOfPath(items, cur)] || null
  var selPal = selItem ? pals[selPath] : null
  var curPal = pals[cur] || null
  var pal = inForce(null, st.extract, selPal && !selPal.error ? selPal : null, curPal && !curPal.error ? curPal : null, st.untuned)

  var tiles = list.map(function (it) {
    var p = pals[it.path]
    var isCur = it.path === cur
    var focus = it.path === selPath
    var sug = !!inp.suggest && inp.suggest === it.path && st.aiOpen
    return {
      path: it.path, name: it.name, isCur: isCur, isBroken: !it.ok, isFav: !!it.fav, isSug: sug,
      ring: sug || focus ? "accent" : (isCur ? "cur" : "none"),
      dim: !it.ok, loading: !!st.loading,
      pass: !p || p.error ? null : (p.ratio >= 4.5 || p.tuned),
      swatch: p && !p.error ? { surface: p.surface, text: p.text } : null,
      showStar: it.ok && (it.fav || focus),
      aria: it.name + (isCur ? ", current" : "") + (it.ok ? "" : ", unreadable") + (it.fav ? ", favourite" : "")
    }
  })

  var salah = !!inp.salah
  var shuffleOn = !!inp.shuffle
  var focusMode = !!inp.focusMode
  var notice = null
  if (salah) notice = { text: "Salah mode, change applies after. Shuffle and palette flips are held.", icon: "mosque", tone: "dim" }
  else if (st.extract === 2) notice = { text: "Mode palette active (night). The picker changes the image only.", icon: "moon", tone: "accent" }
  else if (shuffleOn && focusMode) notice = { text: "Shuffle paused while focus mode is on. It resumes by itself.", icon: "timer", tone: "warn" }

  var shuffleLabel = salah && shuffleOn ? "Held, salah" : (!shuffleOn ? "Shuffle off" : (focusMode ? "Hourly, paused" : "Hourly"))
  var mid = !shuffleOn ? "hint" : (focusMode ? "paused" : "next")

  var monitorIdx = Math.min(st.monitor || 0, monitors.length - 1)
  var count = list.length
  var showCount = q !== ""

  var ratioText = pal.unknown ? "" : pal.ratio.toFixed(1) + ":1 " + (pal.ratio >= 4.5 ? "passes AA" : "fails AA")

  return {
    mode: st.loading ? "loading" : (empty ? "empty" : "grid"),
    tiles: tiles, count: count, sel: si, selPath: selPath, selName: selItem ? selItem.name : "",
    curPath: cur, curName: curItem ? curItem.name : "", previewing: previewing,
    folder: { name: empty && !folder.exists ? "No folder" : folder.name, count: thousands(folder.count || 0),
              skipped: folder.skipped || 0, skippedText: (folder.skipped || 0) + " skipped" },
    search: { query: st.query || "", placeholder: st.folderPrompt ? "Paste a folder path, Enter to use it. Esc cancels." : "Filter by name or tag. Just start typing.", prompt: !!st.folderPrompt, show: showCount && !st.folderPrompt, text: thousands(count) + " of " + thousands(folder.count || items.length) },
    notice: notice, pal: pal, palKnown: !pal.unknown,
    swatches: [
      { n: "surface", src: pal.surface ? "pal" : "theme", c: pal.surface, k: "surface" },
      { n: "accent", src: "theme", c: "", k: "accent" },
      { n: "text", src: pal.text ? "pal" : "theme", c: pal.text, k: "fg" },
      { n: "warn", src: "theme", c: "", k: "waiting" },
      { n: "fail", src: "theme", c: "", k: "failed" }
    ],
    contrast: { show: !pal.unknown, text: ratioText, pass: pal.ratio >= 4.5, tuned: pal.active && !st.untuned,
                canUntune: pal.active, untuneLabel: st.untuned ? "Use tuned" : "Show untuned" },
    tags: selPal && selPal.tags ? selPal.tags : [],
    modes: MODES.map(function (md, i) { return { key: md.key, name: md.name, on: st.extract === i } }),
    extract: st.extract,
    target: { label: monitors[monitorIdx], idx: monitorIdx, list: monitors, output: monitorIdx === 0 ? "" : monitors[monitorIdx] },
    shuffle: { label: shuffleLabel, on: shuffleOn && !salah, mid: mid, next: inp.nextAt || "" },
    lock: !!inp.lock,
    suggestion: !!inp.suggest && st.aiOpen && inp.suggest !== cur,
    toast: !!st.toast, salah: salah, keys: !!st.keys,
    setEnabled: previewing && !!selItem && selItem.ok,
    legend: LEGEND.map(function (k) { return { k: k[0], t: k[1] } }),
    // dots-theme runs only for "Wallpaper"; salah holds palette flips like the board says
    palette: (st.extract === 0 && !salah) ? "wallpaper" : "current"
  }
}

// ---- keys ------------------------------------------------------------------------------------
// returns { st: patch, side: { type, ... } | null }
function nav(m, st, key) {
  var n = m.tiles.length
  var p = {}
  var side = null
  var move = function (d) {
    if (!n) return
    if (m.sel + d < 0 && Math.abs(d) > 1) return          // up from the first row stays put
    var i = Math.min(Math.max(m.sel + d, 0), n - 1)
    var t = m.tiles[i]
    if (t && !t.isBroken) { p.sel = t.path; p.toast = false }
    else {
      // skip unreadable tiles in the direction of travel
      var step = d < 0 ? -1 : 1, j = i
      while (j >= 0 && j < n && m.tiles[j].isBroken) j += step
      if (j >= 0 && j < n) { p.sel = m.tiles[j].path; p.toast = false }
    }
    side = { type: "preview" }
  }
  if (key === "left") move(-1)
  else if (key === "right") move(1)
  else if (key === "up") move(-COLS)
  else if (key === "down") move(COLS)
  else if (key === "enter" || key === "space") {
    if (m.setEnabled) side = { type: "apply", path: m.selPath, stay: key === "space", output: m.target.output, palette: m.palette }
    else if (key === "enter" && !m.previewing) side = { type: "close" }
  } else if (key === "esc") {
    if (st.folderPrompt) p.folderPrompt = false
    else if (m.previewing) { p.sel = m.curPath; side = { type: "restore" } }
    else if (st.query) p.query = ""
    else side = { type: "close" }
  } else if (key === "1" || key === "2" || key === "3") { p.extract = Number(key) - 1; p.untuned = false }
  else if (key === "s") side = { type: "shuffle", on: !m.shuffle.on }
  else if (key === "n") side = { type: "next" }
  else if (key === "r") side = { type: "random" }
  else if (key === "f" && m.selPath) side = { type: "fav", path: m.selPath }
  else if (key === "g") p.folderPrompt = true
  else if (key === "m") p.monitor = (m.target.idx + 1) % m.target.list.length
  else if (key === "l") side = { type: "lock", on: !m.lock }
  else if (key === "?") p.keys = !st.keys
  else if (key === "u" && m.toast) { p.toast = false; side = { type: "undo" } }
  return { st: p, side: side }
}
