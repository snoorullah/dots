// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The tray popover's list model: group by status, fuzzy-filter by title. The input is a
// plain array of { id, title, status, hasMenu, icon } (the QML side maps SystemTrayItem
// onto it), so tests need no D-Bus. Pure functions.
.pragma library

var GROUPS = [
    { key: "attention", label: "NEEDS ATTENTION", status: "Needs attention" },
    { key: "active", label: "ACTIVE", status: "Active" },
    { key: "idle", label: "IDLE", status: "Idle" }
]

function groupKey(status) {
    return status === "NeedsAttention" ? "attention" : (status === "Active" ? "active" : "idle")
}

// subsequence match, case-insensitive: "mvp" finds "Mesh VPN"
function fuzzy(name, q) {
    q = String(q || "").trim().toLowerCase()
    if (!q) return true
    var n = String(name).toLowerCase(), i = 0
    for (var k = 0; k < q.length; k++) {
        i = n.indexOf(q.charAt(k), i)
        if (i < 0) return false
        i++
    }
    return true
}

function build(items, query) {
    var list = (items || []).map(function (it) {
        return { id: String(it.id), name: String(it.title || it.id), group: groupKey(it.status), hasMenu: !!it.hasMenu,
                 icon: it.icon || "", glyph: it.glyph || "squares-four" }
    })
    var all = list.length
    list = list.filter(function (r) { return fuzzy(r.name, query) })
    var groups = []
    GROUPS.forEach(function (g) {
        var rows = list.filter(function (r) { return r.group === g.key }).map(function (r) {
            return { id: r.id, name: r.name, hasMenu: r.hasMenu, icon: r.icon, glyph: r.glyph, status: g.status, tone: g.key === "attention" ? "waiting" : "none" }
        })
        if (rows.length) groups.push({ key: g.key, label: g.label + " · " + rows.length, rows: rows })
    })
    return { groups: groups, total: list.length, empty: all === 0, noMatch: all > 0 && list.length === 0 }
}
