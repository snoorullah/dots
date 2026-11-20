// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Grouped windows: the tab strip for the focused window's Hyprland group. Pure.
//   clients: [{ addr, cls, title, grouped: [addr, ...] }]   grouped is in tab order, and holds the window itself
.pragma library
.import "../../wsswitch/js/Model.js" as Model

function build(clients, activeAddr, mask) {
  var by = {}
  ;(clients || []).forEach(function (c) { by[c.addr] = c })
  var me = by[activeAddr]
  var addrs = me && me.grouped && me.grouped.length > 1 ? me.grouped : []
  var tabs = []
  addrs.forEach(function (a) {
    var c = by[a]
    if (!c) return
    var app = Model.appOf(c.cls)
    var hide = !!mask && Model.sensitive(c.cls, c.title)
    tabs.push({ addr: a, icon: app.icon, title: hide ? Model.MASKED : (String(c.title || "") || app.label), active: a === activeAddr })
  })
  var n = tabs.length
  return { show: n > 1, tabs: tabs, n: n, text: n + " in group" }
}

// the tab after or before the active one, wrapping
function step(m, d) {
  if (!m.show) return ""
  var i = 0
  for (var k = 0; k < m.tabs.length; k++) if (m.tabs[k].active) i = k
  return m.tabs[(i + d + m.tabs.length) % m.tabs.length].addr
}
