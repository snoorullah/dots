// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The window switcher's model. Pure: the QML side hands in Hyprland's windows as plain objects
// plus the UI state, so tests need no compositor.
//   windows: [{ addr, cls, title, wsId, focusHist?, hidden?, special?, tabs?: [title] }]
//   st:      { sel, scope, query, group, layout, confirm, msg, closed: [addr], undo, ai }
// Titles never reach a card while `locked` (mode "locked", no cards) and are replaced by the
// app name while `redacted` (the first seconds after an unlock).
.pragma library
.import "../../wsswitch/js/Model.js" as WM
.import "../../bar/js/Profiles.js" as Profiles

var UNDO_MS = 8000
var REDACT_MS = 2000
var AI_MS = 1500
var SAFE_KINDS = ["mail", "chat"]

var SCOPES = [
  { id: "task", label: "Task", key: "`" },
  { id: "workspace", label: "Workspace", key: "1" },
  { id: "profile", label: "Profile", key: "2" },
  { id: "all", label: "All", key: "3" }
]

function initial() {
  return { sel: 1, scope: "task", query: "", group: "", layout: "strip", confirm: "", msg: "",
           closed: [], undo: null, ai: null }
}

// ---- order -----------------------------------------------------------------------------------
// most recently used first. `mru` is the shell's own list of focused addresses; windows it has
// not seen yet fall back to Hyprland's focusHistoryID, then to the order given.
function touch(mru, addr) {
  if (!addr) return mru
  var out = [addr]
  for (var i = 0; i < mru.length && out.length < 64; i++) if (mru[i] !== addr) out.push(mru[i])
  return out
}

function order(wins, mru) {
  var seen = {}
  ;(mru || []).forEach(function (a, i) { seen[a] = i })
  var keyed = wins.map(function (w, i) {
    var k = seen[w.addr] !== undefined ? seen[w.addr]
      : 1000 + (typeof w.focusHist === "number" ? w.focusHist : 500) * 1 + i / 1000
    return { w: w, k: k }
  })
  keyed.sort(function (a, b) { return a.k - b.k })
  return keyed.map(function (x) { return x.w })
}

// ---- one window ------------------------------------------------------------------------------
function trunc(s, n) {
  s = String(s || "")
  if (s.length <= n) return s
  var k = n - 1, a = Math.ceil(k / 2), b = Math.floor(k / 2)
  return s.slice(0, a) + "…" + s.slice(s.length - b)
}

// like trunc, but a filter hit is kept in view
function truncAround(s, n, q) {
  s = String(s || "")
  if (s.length <= n) return s
  var t = trunc(s, n)
  var k = q ? s.toLowerCase().indexOf(q) : -1
  if (k < 0 || t.toLowerCase().indexOf(q) >= 0) return t
  var from = Math.max(1, Math.min(k - 2, s.length - (n - 1)))
  return "\u2026" + s.slice(from, from + n - 1)
}

function norm(w, pins) {
  var app = WM.appOf(w.cls)
  var dim = w.special ? "scratchpad" : (w.hidden ? "minimized" : "")
  return {
    addr: w.addr, cls: w.cls || "", app: app.label, kind: app.kind, icon: app.icon,
    title: String(w.title || app.label), wsId: Number(w.wsId),
    ws: dim === "scratchpad" ? "sp" : (dim === "minimized" ? "min" : String(w.wsId)),
    profile: dim === "scratchpad" ? "Other" : Profiles.profileOf(w.wsId),
    ticket: (pins && pins[w.addr]) || "", tabs: w.tabs && w.tabs.length ? w.tabs.slice() : null,
    dim: dim, safe: SAFE_KINDS.indexOf(app.kind) >= 0, unavail: dim === "minimized"
  }
}

// the little page drawn on a card: [indent, width, tone], never a capture of the window
var BARS = {
  editor: [[0, 60, "accent"], [14, 110, "dim"], [14, 80, "mid"], [28, 120, "dim"], [28, 70, "accent"], [14, 40, "mid"], [0, 50, "accent"]],
  terminal: [[0, 50, "accent"], [0, 130, "dim"], [0, 100, "dim"], [0, 60, "mid"], [0, 150, "dim"], [0, 40, "accent"], [0, 90, "dim"]],
  browser: [[0, 168, "faint"], [0, 120, "dim"], [0, 150, "mid"], [0, 100, "mid"], [0, 140, "mid"], [0, 110, "mid"], [0, 60, "mid"]],
  mail: [[0, 60, "dim"], [0, 130, "mid"], [0, 50, "dim"], [0, 150, "mid"], [0, 70, "dim"], [0, 120, "mid"], [0, 40, "dim"]],
  chat: [[0, 80, "mid"], [40, 110, "faint"], [0, 60, "mid"], [40, 130, "faint"], [0, 90, "mid"], [40, 70, "faint"], [0, 50, "mid"]],
  notes: [[0, 90, "dim"], [0, 150, "mid"], [0, 140, "mid"], [0, 120, "mid"], [0, 60, "faint"], [0, 148, "mid"], [0, 100, "mid"]],
  media: [[50, 70, "dim"], [40, 90, "mid"], [0, 168, "faint"], [0, 168, "faint"], [20, 130, "mid"], [0, 168, "faint"], [60, 50, "mid"]],
  files: [[0, 40, "accent"], [0, 110, "dim"], [0, 40, "accent"], [0, 90, "dim"], [0, 40, "accent"], [0, 130, "dim"], [0, 40, "accent"]],
  settings: [[0, 60, "dim"], [0, 130, "mid"], [0, 50, "dim"], [0, 110, "mid"], [0, 70, "dim"], [0, 90, "mid"], [0, 40, "dim"]],
  other: [[60, 100, "dim"], [0, 40, "mid"], [50, 40, "mid"], [100, 40, "mid"], [0, 40, "mid"], [50, 40, "mid"], [100, 40, "mid"]]
}

function split(s, q) {
  if (!q) return { pre: s, hit: "", post: "" }
  var k = s.toLowerCase().indexOf(q)
  if (k < 0) return { pre: s, hit: "", post: "" }
  return { pre: s.slice(0, k), hit: s.slice(k, k + q.length), post: s.slice(k + q.length) }
}

// ---- scope and filter ------------------------------------------------------------------------
function scoped(list, scope, ctx) {
  var act = list.filter(function (w) { return !w.dim })
  var dm = list.filter(function (w) { return w.dim })
  if (scope === "workspace") act = act.filter(function (w) { return w.wsId === ctx.activeWs })
  else if (scope === "profile") act = act.filter(function (w) { return w.profile === ctx.profile })
  else if (scope === "task")
    act = act.filter(function (w) { return w.ticket }).concat(act.filter(function (w) { return !w.ticket }))
  return act.concat(scope === "workspace" ? dm.filter(function (w) { return w.wsId === ctx.activeWs }) : dm)
}

function haystack(w) {
  return (w.title + " " + (w.tabs || []).join(" ") + " " + w.app + " " + w.ticket + " " + w.profile).toLowerCase()
}

function isQuestion(q) { return /\?\s*$/.test(String(q || "")) && String(q).trim().length > 3 }

// ---- the model -------------------------------------------------------------------------------
function build(inp) {
  var st = inp.st || initial()
  var locked = !!inp.locked
  var redacted = !!inp.redacted && !locked
  if (locked) return { mode: "locked", cards: [], total: 0, sel: 0, scopes: [], hints: [], caption: null, status: null, panelW: 0, tx: 0 }

  var activeWs = Number(inp.activeWs)
  var all = order(inp.windows || [], inp.mru).map(function (w) { return norm(w, redacted ? null : inp.pins) })
  var closed = st.closed || []
  all = all.filter(function (w) { return closed.indexOf(w.addr) < 0 })
  var ctx = { activeWs: activeWs, profile: Profiles.profileOf(activeWs) }
  var total = all.length
  var list = scoped(all, st.scope, ctx)

  var q = ""
  var ai = null
  var question = isQuestion(st.query)
  if (question) {
    ai = st.ai || { phase: "thinking", ids: [] }
    if (ai.phase === "fallback") list = list.filter(function (w) { return ai.ids.indexOf(w.addr) >= 0 })
  } else if (st.query) {
    q = String(st.query).toLowerCase()
    list = all.filter(function (w) { return haystack(w).indexOf(q) >= 0 })
  }
  var filtering = !!st.query

  // an opened group becomes one card per tab
  var groupOpen = !!st.group && !redacted
  if (groupOpen) {
    var out = []
    list.forEach(function (w) {
      if (w.addr === st.group && w.tabs)
        w.tabs.forEach(function (t, k) {
          var c = {}
          for (var p in w) c[p] = w[p]
          c.addr = w.addr + "#" + k
          c.parent = w.addr
          c.title = t; c.tabs = null; c.tabIdx = k; c.tabCount = w.tabs.length
          out.push(c)
        })
      else out.push(w)
    })
    list = out
  }

  var n = list.length
  var layout = st.layout
  var sel = n ? Math.min(Math.max(st.sel, 0), n - 1) : 0
  var top = ai && ai.phase === "done" ? ai.ids : []

  var cards = list.map(function (w, i) {
    var shown = redacted ? w.app : w.title
    var short = redacted ? w.app : truncAround(w.title, layout === "list" ? 38 : 18, q)
    var h = split(short, q)
    var isTab = w.tabIdx !== undefined
    var group = !!w.tabs
    var suggested = top.length > 0 && w.addr === top[0]
    return {
      id: w.addr, addr: w.parent || w.addr, title: short, full: shown, app: w.app, icon: w.icon, kind: w.kind,
      pre: h.pre, hit: h.hit, post: h.post,
      ws: w.ws, profile: w.profile, ticket: redacted ? "" : w.ticket,
      unavail: w.unavail || redacted, bars: (w.unavail || redacted) ? [] : (BARS[w.kind] || BARS.other),
      dim: w.dim, group: group, badge: group ? w.tabs.length + " tabs" : (isTab ? "tab " + (w.tabIdx + 1) + "/" + w.tabCount : ""),
      selected: n > 0 && i === sel, suggested: suggested,
      faded: top.length > 0 && top.indexOf(w.addr) < 0, ring: top.indexOf(w.addr) >= 0,
      confirm: st.confirm === w.addr,
      aria: shown + ", " + w.app + ", workspace " + w.ws + ", " + w.profile
    }
  })

  var layoutW = layout === "list" ? 780 : layout === "grid" ? 893 : (n >= 5 ? 893 : Math.max(680, n * 212 - 12 + 32))
  var vw = layoutW - 32
  var contentW = Math.max(n * 212 - 12, 1)
  var tx = contentW <= vw ? (vw - contentW) / 2 : Math.min(0, Math.max(vw - contentW, vw / 2 - (sel * 212 + 100)))

  // one window (or none) and no filter: the strip would be a lone card, Alt+Tab is a no-op
  var mode = (total <= 1 && !filtering) ? "single" : (n === 0 ? "nomatch" : "strip")

  var cur = cards[sel]
  var caption = null
  if (cur) {
    if (mode === "single") caption = { title: "Nothing else open", meta: [{ t: "Alt+Tab is a no-op", tone: "dim" }], count: "" }
    else if (redacted) caption = { title: cur.app, meta: [{ t: "names hidden, app only", tone: "warn" }], count: (sel + 1) + " / " + n }
    else {
      var meta = [{ t: cur.dim ? cur.dim : "workspace " + cur.ws, tone: "dim" }, { t: cur.profile, tone: "accent" }]
      if (cur.ticket) meta.push({ t: cur.ticket, tone: "accent" })
      if (cur.group) meta = [{ t: "release focuses its last-active tab", tone: "dim" }, { t: cur.profile, tone: "accent" }]
      caption = { title: trunc(cur.full, 40), meta: meta,
                  count: (sel + 1) + " / " + n + (n > 7 && layout === "strip" ? "   +" + (n - 7) + " more" : "") }
    }
  }

  var status = null
  var undo = st.undo
  if (st.confirm && cur && st.confirm === cur.id)
    status = { text: cur.app + " is on the safe list. Press W again to close it.", tone: "warn", icon: "x" }
  else if (undo)
    status = { text: "Closed “" + trunc(undo.title, 28) + "”. Undo for 8 s.", tone: "accent", icon: "arrow-counter-clockwise", action: "Undo" }
  else if (st.msg) status = { text: st.msg, tone: "accent", icon: "list-bullets" }
  else if (ai) {
    var t = { thinking: "Asking the local model, titles only. Falls back to fuzzy match after 1.5 s.",
              done: "Suggested by the local model. Nothing is selected for you. Titles only, offline.",
              fallback: "Model took longer than 1.5 s. Showing fuzzy matches instead." }[ai.phase]
    status = { text: t, tone: "accent", icon: "sparkle" }
  } else if (redacted)
    status = { text: "Session just unlocked. Ticket and task names stay hidden for 2 s.", tone: "warn", icon: "lock" }

  var hints = filtering ? [["Esc", "clear"], ["Esc Esc", "cancel"]]
    : groupOpen ? [["Left Right", "tab"], ["Up", "collapse"], ["W", "close"]]
    : mode === "single" ? [["Esc", "cancel"]]
    : [["Tab", "next"], ["Shift+Tab", "back"], ["Down", "tabs"], ["W", "close"]]

  var qCount = ai ? (ai.phase === "thinking" ? "thinking" : ai.phase === "done" ? top.length + " ranked" : n + " of " + total)
    : n + " of " + total

  return {
    mode: mode, cards: cards, total: total, count: n, sel: sel, layout: layout,
    scopes: SCOPES.map(function (s) { return { id: s.id, label: s.label, key: s.key, on: st.scope === s.id } }),
    showScope: !filtering && !groupOpen, showGroupChip: groupOpen && !filtering, showQuery: filtering,
    query: st.query || "", qCount: qCount, thinking: !!ai && ai.phase === "thinking", ai: !!ai,
    hints: hints.map(function (h) { return { k: h[0], t: h[1] } }),
    caption: caption, status: status, redacted: redacted,
    panelW: layoutW, tx: tx, contentW: contentW, overflow: layout === "strip" && contentW > vw,
    hasMore: n > 8
  }
}

// ---- keys ------------------------------------------------------------------------------------
// returns { st: patch, side: { type, addr?, ... } | null }. The shell applies both.
function nav(m, st, key, ticket) {
  var n = m.cards.length
  var cur = m.cards[m.sel]
  var p = {}
  var none = { st: p, side: null }
  if (m.mode === "locked") return none
  var scopeKeys = { "`": "task", "1": "workspace", "2": "profile", "3": "all" }
  if (scopeKeys[key]) { p.scope = scopeKeys[key]; p.sel = 1; p.msg = ""; p.group = ""; return { st: p, side: null } }
  if (!n) return none
  if (key === "tab" || key === "right") { p.sel = (m.sel + 1) % n; p.msg = ""; p.confirm = ""; return { st: p, side: null } }
  if (key === "shift-tab" || key === "left") { p.sel = (m.sel - 1 + n) % n; p.msg = ""; p.confirm = ""; return { st: p, side: null } }
  if (key === "down") {
    if (cur.group) {
      p.group = cur.addr; p.sel = m.sel; p.msg = ""
    } else p.msg = "Down only opens a grouped card. Select the Browser group first."
    return { st: p, side: null }
  }
  if (key === "up") {
    if (st.group) {
      var idx = 0
      m.cards.forEach(function (c, i) { if (c.addr === st.group && idx === 0) idx = i })
      p.group = ""; p.sel = idx
    }
    return { st: p, side: null }
  }
  if (key === "w") {
    if (cur.badge.indexOf("tab ") === 0) { p.msg = "Close works on whole windows. Collapse the group first."; return { st: p, side: null } }
    var safe = SAFE_KINDS.indexOf(cur.kind) >= 0
    if (safe && st.confirm !== cur.id) { p.confirm = cur.id; p.undo = null; p.msg = ""; return { st: p, side: null } }
    p.closed = (st.closed || []).concat([cur.addr])
    p.undo = { addr: cur.addr, title: cur.full }
    p.confirm = ""; p.msg = ""
    p.sel = Math.max(0, Math.min(m.sel, n - 2))
    return { st: p, side: { type: "closeLater", addr: cur.addr } }
  }
  if (key === "m") {
    p.msg = "Sent to the scratchpad. It stays at the end of the strip, dimmed."; p.confirm = ""
    return { st: p, side: { type: "scratch", addr: cur.addr } }
  }
  if (key === "p") {
    if (!ticket) { p.msg = "No current ticket to pin to."; return { st: p, side: null } }
    p.msg = "Pinned to " + ticket + ". Stored locally only."; p.confirm = ""
    return { st: p, side: { type: "pin", addr: cur.addr, ticket: ticket } }
  }
  if (key === "u") {
    p.msg = "Unlinked from its ticket. Stored locally only."; p.confirm = ""
    return { st: p, side: { type: "unpin", addr: cur.addr } }
  }
  return none
}

function selectedAddr(m) {
  var c = m.cards[m.sel]
  return c ? c.addr : ""
}

// the window a quick flip goes to: the previous one in the same order the strip uses
function previous(windows, mru, activeAddr) {
  var o = order(windows || [], mru).filter(function (w) { return !w.special && !w.hidden })
  for (var i = 0; i < o.length; i++) if (o[i].addr !== activeAddr) return o[i].addr
  return ""
}

function questionFor(q) { return isQuestion(q) }
