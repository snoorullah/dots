// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// View-model rules for the control centre: feed items to board rows, sections, grouping,
// filtering, per-kind actions, time and agent tables. Pure functions with no QML imports,
// so qmltestrunner covers them without a compositor.
.pragma library

var DAY = 86400
var SECTIONS = ["WAITING ON YOU", "TODAY", "WHILE YOU WERE AWAY", "FROM YESTERDAY", "PREVIOUS PENDING REVIEWS"]

// feed kind -> board kind and source label. `task` never reaches the queue: tasks live on
// the Tasks tab. Mail items are read-only here (replying is a stub).
var KIND = {
    blocker: { kind: "agent", src: "Agent", label: "agent stopped" },
    review: { kind: "pr", src: "GitHub", label: "review requested" },
    alert: { kind: "alert", src: "Alert", label: "alert" },
    dm: { kind: "msg", src: "Slack", label: "direct message" },
    mail: { kind: "mail", src: "Mail", label: "mail" },
    erp: { kind: "ticket", src: "ERP", label: "ticket" },
    untracked: { kind: "capture", src: "You", label: "time with no ticket" }
}
var RANK = { critical: 3, time: 2, active: 1, passive: 0 }

var SRC_ICON = { All: "funnel", Agent: "sparkle", Slack: "chat-circle", Mail: "envelope", GitHub: "git-pull-request", ERP: "ticket", Alert: "bell-ringing", You: "note-pencil" }
function srcIcon(src) { return SRC_ICON[src] || "funnel" }

// ---- human ids --------------------------------------------------------------
// The bar's rule (BarModel.js ticketOf / plainDesc): say the HD number or repo plus number, never a
// TASK- / local: / lane: id. The daemon sends `ticket` when it knows one.
var INTERNAL_RE = /^(?:TASK-\d{4}-\d+|local:|lane:)/

function pad4(n) { n = String(n); return n.length < 4 ? ("0000" + n).slice(-4) : n }

function isInternal(ref) { return INTERNAL_RE.test(String(ref || "").trim()) }

// the ticket a person would say for a ref (and the title as a second source), "" when none
function humanRef(ref, title) {
    var r = String(ref || "").trim(), d = String(title || "")
    var m = /^(?:HD[ -]?#?)?(\d{3,6})$/.exec(r)
    if (m) return "HD " + pad4(m[1])
    m = /^gh:[^\/\s]+\/([^#\s]+)#(\d+)$/.exec(r)
    if (m) return m[1] + "#" + m[2]
    if (r && !isInternal(r)) return r
    m = /\bHD[ -]?#?(\d{3,6})\b/.exec(d)
    return m ? "HD " + pad4(m[1]) : ""
}

// the title without the ids the ticket already says
function plainDesc(desc) {
    var d = String(desc === undefined || desc === null ? "" : desc)
    d = d.replace(/\(\s*(?:(?:TASK-\d{4}-\d+|HD[ -]?#?\d{3,6})\s*[,;]?\s*)+\)/g, " ")
    d = d.replace(/\bTASK-\d{4}-\d+\b/g, " ")
    d = d.replace(/^\s*HD[ -]?#?\d{3,6}\s*[:\-]\s*/, "")
    d = d.replace(/\s+/g, " ").replace(/^[\s:,;-]+|[\s:,;-]+$/g, "")
    return isInternal(d) ? "" : d
}

// "HD 8580 Fix the thing": ticket (daemon's, else derived) plus a short description
function label(ticket, ref, title) {
    var t = ticket ? String(ticket) : humanRef(ref, title)
    var d = plainDesc(title)
    if (d === String(ref || "") || d === t) d = ""
    return (t && d) ? t + " " + d : (t || d)
}

function age(sec) {
    var s = Math.max(0, Number(sec) || 0)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < DAY) return Math.floor(s / 3600) + "h"
    return Math.floor(s / DAY) + "d"
}

// 6120 -> "1:42" (hours:minutes, the board's time format)
function hm(sec) {
    var m = Math.floor(Math.max(0, Number(sec) || 0) / 60)
    var mm = m % 60
    return Math.floor(m / 60) + ":" + (mm < 10 ? "0" : "") + mm
}

// Estimated logout as a countdown stopwatch: the moment today's worked time reaches the target
// (8h), read from the last activity.json (workedSec at docTs) and counted down each second.
// A break moves it later on the next refresh. Past the target it counts up: "+0:12:05".
// "" when there is no figure.
var DAY_TARGET_SEC = 8 * 3600
function logoutLeft(workedSec, docTs, nowSec, targetSec) {
    if (workedSec === undefined || workedSec === null || !(Number(docTs) > 0)) return ""
    var t = Number(targetSec) > 0 ? Number(targetSec) : DAY_TARGET_SEC
    var d = Math.round(t - Number(workedSec) - (Number(nowSec) - Number(docTs)))
    var over = d < 0, a = Math.abs(d)
    var h = Math.floor(a / 3600), m = Math.floor(a % 3600 / 60), sec = a % 60
    function p2(x) { return (x < 10 ? "0" : "") + x }
    return (over ? "+" : "") + h + ":" + p2(m) + ":" + p2(sec)
}

// epoch seconds -> local "17:04" (the login time under "Day so far")
function clock(ts) {
    var d = new Date((Number(ts) || 0) * 1000)
    var h = d.getHours(), m = d.getMinutes()
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

function sectionOf(tone, ageSec, nowSec, sinceTs, section) {
    if (section === "previous") return SECTIONS[4]
    if (tone) return SECTIONS[0]
    if (ageSec >= DAY) return SECTIONS[3]
    if (sinceTs > 0 && nowSec - ageSec < sinceTs) return SECTIONS[2]
    return SECTIONS[1]
}

// The feed kind an item is filed under. The source wins for alerts and mail: an item from the
// alert/ops sources is an alert, one from the mail source is mail, whatever its kind says.
function feedKindOf(it) {
    var src = String(it.src || "")
    if (it.kind === "task" || it.kind === "blocker" || it.kind === "untracked") return it.kind
    if (src === "alert" || src === "ops") return "alert"
    if (src === "mail") return "mail"
    return it.kind
}

function fromFeed(items, nowSec, sinceTs) {
    var out = []
    var list = items || []
    for (var i = 0; i < list.length; i++) {
        var it = list[i]
        var k = it && KIND[feedKindOf(it)]
        if (!k) continue
        var fk = feedKindOf(it)
        var tone = it.waiting ? "wait" : (fk === "alert" ? "fail" : "")
        var ageSec = Math.max(0, Number(it.ageSec) || 0)
        var urg = String(it.urgency || "passive")
        out.push({
            id: String(it.id), kind: k.kind, src: k.src, feedKind: fk,
            who: it.actor ? String(it.actor) : "You",
            ageSec: ageSec, age: age(ageSec), tone: tone,
            sec: sectionOf(tone, ageSec, nowSec, sinceTs, it.section),
            title: String(it.title || ""),
            sub: k.label + (humanRef(it.ref, "") ? " · " + humanRef(it.ref, "") : ""),
            body: String(it.title || ""),
            ctx: humanRef(it.ref, ""),
            ref: it.ref ? String(it.ref) : "",
            url: it.url ? String(it.url) : "",
            jump: it.jump || null,
            canBreakdown: !!it.canBreakdown,
            urgency: urg,
            vip: !!it.vip,
            overdue: urg === "time" || urg === "critical",
            // no project field in the feed: alerts and ops/herdr items stand in for "infra"
            infra: fk === "alert" || it.src === "ops" || it.src === "herdr",
            raw: it
        })
    }
    return out
}

function sortItems(items) {
    return items.slice().sort(function (a, b) {
        var r = (RANK[b.urgency] || 0) - (RANK[a.urgency] || 0)
        if (r) return r
        var w = (b.tone ? 1 : 0) - (a.tone ? 1 : 0)
        if (w) return w
        return b.ageSec - a.ageSec
    })
}

// hidden: id -> "done" | "snoozed". View "Snoozed" shows only snoozed; everything else hides both.
function select(items, f) {
    var hidden = f.hidden || {}
    var out = []
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        var h = hidden[it.id] || ""
        if (f.view === "Snoozed") { if (h !== "snoozed") continue }
        else if (h) continue
        if (f.src && f.src !== "All" && it.src !== f.src) continue
        if (f.view === "VIPs" && !it.vip) continue
        if (f.view === "Overdue" && !it.overdue) continue
        if (f.view === "Infra only" && !it.infra) continue
        out.push(it)
    }
    return out
}

function counts(items, hidden) {
    // an agent that needs me is an item like any other: Queue and Inbox list the same things
    var q = 0
    for (var i = 0; i < items.length; i++) {
        if ((hidden || {})[items[i].id]) continue
        q++
    }
    return { queue: q, inbox: q }
}

function group(items, by) {
    var sorted = sortItems(items)
    var keyOf = function (it) {
        return by === "Source" ? it.src.toUpperCase() : (by === "Person" ? it.who.toUpperCase() : it.sec)
    }
    var order = by === "Urgency" ? SECTIONS.slice() : []
    var map = {}
    sorted.forEach(function (it) {
        var k = keyOf(it)
        if (!map[k]) { map[k] = []; if (order.indexOf(k) < 0) order.push(k) }
        map[k].push(it)
    })
    return order.filter(function (k) { return map[k] }).map(function (k) {
        return { name: k, count: map[k].length, items: map[k] }
    })
}

function neighbour(items, id, delta) {
    if (!items || items.length === 0) return ""
    var at = -1
    for (var i = 0; i < items.length; i++) if (items[i].id === id) at = i
    if (at < 0) return items[0].id
    return items[Math.max(0, Math.min(items.length - 1, at + delta))].id
}

// the row to select once `id` leaves the list: the one below, else the one above
function afterRemoval(items, id) {
    var at = -1
    for (var i = 0; i < items.length; i++) if (items[i].id === id) at = i
    if (at < 0) return items.length ? items[0].id : ""
    if (at + 1 < items.length) return items[at + 1].id
    return at > 0 ? items[at - 1].id : ""
}

// ---- actions --------------------------------------------------------------
// effect: open (xdg-open url, else dots-jump) | jump | breakdown | hide | mode | stub
// remote: the real action would write or send elsewhere, so it is a stub. A remote action with
// a `mode` still opens its compose panel (typing is local); only the Send inside stays disabled.
function A(label, key, icon, effect, o) {
    o = o || {}
    return { label: label, key: key, icon: icon, effect: effect, primary: !!o.primary, remote: !!o.remote, mode: o.mode || "", hide: o.hide || "" }
}

var BY_KIND = {
    agent: [A("Allow once", "a", "check", "stub", { primary: true, remote: true }), A("Deny", "d", "x", "stub", { remote: true }),
            A("Open pane", "o", "terminal-window", "jump"), A("Snooze", "s", "alarm", "mode", { mode: "snooze" })],
    msg: [A("Reply", "r", "arrow-bend-up-left", "mode", { primary: true, remote: true, mode: "reply" }), A("Send to agent", "g", "paper-plane-tilt", "mode", { remote: true, mode: "agent" }),
          A("Queue", "q", "list-plus", "hide", { hide: "queue" }), A("Snooze", "s", "alarm", "mode", { mode: "snooze" }), A("Open", "o", "arrow-square-out", "open")],
    alert: [A("See analysis", "v", "magnifying-glass", "open", { primary: true }), A("Fix in repo", "f", "git-branch", "stub", { remote: true }),
            A("Queue", "q", "list-plus", "hide", { hide: "queue" }), A("Snooze", "s", "alarm", "mode", { mode: "snooze" })],
    pr: [A("Open review", "o", "eye", "open", { primary: true }), A("Send to agent", "g", "paper-plane-tilt", "mode", { remote: true, mode: "agent" }),
         A("Queue", "q", "list-plus", "hide", { hide: "queue" }), A("Snooze", "s", "alarm", "mode", { mode: "snooze" })],
    ticket: [A("Comment", "c", "chat-circle", "mode", { primary: true, remote: true, mode: "reply" }), A("Send to agent", "g", "paper-plane-tilt", "mode", { remote: true, mode: "agent" }),
             A("Queue", "q", "list-plus", "hide", { hide: "queue" }), A("Remind", "s", "alarm", "mode", { mode: "snooze" }), A("Open", "o", "arrow-square-out", "open")],
    mail: [A("Draft reply", "r", "pencil-simple", "mode", { primary: true, remote: true, mode: "reply" }), A("Send to agent", "g", "paper-plane-tilt", "mode", { remote: true, mode: "agent" }),
           A("Queue", "q", "list-plus", "hide", { hide: "queue" }), A("Snooze", "s", "alarm", "mode", { mode: "snooze" })],
    capture: [A("Make a task", "t", "check-square", "stub", { primary: true, remote: true }), A("Send to agent", "g", "paper-plane-tilt", "mode", { remote: true, mode: "agent" }),
              A("Dismiss", "x", "x", "hide", { hide: "dismiss" })]
}

function actionsFor(kind) {
    var head = BY_KIND[kind] || []
    return head.concat([A("Break down & start", "b", "list-plus", "breakdown"), A("Jump", "j", "arrow-square-out", "jump")])
}

// whether the item can take an action right now (local data permitting)
function canRun(action, item) {
    if (!item) return false
    if (action.effect === "stub") return false
    if (action.effect === "breakdown") return item.canBreakdown
    if (action.effect === "jump") return !!item.jump || !!item.url
    if (action.effect === "open") return !!item.url || !!item.jump
    return true
}

function statusFor(label, arg) {
    if (label === "Queue") return "Queued. Hidden for this session."
    if (label === "Dismiss") return "Dismissed."
    if (label === "Snooze" || label === "Remind") return "Snoozed: " + String(arg || "").toLowerCase() + ". It stays listed under Snoozed."
    if (label === "Break down & start") return "Broken into steps. First step started."
    if (label === "Jump" || label === "Open pane") return "Jumped to the source. Esc returns you."
    return label + "."
}

// ---- other tabs -----------------------------------------------------------
var BY = { Project: ["byProject", "project"], Item: ["byRef", "ref"], Agent: ["byAgent", "agent"], App: ["byApp", "app"] }

function timeRows(bucket, by) {
    var spec = BY[by]
    var list = (bucket && spec && bucket[spec[0]]) || []
    var rows = list.map(function (r) {
        var n = String(r[spec[1]] || "")
        if (by === "Item") n = label(r.ticket, r.ref, r.title) || "No ticket"
        return { n: n, sec: Number(r.sec) || 0 }
    }).sort(function (a, b) { return b.sec - a.sec })
    var max = rows.length ? rows[0].sec : 0
    return rows.map(function (r) { return { n: r.n, v: hm(r.sec), w: max > 0 ? Math.round(100 * r.sec / max) : 0 } })
}

var REF_RE = /\b(TASK-\d{4}-\d+|HD[ -]?\d+|[A-Z]{2,6}-\d+)\b/

function refIn(text) {
    var m = REF_RE.exec(String(text || ""))
    return m ? m[1] : ""
}

// first usable line of a prompt: tags and blanks are skipped
function promptLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim()
        if (l && l.charAt(0) !== "<") return l.length > 120 ? l.substring(0, 120) : l
    }
    return ""
}

// "TASK-1 part b: verify" -> "part b: verify" (the ref moves to the For column)
function workOn(title, ref) {
    var t = String(title || "")
    if (ref && t.indexOf(ref) === 0) t = t.substring(ref.length)
    return t.replace(/^[\s:\-.]+/, "").trim()
}

// tasks: raw feed items (kind task) that carry a herdr pane (jump.sess); sessions: sess -> the
// hook's session record ({agent, ticket, prompt_head, pane}).
function agentRows(items, nowAgent, byAgent, tasks, sessions) {
    var rows = []
    var seen = {}
    ;(items || []).forEach(function (it) {
        if (it.kind !== "agent") return
        var w = it.tone === "wait"
        var hr = humanRef(it.ref, "")
        rows.push({ name: it.who, forRef: hr, task: it.title, state: w ? "Waiting on you" : "Reported", tone: w ? "wait" : "", age: it.age, last: hr || (w ? "needs your answer" : ""), action: w ? "Answer" : "View", item: it })
    })
    var sess = sessions || {}
    ;(tasks || []).forEach(function (t) {
        if (!t || t.kind !== "task" || !t.jump || !t.jump.sess) return
        var s = sess[t.jump.sess] || {}
        var ref = refIn(t.title) || refIn(s.ticket) || refIn(t.ref)
        var work = workOn(t.title, ref) || (t.title ? "" : promptLine(s.prompt_head))
        if (t.jump.pane) seen[t.jump.pane] = true
        rows.push({ name: String(s.agent || t.actor || "agent"), forRef: ref, task: work, state: "Working", tone: "", age: age(t.ageSec), last: t.jump.pane ? "pane " + t.jump.pane : "", action: "Jump", item: { raw: t, jump: t.jump, url: t.url || "" }, pane: t.jump.pane || "" })
    })
    if (nowAgent && nowAgent.name && !(nowAgent.pane && seen[nowAgent.pane])) {
        rows.push({ name: String(nowAgent.name), forRef: "", task: "", state: String(nowAgent.status || "Working"), tone: "", age: "", last: nowAgent.cwd ? String(nowAgent.cwd) : "", action: "Open", item: null, pane: nowAgent.pane || "" })
    }
    ;(byAgent || []).forEach(function (a) {
        if (nowAgent && nowAgent.name === a.agent) return
        rows.push({ name: String(a.agent), forRef: "", task: "", state: "Ran today", tone: "", age: "", last: hm(a.sec) + " today", action: "", item: null })
    })
    return rows
}

var SRC_ORDER = [["notif", "Notifications"], ["mail", "Mail"], ["gh", "GitHub"], ["ops", "Alerts"], ["herdr", "Agents"], ["erp", "ERP"]]
var SRC_LABEL = { ok: "live", stale: "stale", error: "error", unavailable: "unavailable", off: "off" }

// A healthy source shows plain text, never green. tone: "" fine | "unknown" cannot reach | "off" dim
function sourceRows(sources) {
    var s = sources || {}
    return SRC_ORDER.map(function (p) {
        var st = s[p[0]] && s[p[0]].state
        var tone = st === "ok" ? "" : (st === "off" || st === "unavailable" ? "off" : "unknown")
        return { name: p[1], label: SRC_LABEL[st] || "unknown", tone: tone }
    })
}

// Segment widths for a bar `width` wide with `gap` between segments: proportional to `secs`,
// whole pixels, and they sum to the bar exactly (the rounding error is spread, never added up).
function barWidths(secs, width, gap) {
    var n = (secs || []).length
    if (n === 0) return []
    var avail = Math.max(0, Number(width) - Number(gap) * (n - 1))
    var total = 0
    for (var i = 0; i < n; i++) total += Math.max(0, Number(secs[i]) || 0)
    var out = [], prev = 0, cum = 0
    for (var j = 0; j < n; j++) {
        cum += Math.max(0, Number(secs[j]) || 0)
        var edge = total > 0 ? Math.round(avail * cum / total) : 0
        out.push(edge - prev)
        prev = edge
    }
    return out
}

// Totals under the heatmap: whole-number days worked, summed seconds, best day.
function heatTotals(days) {
    var tot = 0, n = 0, best = null
    ;(days || []).forEach(function (d) {
        var s = Number(d.workedSec) || 0
        if (s <= 0) return
        tot += s
        n++
        if (!best || s > best.sec) best = { d: d.d, sec: s }
    })
    return { totalSec: tot, daysWorked: n, avgSec: n ? Math.round(tot / n) : 0, best: best }
}
