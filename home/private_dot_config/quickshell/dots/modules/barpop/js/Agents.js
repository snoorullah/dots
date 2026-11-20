// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The agent popup's model. Cards are attention items that come from herdr (an agent
// asking for you); running, paused, done and budget come from the optional agents.json
// (v1). Both are read-only: nothing here approves, denies or answers anything.
.pragma library

function fmtEl(sec) {
    var m = Math.max(0, Math.floor((Number(sec) || 0) / 60))
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60), r = m % 60
    return r ? h + "h " + r + "m" : h + "h"
}

function money(n) {
    var v = Number(n) || 0
    return "$" + (Math.round(v * 100) % 100 === 0 ? String(Math.round(v)) : v.toFixed(2))
}

// items: attention items; doc: agents.json or null; opts: { focusId }
function build(items, doc, opts) {
    opts = opts || {}
    var asks = (items || []).filter(function (it) { return it && it.src === "herdr" && it.waiting === true })
    asks.sort(function (a, b) { return (Number(b.ageSec) || 0) - (Number(a.ageSec) || 0) })
    var focusId = opts.focusId && asks.some(function (a) { return a.id === opts.focusId }) ? opts.focusId : (asks.length ? asks[0].id : "")
    var cards = asks.map(function (it) {
        return { id: it.id, agent: it.actor || "agent", age: fmtEl(it.ageSec), verb: String(it.title || it.id),
                 obj: it.ref ? String(it.ref) : "", canJump: !!it.jump, ref: it.ref || "", focused: it.id === focusId }
    })

    var ok = doc && typeof doc === "object" && doc.v === 1
    var running = ok && doc.running ? doc.running.map(function (r) {
        var p = (r.progress === null || r.progress === undefined) ? -1 : Math.round(Math.max(0, Math.min(1, +r.progress)) * 100)
        return { name: String(r.name || "agent"), task: String(r.task || ""), el: fmtEl(r.elapsedSec), pct: p }
    }) : []
    var paused = ok && doc.paused ? doc.paused.map(function (r) { return { name: String(r.name || "agent"), why: String(r.why || "") } }) : []
    var done = ok && doc.done ? doc.done.slice(0, 3).map(String) : []
    var budget = null
    if (ok && doc.budget && +doc.budget.cap > 0) {
        budget = { text: money(doc.budget.used) + " / " + money(doc.budget.cap), pct: Math.round(Math.min(1, doc.budget.used / doc.budget.cap) * 100) }
    }
    return {
        cards: cards, quiet: cards.length === 0,
        pill: cards.length > 0 ? "Needs you " + cards.length : "All clear", lit: cards.length > 0,
        running: running, paused: paused, done: done, budget: budget
    }
}
