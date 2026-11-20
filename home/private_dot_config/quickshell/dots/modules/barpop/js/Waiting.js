// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The waiting popup's model, from the attention feed's items. Triage order is fixed:
// problems, then red chips (age at least 1.5x its rule), then amber, oldest first
// inside a colour. Six rows, the rest live in the sidebar. Pure functions.
.pragma library

var MAX_ROWS = 6
var RULE_MIN = { critical: 0, time: 60, active: 120, passive: 240 }
var TITLE = { all: "Waiting on you", mail: "Mail", chat: "Chat", agent: "Agent", problem: "Problems" }
var ORDER = { mail: "rule: reply within 1h", chat: "rule: reply within 1h", agent: "rule: waits for your click", problem: "rule: alert at once" }
var ICON = { all: "clock", mail: "envelope-simple", chat: "chat-text", agent: "robot", problem: "warning", other: "clipboard-text" }
var LABEL = { blocker: "Blocker", review: "Review", alert: "Problem", dm: "Chat", erp: "ERP ticket", mail: "Mail", task: "Task" }

function fmtAge(sec) {
    var m = Math.max(0, Math.floor((Number(sec) || 0) / 60))
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60), r = m % 60
    return r ? h + "h " + r + "m" : h + "h"
}

function category(it) {
    if (it.kind === "alert") return "problem"
    if (it.kind === "dm") return "chat"
    if (it.kind === "mail") return "mail"
    if (it.src === "herdr") return "agent"
    return "other"
}

function ruleMin(it) {
    return RULE_MIN.hasOwnProperty(it.urgency) ? RULE_MIN[it.urgency] : 0
}

// red | amber | dim. A rule of zero (alert at once) never goes grey.
function tone(it) {
    if (category(it) === "problem") return "red"
    var rule = ruleMin(it)
    if (!rule) return "amber"
    var r = ((Number(it.ageSec) || 0) / 60) / rule
    return r >= 1.5 ? "red" : (r >= 0.5 ? "amber" : "dim")
}

function isWaiting(it) {
    return !!it && it.kind !== "task" && (it.waiting === true || it.kind === "alert")
}

function openable(url) { return /^https:\/\/[^\s]+$/.test(String(url || "")) }

function rank(it) {
    if (category(it) === "problem") return 0
    return tone(it) === "red" ? 1 : 2
}

// items: attention.json items (or null). opts: { filter, focusId, focusFirst, stale, prayerIn }
function build(items, opts) {
    opts = opts || {}
    var filter = TITLE.hasOwnProperty(opts.filter) ? opts.filter : "all"
    var alive = (items || []).filter(isWaiting)
    var counts = { all: alive.length, mail: 0, chat: 0, agent: 0, problem: 0 }
    alive.forEach(function (it) { var c = category(it); if (counts.hasOwnProperty(c)) counts[c]++ })

    var shown = alive.filter(function (it) { return filter === "all" || category(it) === filter })
    shown.sort(function (a, b) {
        var r = rank(a) - rank(b)
        return r ? r : (Number(b.ageSec) || 0) - (Number(a.ageSec) || 0)
    })
    var vis = shown.slice(0, MAX_ROWS)
    var fid = ""
    vis.forEach(function (it) { if (it.id === opts.focusId) fid = it.id })
    if (!fid && opts.focusFirst && vis.length) fid = vis[0].id
    var rows = vis.map(function (it) {
        var cat = category(it)
        var rule = ruleMin(it)
        var rt = cat === "problem" ? "alert at once" : (rule ? "rule " + fmtAge(rule * 60) : "waiting")
        return {
            id: it.id, subj: String(it.title || it.ref || it.id), age: fmtAge(it.ageSec), tone: tone(it),
            muted: (it.actor ? it.actor + " · " : "") + (LABEL[it.kind] || "Item") + " · " + rt,
            icon: ICON[cat === "other" ? "other" : cat], category: cat,
            focused: it.id === fid,
            canJump: !!it.jump, canOpen: openable(it.url), ref: it.ref || "", url: it.url || ""
        }
    })
    var moreN = Math.max(0, shown.length - vis.length)
    var problems = counts.problem
    var banner = null
    if (opts.stale) banner = { kind: "unknown", text: "Sources are stale. Showing the last known list." }
    else if (problems > 0 && filter === "all") banner = { kind: "red", text: problems + " problem" + (problems > 1 ? "s" : "") + ". Fix it first, the rest wait." }

    return {
        filter: filter, title: TITLE[filter], icon: ICON[filter],
        count: shown.length, counts: counts,
        chips: ["all", "mail", "chat", "agent", "problem"].map(function (k) {
            return { key: k, label: k === "all" ? "All" : TITLE[k] === "Problems" ? "Problem" : TITLE[k], n: counts[k], on: k === filter }
        }),
        order: filter === "all" ? (problems > 0 ? "problems first, then oldest" : "oldest first within colour") : ORDER[filter],
        prayer: filter === "all" && opts.prayerIn !== undefined && opts.prayerIn !== null && opts.prayerIn >= 0 ? "prayer in " + opts.prayerIn + "m" : "",
        banner: banner, rows: rows, moreN: moreN,
        moreLabel: moreN > 0 ? moreN + " more, open sidebar" : "Open sidebar",
        empty: shown.length === 0, stale: !!opts.stale
    }
}
