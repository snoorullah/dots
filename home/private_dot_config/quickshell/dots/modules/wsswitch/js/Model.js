// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The workspace switcher's model. Pure: the QML side hands in Hyprland's workspaces and
// windows as plain arrays plus the UI state, tests need no compositor.
//   windows:    [{ addr, cls, title, wsId, needs? }]
//   workspaces: [{ id, name, urgent? }]
// Profiles come from the bar's Profiles.js (the one map of profile -> workspace numbers).
.pragma library
.import "../../bar/js/Profiles.js" as Profiles

// window class -> what the chip draws. First match wins; the last row is the fallback.
var APPS = [
  { re: /kitty|alacritty|foot|wezterm|ghostty|konsole|xterm|terminal/i, kind: "terminal", label: "Terminal", icon: "terminal-window" },
  { re: /^code|cursor|codium|zed|neovide|sublime/i,                    kind: "editor",   label: "Editor",   icon: "note-pencil" },
  { re: /zen|firefox|brave|chrom|aether|vivaldi|librewolf/i,           kind: "browser",  label: "Browser",  icon: "globe" },
  { re: /slack|teams|telegram|legcord|discord|beeper|zapzap|signal/i,  kind: "chat",     label: "Chat",     icon: "chat-circle" },
  { re: /thunderbird|evolution|geary/i,                                kind: "mail",     label: "Mail",     icon: "envelope" },
  { re: /obsidian/i,                                                   kind: "notes",    label: "Notes",    icon: "notebook" },
  { re: /nautilus|thunar|dolphin|nemo|pcmanfm|yazi/i,                  kind: "files",    label: "Files",    icon: "file-text" },
  { re: /spotify|mpv|vlc/i,                                            kind: "media",    label: "Media",    icon: "play" },
  { re: /pavucontrol|blueman|nm-|settings/i,                           kind: "settings", label: "Settings", icon: "gear" },
  { re: /.*/,                                                          kind: "other",    label: "App",      icon: "squares-four" }
]

function appOf(cls) {
  var c = String(cls || "")
  for (var i = 0; i < APPS.length; i++) if (APPS[i].re.test(c)) return APPS[i]
  return APPS[APPS.length - 1]
}

function numeric(s) { return /^-?\d+$/.test(String(s)) }

function wsLabel(w) {
  return (w.name && !numeric(w.name)) ? String(w.name) : "Workspace " + w.id
}

// profile cards, board order. Entries mirror Profiles.list plus the live data.
function profileEntries(inp) {
  var P = inp.profiles || Profiles.list
  var wss = (inp.workspaces || []).filter(function (w) { return Number(w.id) > 0 })
  var wins = inp.windows || []
  var activeWs = Number(inp.activeWs)
  var activeAddr = inp.activeAddr || ""
  var byWs = {}
  wins.forEach(function (w) {
    var id = Number(w.wsId)
    if (!(id > 0)) return
    ;(byWs[id] = byWs[id] || []).push(w)
  })
  var ids = {}
  wss.forEach(function (w) { ids[w.id] = w })
  Object.keys(byWs).forEach(function (k) { if (!ids[k]) ids[k] = { id: Number(k), name: String(k) } })

  var out = []
  for (var i = 0; i < P.length; i++) {
    var p = P[i]
    var list = Object.keys(ids).map(Number).filter(function (id) { return Profiles.profileOf(id) === p.name })
    if (p.ws[0] > 0 && list.indexOf(p.ws[0]) < 0) list.push(p.ws[0])
    list.sort(function (a, b) { return a - b })
    var total = 0, needs = 0
    var wsEntries = list.map(function (id) {
      var w = ids[id] || { id: id, name: String(id) }
      var rows = (byWs[id] || []).map(function (x) {
        var a = appOf(x.cls)
        var title = String(x.title || "") || a.label
        return {
          addr: String(x.addr), app: a.kind, icon: a.icon, appLabel: a.label, title: title,
          wsId: id, wsLabel: wsLabel(w), profile: p.name,
          state: x.needs ? "needs" : (x.addr === activeAddr ? "active" : "running"),
          floating: !!x.floating
        }
      })
      var flagged = rows.filter(function (r) { return r.state === "needs" }).length
      var wn = flagged > 0 ? flagged : (w.urgent === true ? 1 : 0)
      total += rows.length; needs += wn
      return { id: id, label: wsLabel(w), active: id === activeWs, n: rows.length, needs: wn, wins: rows }
    })
    out.push({
      name: p.name, icon: p.icon, letter: p.key, key: i + 1, ws: wsEntries,
      total: total, needs: needs, empty: total === 0, primary: p.ws[0]
    })
  }
  return out
}

function activeProfile(inp) {
  var id = Number(inp.activeWs)
  return id > 0 ? Profiles.profileOf(id) : ""
}

function findProfile(list, name) {
  for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
  return null
}

function findWin(list, addr) {
  if (!addr) return null
  for (var i = 0; i < list.length; i++)
    for (var j = 0; j < list[i].ws.length; j++)
      for (var k = 0; k < list[i].ws[j].wins.length; k++)
        if (list[i].ws[j].wins[k].addr === addr) return list[i].ws[j].wins[k]
  return null
}

function windowsOf(p) {
  var out = []
  if (p) p.ws.forEach(function (w) { w.wins.forEach(function (x) { out.push(x) }) })
  return out
}

function matches(w, q) {
  return !q || (w.appLabel + " " + w.title + " " + w.wsLabel).toLowerCase().indexOf(q) >= 0
}

function split(title, q) {
  var i = q ? title.toLowerCase().indexOf(q) : -1
  if (i < 0) return { pre: title, mid: "", post: "" }
  return { pre: title.slice(0, i), mid: title.slice(i, i + q.length), post: title.slice(i + q.length) }
}

// st: { focus, sel, hover, query, wsIdx, variant a|b|c, mode pop|full, salah, locked, err, toast, moved }
function build(inp) {
  var st = inp.st || {}
  var q = String(st.query || "").toLowerCase()
  var variant = st.variant || "a"
  var mode = variant === "a" ? (st.mode || "pop") : "full"
  var profiles = profileEntries(inp)
  var active = activeProfile(inp)
  var salah = !!st.salah
  var focus = findProfile(profiles, st.focus) ? st.focus : (active || profiles[0].name)
  var filtering = q !== "" && !(variant === "a" && mode === "pop")

  profiles.forEach(function (p) {
    p.on = p.name === focus
    p.isActive = p.name === active
    p.dim = salah && p.name !== active
    p.hits = 0
    p.ws.forEach(function (w) {
      w.wins.forEach(function (x) {
        x.hit = !!q && matches(x, q)
        x.sel = x.addr === st.sel
        x.err = !!st.err && x.addr === st.err
        x.moved = !!st.moved && x.addr === st.moved
        if (x.hit) p.hits++
      })
    })
    var names = p.ws.map(function (w) { return w.label })
    p.sub = (p.on || st.hover === p.name) ? (p.total ? names.join(" · ") : "Nothing open")
                                           : (p.total ? p.total + (p.total === 1 ? " window" : " windows") : "Nothing open")
    p.aria = p.name + ", " + p.total + " windows" + (p.needs ? ", " + p.needs + " need you" : "")
  })

  var order = profiles.slice().sort(function (a, b) { return (b.needs - a.needs) || (a.key - b.key) })
  if (filtering) order = order.filter(function (p) { return p.hits > 0 })

  var fp = findProfile(profiles, focus)
  var wsIdx = Math.max(0, Math.min(Number(st.wsIdx) || 0, fp.ws.length - 1))
  var sel = findWin(profiles, st.sel)

  var groups = [], count = 0
  if (filtering) {
    order.forEach(function (p) {
      var rows = []
      p.ws.forEach(function (w) {
        w.wins.forEach(function (x) {
          if (!x.hit) return
          var s = split(x.title, q)
          rows.push({ addr: x.addr, icon: x.icon, title: x.title, pre: s.pre, mid: s.mid, post: s.post,
                      wsLabel: x.wsLabel, state: x.state, sel: x.sel, err: x.err })
        })
      })
      if (rows.length) { groups.push({ name: p.name, icon: p.icon, n: rows.length, rows: rows }); count += rows.length }
    })
  }

  var targets = profiles.map(function (p) {
    var cur = !!sel && sel.profile === p.name
    return { name: p.name, icon: p.icon, key: p.key, cur: cur, disabled: cur || p.dim, primary: p.primary }
  })

  // the schematic map: one workspace of the focused profile, main + stack
  var mapWs = fp.ws[wsIdx] || null
  var tiles = mapWs ? tile(mapWs.wins.length) : []
  var mapRects = mapWs ? mapWs.wins.map(function (x, i) {
    return { addr: x.addr, icon: x.icon, title: x.title, state: x.state, sel: x.sel, hit: x.hit,
             fx: tiles[i][0], fy: tiles[i][1], fw: tiles[i][2], fh: tiles[i][3] }
  }) : []

  var foot
  if (sel) foot = [{ k: "Up Down", l: "window" }, { k: "Left Right", l: "profile" }, { k: "Esc", l: "close" }]
  else if (variant === "a" && mode === "pop") foot = [{ k: "Up Down", l: "move" }, { k: "Enter", l: "focus" }, { k: "Tab", l: "full" }, { k: "Esc", l: "close" }]
  else foot = [{ k: "Left Right", l: "profile" }, { k: "Up Down", l: "window" }, { k: "Enter", l: "focus" }, { k: "/", l: "filter" }, { k: "Tab", l: "view" }, { k: "Esc", l: "close" }]

  // the selected row's own line: what Enter and the move keys do to it
  var rowHints = [{ k: "Enter", l: "focus" }, { k: "Shift+1-7", l: "move" }, { k: "Shift+Enter", l: "move + follow" }]

  var hov = st.hover ? findProfile(profiles, st.hover) : null

  return {
    variant: variant, mode: mode, locked: !!st.locked, salah: salah, query: String(st.query || ""),
    filtering: filtering, groups: groups, resultCount: count,
    resultsText: count + (count === 1 ? " result" : " results"), noResults: filtering && count === 0,
    active: active, focus: focus, fp: fp, wsIdx: wsIdx, profiles: profiles, order: order,
    sel: sel, targets: targets, map: mapRects, mapWs: mapWs,
    hover: hov, hoverName: hov ? hov.name : "",
    foot: foot, rowHints: rowHints, toast: st.toast || "", err: !!st.err,
    totalWins: profiles.reduce(function (n, p) { return n + p.total }, 0)
  }
}

// main + stack: the first window takes 56 % of the width, the rest share the right column
function tile(n) {
  if (n <= 0) return []
  if (n === 1) return [[0, 0, 1, 1]]
  var mw = 0.56, g = 0.012
  var r = [[0, 0, mw - g / 2, 1]]
  var m = n - 1, h = (1 - 0.04 * (m - 1)) / m
  for (var i = 0; i < m; i++) r.push([mw + g / 2, i * (h + 0.04), 1 - mw - g / 2, h])
  return r
}

// ---- keyboard -----------------------------------------------------------------------
// Returns a patch for the UI state, or { act: ... } for something to run.
//   key: left right up down enter shift-enter, or a digit "1".."7" / shift-digit "s1".."s7"
function nav(m, key) {
  // The popover strip draws m.profiles in fixed order; the rail and grid draw m.order.
  var seq = (m.variant === "a" && m.mode === "pop") ? m.profiles : m.order
  var names = seq.map(function (p) { return p.name })
  if (names.length === 0) return {}
  var i = Math.max(0, names.indexOf(m.focus))
  if (key === "left" || key === "right") {
    var j = Math.max(0, Math.min(names.length - 1, i + (key === "right" ? 1 : -1)))
    return { focus: names[j], sel: "", wsIdx: 0 }
  }
  if (key === "up" || key === "down") {
    var d = key === "down" ? 1 : -1
    if (m.variant === "b") {
      var k = i + 4 * d
      return k >= 0 && k < names.length ? { focus: names[k], sel: "", wsIdx: 0 } : {}
    }
    var wins = m.filtering ? m.groups.reduce(function (a, g) { return a.concat(g.rows) }, [])
                           : windowsOf(m.fp)
    if (wins.length === 0) return {}
    var at = -1
    for (var x = 0; x < wins.length; x++) if (wins[x].addr === (m.sel ? m.sel.addr : "")) at = x
    var n = at + d
    if (n < 0) return { sel: "" }
    return { sel: wins[Math.min(n, wins.length - 1)].addr }
  }
  if (key === "enter") {
    if (!m.sel && m.filtering && m.groups.length > 0) return { act: { type: "focusWin", addr: m.groups[0].rows[0].addr } }
    if (m.sel) return { act: { type: "focusWin", addr: m.sel.addr } }
    return { act: { type: "focusWs", id: focusTarget(m) } }
  }
  if (key === "shift-enter") {
    return { act: { type: "moveWin", addr: m.sel ? m.sel.addr : "", id: moveTarget(m), follow: true, profile: m.focus } }
  }
  var dg = /^(s?)([1-7])$/.exec(String(key))
  if (dg && m.profiles[Number(dg[2]) - 1]) {
    var p = m.profiles[Number(dg[2]) - 1]
    if (dg[1] === "s") return { act: { type: "moveWin", addr: m.sel ? m.sel.addr : "", id: p.primary, follow: false, profile: p.name } }
    return { focus: p.name, sel: "", wsIdx: 0 }
  }
  return {}
}

// Enter on a profile: stay on the workspace you are on if it is in the profile, else its first
function focusTarget(m) {
  var fp = m.fp
  for (var i = 0; i < fp.ws.length; i++) if (fp.ws[i].active) return fp.ws[i].id
  if (m.variant === "c" && fp.ws[m.wsIdx]) return fp.ws[m.wsIdx].id
  return fp.primary
}

// Shift+Enter: the map's chosen workspace, else the profile's first
function moveTarget(m) {
  if (m.variant === "c" && m.fp.ws[m.wsIdx]) return m.fp.ws[m.wsIdx].id
  return m.fp.primary
}
