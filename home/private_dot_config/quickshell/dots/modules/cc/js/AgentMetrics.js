// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// View-model for Time > Agents and the Agents page cards (spec: docs/shell/specs/cc-agent-metrics.md).
// The daemon computes agent-metrics.json and away.json; this file only shapes them for drawing.
// Pure functions with no QML imports, so qmltestrunner covers them without a compositor.
// Tokens are always shown. Cost is a list price estimate and is always written "est.". Anything
// the file leaves out (a null cost, an omitted delta or prev, no live counts) draws as a dash or
// as nothing, never as a zero.
.pragma library
.import "Queue.js" as Q

var PERIODS = ["today", "week", "month"]
var PERIOD_NAME = { today: "Today", week: "This week", month: "This month" }
var PERIOD_PREV = { today: "yesterday", week: "last week", month: "last month" }
var STALE_SEC = 900
var KINDS = [["in", "Input"], ["out", "Output"], ["cacheWrite", "Cache write"], ["cacheRead", "Cache read"]]
var MINUS = "−"

function num(v) { return typeof v === "number" && isFinite(v) }
function pad2(n) { return (n < 10 ? "0" : "") + n }
function sentence(s) { return s.charAt(0).toUpperCase() + s.substring(1) }

// -> { state: missing | invalid | version | ok, doc }
function parse(text) {
    if (text === null || text === undefined || text === "") return { state: "missing", doc: null }
    var d = null
    try { d = JSON.parse(text) } catch (e) { d = null }
    if (!d || typeof d !== "object" || Array.isArray(d)) return { state: "invalid", doc: null }
    if (Number(d.v) !== 1) return { state: "version", doc: null }
    return { state: "ok", doc: d }
}

function emptyText(parsed) {
    var s = parsed ? parsed.state : "missing"
    if (s === "invalid") return "agent-metrics.json could not be read. The next dots-overview run rewrites it."
    if (s === "version") return "agent-metrics.json is a newer version than this panel reads."
    return "No agent-metrics.json yet. dots-overview writes it on its next run."
}

// ---- number text -----------------------------------------------------------------------
function tokens(n) {
    if (!num(n)) return "-"
    var a = Math.abs(n)
    if (a >= 1e9) return (n / 1e9).toFixed(2) + "B"
    if (a >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (a >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(Math.round(n))
}
function group(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }
function money(v) {
    if (!num(v)) return "n/a"
    var a = Math.abs(v)
    return "$" + (a < 10 ? v.toFixed(2) : group(v))
}
function cost(v, floor) { return num(v) ? "est. " + money(v) + (floor ? "+" : "") : "n/a" }
function dur(min) {
    if (!num(min)) return "-"
    if (min < 1) return "0m"
    if (min < 60) return Math.round(min) + "m"
    var h = Math.floor(min / 60)
    return h + "h " + pad2(Math.round(min - h * 60)) + "m"
}
function pct(v) { return num(v) ? Math.round(v * 100) + "%" : "-" }
function count(v) { return num(v) ? String(Math.round(v)) : "-" }

// the token total of a node whether the daemon wrote tokens as an object or as a plain number
function tokTotal(t) { return num(t) ? t : (t && typeof t === "object" && num(t.total) ? t.total : NaN) }

// ---- change against the previous period ----------------------------------------------------
// -> { text, dir, tone, prev } ; text "" when the file gave neither a delta nor both values
//    worse: "up" when a rise is bad (waiting on you), "" when neither direction is good or bad
function change(cur, prev, given, fmt, worse) {
    var d = num(given) ? given : ((num(cur) && num(prev)) ? cur - prev : NaN)
    var out = { text: "", dir: "flat", tone: "neutral", prev: num(prev) ? fmt(prev) : "" }
    if (!num(d)) return out
    out.dir = d > 0.0001 ? "up" : (d < -0.0001 ? "down" : "flat")
    out.text = out.dir === "flat" ? "0" : (d > 0 ? "+" : MINUS) + fmt(Math.abs(d))
    if (worse === "up") out.tone = out.dir === "up" ? "bad" : (out.dir === "down" ? "good" : "neutral")
    return out
}

function section(doc, name) { return doc && doc.periods && doc.periods[name] ? doc.periods[name] : null }
function prevOf(p) { return p && p.prev && typeof p.prev === "object" ? p.prev : null }
function deltaOf(p, key) { return p && p.delta && typeof p.delta === "object" ? p.delta[key] : undefined }

// Does this period have anything to draw?
function has(doc, period) {
    var p = section(doc, period)
    return !!p && !!p.tokens && typeof p.tokens === "object"
}

// the last `n` days as series for the bar charts: oldest first, missing days kept as zero bars
function daily(doc, n) {
    var days = doc && Array.isArray(doc.days) ? doc.days : []
    var tail = days.slice(Math.max(0, days.length - (n || 30)))
    var out = { days: [], tokens: [], cost: [], runs: [], hasCost: false, peakTok: 0, peakCost: 0, totalTok: 0 }
    tail.forEach(function (d) {
        var t = d && d.tokens ? tokTotal(d.tokens) : NaN
        var c = d ? d.costUsd : null
        out.days.push(d ? String(d.day || "") : "")
        out.tokens.push(num(t) ? t : 0)
        out.cost.push(num(c) ? c : 0)
        out.runs.push(d && num(d.runs) ? d.runs : 0)
        if (num(c)) out.hasCost = true
        out.peakTok = Math.max(out.peakTok, num(t) ? t : 0)
        out.peakCost = Math.max(out.peakCost, num(c) ? c : 0)
        out.totalTok += num(t) ? t : 0
    })
    return out
}

// ---- KPI cards ---------------------------------------------------------------------------------
// -> [{ key, label, icon, has, value, sub, delta, dir, tone, prev, spark }]
function kpiCards(doc, period) {
    var p = section(doc, period)
    if (!p) return []
    var pv = prevOf(p)
    var floor = num(p.unpricedTokens) && p.unpricedTokens > 0
    var d = daily(doc, 30)
    var tk = p.tokens || {}
    function card(key, label, icon, value, ch, spark, extra) {
        var c = { key: key, label: label, icon: icon, has: value !== "", value: value === "" ? "" : value, delta: ch.text, dir: ch.dir, tone: ch.tone,
                  prev: ch.prev, spark: spark || [], note: "" }
        for (var k in extra) c[k] = extra[k]
        return c
    }
    var runsSpark = d.runs
    var cards = [
        card("runs", "Runs", "robot", num(p.runs) ? count(p.runs) : "", change(p.runs, pv ? pv.runs : NaN, deltaOf(p, "runs"), count), runsSpark),
        card("prompts", "Prompts", "chat-circle", num(p.prompts) ? count(p.prompts) : "", change(p.prompts, pv ? pv.prompts : NaN, deltaOf(p, "prompts"), count)),
        card("active", "Active time", "timer", num(p.activeMin) ? dur(p.activeMin) : "", change(p.activeMin, pv ? pv.activeMin : NaN, deltaOf(p, "activeMin"), dur)),
        card("waiting", "Waiting on you", "hourglass-medium", num(p.waitingMin) ? dur(p.waitingMin) : "", change(p.waitingMin, pv ? pv.waitingMin : NaN, deltaOf(p, "waitingMin"), dur, "up")),
        card("tokens", "Tokens", "stack", num(tokTotal(tk)) ? tokens(tokTotal(tk)) : "", change(tokTotal(tk), pv ? tokTotal(pv.tokens) : NaN, deltaOf(p, "tokens"), tokens), d.tokens),
        card("cost", "Cost", "receipt", num(p.costUsd) ? cost(p.costUsd, floor) : "", change(p.costUsd, pv ? pv.costUsd : NaN, deltaOf(p, "costUsd"), money), d.hasCost ? d.cost : [],
             { note: "list price estimate" })
    ]
    return cards
}

// ---- tokens by kind: one stacked bar ---------------------------------------------------------------
// -> { total, segs: [{ key, label, v, text, frac }] } ; segs empty when there are no tokens
function kindBar(doc, period) {
    var p = section(doc, period), tk = p && p.tokens ? p.tokens : null
    var segs = [], sum = 0
    if (tk) KINDS.forEach(function (k) { if (num(tk[k[0]]) && tk[k[0]] > 0) sum += tk[k[0]] })
    if (tk && sum > 0) KINDS.forEach(function (k) {
        var v = num(tk[k[0]]) ? tk[k[0]] : 0
        segs.push({ key: k[0], label: k[1], v: v, text: tokens(v), frac: v / sum, pct: v / sum >= 0.1 ? Math.round(100 * v / sum) + "%" : (v / sum >= 0.005 ? "<" + Math.max(1, Math.ceil(100 * v / sum)) + "%" : "") })
    })
    return { total: sum, segs: segs }
}

// ---- tables ------------------------------------------------------------------------------------------
// titles: { ref: title } for ticket labels (the mirror's refs); {} when none are known
function ticketLabel(key, titles) {
    var k = String(key === undefined || key === null ? "" : key)
    if (k === "") return "No ticket"
    var t = titles && titles[k] ? titles[k] : ""
    var l = Q.label("", k, t)
    if (l !== "") return l
    var bare = k.replace(/^lane:/, "")
    if (bare !== k && titles && titles[bare]) {
        l = Q.label("", bare, titles[bare])
        if (l !== "") return l
    }
    return /^local:/.test(bare) ? "Local task" : "Task"
}

function modelName(key) {
    var k = String(key || "")
    return k === "" ? "unknown model" : k.replace(/^claude-/, "")
}

function rowOf(kind, r, titles, floorTok) {
    var t = tokTotal(r.tokens)
    var out = { kind: kind, key: String(r.key === undefined ? "" : r.key), runs: num(r.runs) ? r.runs : NaN, activeMin: num(r.activeMin) ? r.activeMin : NaN,
                tokens: t, costUsd: num(r.costUsd) ? r.costUsd : null, models: Array.isArray(r.models) ? r.models : [],
                priced: r.priced !== false }
    out.label = kind === "ticket" ? ticketLabel(r.key, titles) : (kind === "model" ? modelName(r.key) : (String(r.key || "") || "unnamed"))
    out.tokText = tokens(t)
    out.costText = num(r.costUsd) ? cost(r.costUsd, false) : (r.priced === false ? "no price" : "n/a")
    out.runsText = count(r.runs)
    out.activeText = dur(r.activeMin)
    out.share = num(floorTok) && floorTok > 0 && num(t) ? t / floorTok : 0
    return out
}

function rows(doc, period, kind, titles) {
    var p = section(doc, period)
    var src = p ? p[kind === "agent" ? "byAgent" : (kind === "ticket" ? "byTicket" : "byModel")] : null
    if (!Array.isArray(src)) return []
    var total = p && p.tokens ? tokTotal(p.tokens) : NaN
    return src.map(function (r) { return rowOf(kind, r || {}, titles, total) })
}

// the rows j and k walk, top to bottom: agents, tickets, models. `at` is the first index of each
function navRows(doc, period, titles) {
    var a = rows(doc, period, "agent", titles), t = rows(doc, period, "ticket", titles), m = rows(doc, period, "model", titles)
    return { agents: a, tickets: t, models: m, all: a.concat(t, m), tickets0: a.length, models0: a.length + t.length }
}

// ---- subagents and live --------------------------------------------------------------------------------
function subagent(doc, period) {
    var p = section(doc, period)
    if (!p || !num(p.subagentShare)) return { has: false, text: "-", frac: 0 }
    return { has: true, text: pct(p.subagentShare), frac: Math.max(0, Math.min(1, p.subagentShare)) }
}

// -> { has, working, needs, idle, agents } ; has false when the file carries no live counts
function live(doc) {
    var l = doc && doc.live && typeof doc.live === "object" ? doc.live : null
    if (!l) return { has: false, working: 0, needs: 0, idle: 0, agents: 0 }
    var by = l.byStatus && typeof l.byStatus === "object" ? l.byStatus : {}
    var needs = num(l.needsYou) ? l.needsYou : 0
    var working = num(by.working) ? by.working : 0
    var idle = (num(by.idle) ? by.idle : 0) + (num(by.done) ? by.done : 0)
    return { has: true, working: working, needs: needs, idle: idle, agents: num(l.agents) ? l.agents : working + needs + idle }
}

// ---- the whole page ------------------------------------------------------------------------------------------
function model(doc, period, titles) {
    var nav = navRows(doc, period, titles)
    var p = section(doc, period)
    var floor = !!p && num(p.unpricedTokens) && p.unpricedTokens > 0
    return { period: period, name: PERIOD_NAME[period], prevName: PERIOD_PREV[period], cards: kpiCards(doc, period), kinds: kindBar(doc, period),
             nav: nav, daily: daily(doc, 30), sub: subagent(doc, period), live: live(doc), unpriced: floor ? p.unpricedTokens : 0,
             range: p && p.first ? (p.first === p.last ? p.first : p.first + " to " + p.last) : "" }
}

// ---- the Agents page card (today) ----------------------------------------------------------------------------
// -> { has, runs, tokens, cost, note }
function todayCard(doc) {
    var p = section(doc, "today")
    if (!p || !p.tokens) return { has: false, runs: "-", tokens: "-", cost: "n/a", active: "-" }
    var floor = num(p.unpricedTokens) && p.unpricedTokens > 0
    return { has: true, runs: count(p.runs), tokens: tokens(tokTotal(p.tokens)), cost: cost(p.costUsd, floor), active: dur(p.activeMin) }
}

// ---- away history ---------------------------------------------------------------------------------------------------
var DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function whenText(ts) {
    var d = new Date(ts * 1000)
    return DOW[d.getDay()] + " " + d.getDate() + " " + MON[d.getMonth()] + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function awayLabel(g) {
    var l = String(g.label || g.category || "").trim()
    if (l === "" || l === "misc") return "Away"
    return sentence(l)
}

// -> { state, has, count, unanswered, totalMin, rows: [{ when, minutes, minText, label, answered }] } newest first
function away(text) {
    var p = parse(text)
    if (p.state !== "ok" || !Array.isArray(p.doc.gaps)) return { state: p.state === "ok" ? "invalid" : p.state, has: false, count: 0, unanswered: 0, totalMin: 0, rows: [] }
    var gaps = p.doc.gaps.filter(function (g) { return g && num(g.startTs) && num(g.minutes) })
    gaps.sort(function (a, b) { return b.startTs - a.startTs })
    var rows = gaps.map(function (g) {
        return { when: whenText(g.startTs), minutes: g.minutes, minText: dur(g.minutes), label: awayLabel(g), answered: g.answered === true, day: String(g.day || "") }
    })
    var un = rows.filter(function (r) { return !r.answered }).length
    var tot = 0
    rows.forEach(function (r) { tot += r.minutes })
    return { state: "ok", has: rows.length > 0, count: rows.length, unanswered: un, totalMin: tot, rows: rows }
}

// ---- keyboard ---------------------------------------------------------------------------------------------------------
// j k move through nav.all, p P switch the period. -> { row, period }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
function step(st, action, arg, nRows) {
    var s = { row: st.row, period: st.period }
    var n = Number(arg) || 0, max = Math.max(0, nRows - 1)
    if (action === "move") s.row = clamp(s.row + n, 0, max)
    else if (action === "top") s.row = 0
    else if (action === "bottom") s.row = max
    else if (action === "page") s.row = clamp(s.row + 10 * n, 0, max)
    else if (action === "period") { s.period = (s.period + (n > 0 ? 1 : PERIODS.length - 1)) % PERIODS.length; s.row = 0 }
    s.row = clamp(s.row, 0, max)
    return s
}

function hints() {
    return [["j k", "row"], ["p P", "period"], ["Enter", "jump to agent"], ["g G", "ends"], ["[ ]", "sub-tab"]]
}
