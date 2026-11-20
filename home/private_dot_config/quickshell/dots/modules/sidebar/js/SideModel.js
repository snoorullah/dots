// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Pure presentation logic for the sidebar: tab filters, row grouping, source names.
// No QML imports, tested under qmltestrunner (tst/tst_sidemodel.qml).
.pragma library
.import "../../overview/js/Model.js" as Model
.import "../../overview/js/Fmt.js" as Fmt

var TABS = [
    { key: "queue", label: "Queue" },
    { key: "inbox", label: "Inbox" },
    { key: "agents", label: "Agents" },
    { key: "work", label: "Work" },
    { key: "time", label: "Time" }
]

var DAY = 86400

function ccTab(key) {
    for (var i = 0; i < TABS.length; i++) if (TABS[i].key === key) return key
    return "queue"
}

function has(list, v) { return list.indexOf(v) >= 0 }

// Which items a tab shows. Unknown tab = everything.
function filterTab(items, tab) {
    var all = items || []
    return all.filter(function (i) {
        switch (tab) {
        case "inbox": return has(["dm", "erp"], i.kind)
        case "agents": return i.src === "agent"
        case "work": return has(["task", "review", "blocker"], i.kind)
        case "time": return i.kind === "untracked"
        default: return true
        }
    })
}

// "waiting" (someone waits on me), "failed" (an alert nobody waits on), "" otherwise.
function mark(item) {
    if (item.waiting) return "waiting"
    return item.kind === "alert" ? "failed" : ""
}

function groupKey(item) {
    if (mark(item) !== "") return "waiting"
    if (item.away === true) return "away"
    return (+item.ageSec || 0) >= DAY ? "yesterday" : "today"
}

var HEADS = [
    { key: "waiting", name: "WAITING ON YOU" },
    { key: "today", name: "TODAY" },
    { key: "away", name: "WHILE YOU WERE AWAY" },
    { key: "yesterday", name: "FROM YESTERDAY" }
]

// Flat list for a ListView/Repeater: { head, key } rows and { item, key } rows. Empty groups
// are dropped. Inside a group the overview's ordering (urgency, waiting, oldest) holds.
function group(items) {
    var sorted = Model.sortItems(items || [])
    var out = []
    for (var h = 0; h < HEADS.length; h++) {
        var mine = sorted.filter(function (i) { return groupKey(i) === HEADS[h].key })
        if (mine.length === 0) continue
        out.push({ head: HEADS[h].name, key: "head:" + HEADS[h].key })
        for (var k = 0; k < mine.length; k++) out.push({ item: mine[k], key: "item:" + mine[k].id })
    }
    return out
}

// [display name, icon key]. The key is mapped to a Phosphor name in SideRow.qml.
var SRC = {
    gh: ["GitHub", "github"], github: ["GitHub", "github"],
    slack: ["Slack", "slack"], dm: ["Slack", "slack"],
    erp: ["ERP", "erp"], mail: ["Mail", "mail"],
    agent: ["Agent", "agent"], timetrack: ["You", "you"], you: ["You", "you"]
}

function srcEntry(item) {
    var s = String(item.src || "").toLowerCase()
    if (SRC.hasOwnProperty(s)) return SRC[s]
    if (item.kind === "alert") return ["Alert", "alert"]
    if (item.kind === "untracked") return ["You", "you"]
    return null
}
function srcLabel(item) { var e = srcEntry(item); return e ? e[0] : "" }
function srcKey(item) { var e = srcEntry(item); return e ? e[1] : "" }

function who(item) { return item && item.actor ? String(item.actor) : "" }

function age(item) { return Fmt.age(item.ageSec) }

function pickTitle(item) { return item && item.title ? String(item.title) : "Pick an item" }
