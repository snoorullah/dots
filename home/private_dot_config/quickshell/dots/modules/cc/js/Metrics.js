// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// View-model for the Time sub-tabs (spec: docs/shell/specs/cc-time-kpis.md, keys:
// docs/shell/specs/cc-keys.md). The daemon computes every number into metrics.json; this file
// only shapes it for drawing: weeks, day rows, heat grid, KPI cards, trends, the report text and
// the keyboard cursor. Pure functions with no QML imports, so qmltestrunner covers them without
// a compositor. A key the daemon left out is a key the page says is missing, never a zero.
.pragma library

var SUBS = [["today", "Today"], ["week", "Week"], ["days", "Days"], ["heatmap", "Heatmap"], ["zones", "Focus zones"],
            ["progress", "Progress"], ["report", "Report"], ["screen", "Screen and health"], ["reminders", "Reminders"], ["agents", "Agents"]]
var PERIODS = ["today", "week", "month", "quarter"]
var PERIOD_NAME = { today: "Today", week: "This week", month: "This month", quarter: "This quarter" }
var PERIOD_PREV = { today: "yesterday", week: "last week", month: "last month", quarter: "last quarter" }
var DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MINUS = "−"
var STALE_SEC = 600

function subId(name) { for (var i = 0; i < SUBS.length; i++) if (SUBS[i][1] === name) return SUBS[i][0]; return "today" }
function subName(id) { for (var i = 0; i < SUBS.length; i++) if (SUBS[i][0] === id) return SUBS[i][1]; return "Today" }

// ---- file ------------------------------------------------------------------------------
// -> { state: missing | invalid | version | ok, doc, v, ageSec }
function parse(text, nowTs) {
    if (text === null || text === undefined || text === "") return { state: "missing", doc: null, ageSec: -1 }
    var d = null
    try { d = JSON.parse(text) } catch (e) { d = null }
    if (!d || typeof d !== "object" || Array.isArray(d)) return { state: "invalid", doc: null, ageSec: -1 }
    if (Number(d.v) !== 1) return { state: "version", v: d.v, doc: null, ageSec: -1 }
    var age = (Number(d.ts) > 0 && Number(nowTs) > 0) ? Math.max(0, nowTs - d.ts) : -1
    return { state: "ok", doc: d, ageSec: age }
}

function ago(sec) {
    if (!num(sec) || sec < 0) return ""
    if (sec < 90) return "just now"
    if (sec < 5400) return Math.round(sec / 60) + " min ago"
    return Math.round(sec / 3600) + " h ago"
}

function isStale(parsed) { return !!parsed && parsed.state === "ok" && parsed.ageSec > STALE_SEC }

// where each section comes from, in words a person would say (no host or company names)
var NEED = {
    days: "the work tracker database (work.db)",
    periods: "the work tracker database (work.db)",
    improve: "the work tracker database (work.db)",
    zones: "the focus log (private.db, focus_span)",
    screen: "ActivityWatch on localhost:5600",
    health: "the health log (private.db, health_checkpoint)",
    reminders: "Taskwarrior (task export)"
}
var TITLE = { days: "day history", periods: "period totals", improve: "improvement metrics", zones: "focus zones", screen: "screen time", health: "health checkpoints", reminders: "reminders" }
var SRC_KEYS = { days: ["days", "work"], periods: ["periods", "work"], improve: ["improve", "work"], zones: ["zones", "private"], screen: ["screen", "aw"], health: ["health", "private"], reminders: ["reminders", "tasks", "task"] }

function srcStatus(doc, section) {
    var s = doc && doc.sources, keys = SRC_KEYS[section] || [section]
    if (!s) return null
    for (var i = 0; i < keys.length; i++) {
        var v = s[keys[i]]
        if (v === undefined || v === null) continue
        if (typeof v === "string") return { status: v, reason: "" }
        return { status: String(v.status || v.state || ""), reason: String(v.reason || v.why || "") }
    }
    return null
}

function present(doc, section) {
    if (!doc || doc[section] === undefined || doc[section] === null) return false
    if (section === "days") return doc.days.length > 0
    return true
}

// The one line an empty tab shows. `parsed` is parse()'s result, `section` a key of NEED.
function emptyText(parsed, section) {
    if (!parsed || parsed.state === "missing") return "No metrics yet. dots-overview has not written ~/.local/state/dots-overview/metrics.json."
    if (parsed.state === "invalid") return "metrics.json is not valid JSON. The next dots-overview cycle rewrites it."
    if (parsed.state === "version") return "metrics.json is version " + parsed.v + "; this build reads version 1."
    var st = srcStatus(parsed.doc, section)
    var why = st && st.reason ? " " + sentence(st.reason) + (/[.!]$/.test(st.reason) ? "" : ".") : ""
    return "No " + (TITLE[section] || section) + ": " + (NEED[section] || "its source") + " was not readable." + why
}

// ---- number formats -----------------------------------------------------------------------
function pad2(n) { return (n < 10 ? "0" : "") + n }
function num(v) { return typeof v === "number" && isFinite(v) }
function hm(min) {
    if (!num(min)) return "-"
    var m = Math.round(Math.abs(min))
    return (min < 0 && m > 0 ? MINUS : "") + Math.floor(m / 60) + ":" + pad2(m % 60)
}
function hmSec(sec) { return num(sec) ? hm(sec / 60) : "-" }
function signedHm(min) {
    if (!num(min)) return "-"
    var m = Math.round(min)
    if (m === 0) return "0:00"
    return (m > 0 ? "+" : MINUS) + Math.floor(Math.abs(m) / 60) + ":" + pad2(Math.abs(m) % 60)
}
function pct(v) { return num(v) ? Math.round(v) + "%" : "-" }
function dec(v, n) { return num(v) ? String(Math.round(v * Math.pow(10, n)) / Math.pow(10, n)) : "-" }
function clockMin(m) {
    if (!num(m)) return "-"
    var x = Math.round(m) % 1440
    return pad2(Math.floor(x / 60)) + ":" + pad2(x % 60)
}
function clockTs(ts) {
    if (!(Number(ts) > 0)) return "-"
    var d = new Date(ts * 1000)
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}
function minOfDay(ts) {
    if (!(Number(ts) > 0)) return undefined
    var d = new Date(ts * 1000)
    return d.getHours() * 60 + d.getMinutes()
}
function signedNum(v, unit) {
    if (!num(v)) return "-"
    var r = Math.round(v * 10) / 10
    if (r === 0) return "0" + (unit ? " " + unit : "")
    return (r > 0 ? "+" : MINUS) + Math.abs(r) + (unit ? " " + unit : "")
}

// a value by unit kind: min | sec | pct | count | clock
function fmt(kind, v) {
    if (!num(v)) return "-"
    if (kind === "min") return hm(v)
    if (kind === "sec") return hmSec(v)
    if (kind === "pct") return pct(v)
    if (kind === "clock") return clockMin(v)
    return String(Math.round(v))
}
function fmtDelta(kind, v) {
    if (!num(v)) return "-"
    if (kind === "min" || kind === "sec" || kind === "clock") return signedHm(kind === "sec" ? v / 60 : v)
    if (kind === "pct") return signedNum(v, "pts")
    return signedNum(Math.round(v))
}
function dirOf(delta) { return !num(delta) || delta === 0 ? "flat" : (delta > 0 ? "up" : "down") }
// good: +1 more is better, -1 less is better, 0 neither. -> good | bad | neutral
function toneOf(delta, good) {
    if (!num(delta) || delta === 0 || !good) return "neutral"
    return (delta > 0) === (good > 0) ? "good" : "bad"
}

// ---- dates ---------------------------------------------------------------------------------
function parseDay(s) { var p = String(s).split("-"); return Date.UTC(+p[0], +p[1] - 1, +p[2]) }
function fmtDay(ms) { var d = new Date(ms); return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate()) }
function addDays(s, n) { return fmtDay(parseDay(s) + n * 86400000) }
function dow(s) { return (new Date(parseDay(s)).getUTCDay() + 6) % 7 }
function weekStart(s) { return addDays(s, -dow(s)) }
function dayNum(s) { return new Date(parseDay(s)).getUTCDate() }
function monName(s) { return MON[new Date(parseDay(s)).getUTCMonth()] }
function dayLabel(s) { return DOW[dow(s)] + " " + dayNum(s) + " " + monName(s) }
function shortLabel(s) { return dayNum(s) + " " + monName(s) }
function monthKey(s) { return String(s).substring(0, 7) }
function monthLabel(key) { return MON[+key.substring(5, 7) - 1] + " " + key.substring(0, 4) }

// ---- doc accessors ---------------------------------------------------------------------------
function dayList(doc) { return doc && doc.days ? doc.days : [] }
function dayMap(doc) {
    var m = {}, l = dayList(doc)
    for (var i = 0; i < l.length; i++) m[l[i].day] = l[i]
    return m
}
function todayOf(doc) {
    if (doc && doc.today) return doc.today
    var l = dayList(doc)
    return l.length ? l[l.length - 1].day : ""
}
function working(d) { return !d.kind || d.kind === "working" }

// ---- series colours: tokens, never hex, never green --------------------------------------------
var SERIES = [{ tok: "accent", a: 1 }, { tok: "accent", a: 0.55 }, { tok: "waiting", a: 1 }, { tok: "waiting", a: 0.55 },
              { tok: "fgDim", a: 0.9 }, { tok: "fgDim", a: 0.45 }]
function series(slot) { return SERIES[Math.max(0, Math.min(slot, SERIES.length - 1))] }

// ---- Week ---------------------------------------------------------------------------------------
function sumField(rows, key) {
    var t = 0, any = false
    for (var i = 0; i < rows.length; i++) if (num(rows[i][key])) { t += rows[i][key]; any = true }
    return any ? t : undefined
}

// offset 0 is this week, -1 last week. Seven rows Monday first, stacked by focus zone.
function weekModel(doc, offset) {
    var today = todayOf(doc), map = dayMap(doc), byDay = (doc && doc.zones && doc.zones.byDay) || {}
    var ws = addDays(weekStart(today), 7 * (offset || 0))
    var zoneTot = {}, rows = [], i, j
    for (i = 0; i < 7; i++) {
        var day = addDays(ws, i), d = map[day], zs = byDay[day] || []
        for (j = 0; j < zs.length; j++) zoneTot[zs[j].zone] = (zoneTot[zs[j].zone] || 0) + zs[j].min
        rows.push({ day: day, label: DOW[i], num: dayNum(day), has: !!d, isToday: day === today, future: day > today,
                    kind: d ? d.kind : "", workedMin: d ? d.workedMin : undefined, targetMin: d ? d.targetMin : undefined,
                    focusMin: d ? d.focusMin : undefined, deductionMin: d ? d.deductionMin : undefined, tasksDone: d ? d.tasksDone : undefined,
                    loginTs: d ? d.loginTs : undefined, logoutTs: d ? d.logoutTs : undefined, zones: zs, segs: [] })
    }
    var order = Object.keys(zoneTot).sort(function (a, b) { return zoneTot[b] - zoneTot[a] || (a < b ? -1 : 1) })
    var slot = {}, legend = []
    for (i = 0; i < order.length; i++) { slot[order[i]] = i; legend.push({ zone: order[i], min: zoneTot[order[i]], slot: i }) }
    var tgt = 0
    for (i = 0; i < 7; i++) {
        var r = rows[i], w = r.workedMin || 0, zsum = 0
        for (j = 0; j < r.zones.length; j++) zsum += r.zones[j].min
        var k = zsum > w && zsum > 0 ? w / zsum : 1, used = 0
        for (j = 0; j < r.zones.length; j++) {
            var m = r.zones[j].min * k
            if (m > 0) { r.segs.push({ zone: r.zones[j].zone, min: m, slot: slot[r.zones[j].zone] }); used += m }
        }
        r.segs.sort(function (a, b) { return a.slot - b.slot })
        r.restMin = Math.max(0, w - used)
        r.met = num(r.workedMin) && num(r.targetMin) && r.targetMin > 0 && r.workedMin >= r.targetMin
        if (num(r.targetMin) && r.targetMin > tgt && working(r)) tgt = r.targetMin
    }
    var total = sumField(rows, "workedMin"), target = 0, mx = 60
    for (i = 0; i < 7; i++) {
        if (rows[i].targetMin > 0 && working(rows[i])) target += rows[i].targetMin
        // a weekday still to come has no day_class yet: expect the usual target
        else if (!rows[i].has && rows[i].future && i < 5) target += tgt
        mx = Math.max(mx, rows[i].workedMin || 0, rows[i].targetMin || 0)
    }
    var prevRows = []
    for (i = 0; i < 7; i++) { var pd = map[addDays(ws, -7 + i)]; if (pd) prevRows.push(pd) }
    // the same elapsed days of last week, so a Monday is not judged against a full week
    var upto = offset === 0 ? Math.max(0, dow(today)) + 1 : 7
    var prevSame = []
    for (i = 0; i < upto; i++) { var qd = map[addDays(ws, -7 + i)]; if (qd) prevSame.push(qd) }
    var prev = prevSame.length ? sumField(prevSame, "workedMin") : undefined
    var delta = (num(total) && num(prev)) ? total - prev : undefined
    return {
        start: ws, end: addDays(ws, 6), label: shortLabel(ws) + " to " + shortLabel(addDays(ws, 6)), isCurrent: !offset,
        rows: rows, legend: legend, totalMin: total, targetMin: target, targetLineMin: tgt, leftMin: Math.max(0, target - (total || 0)),
        prevMin: prev, deltaMin: delta, deltaPct: (num(delta) && prev > 0) ? 100 * delta / prev : undefined,
        maxMin: Math.ceil(mx / 60) * 60, anyData: prevRows.length > 0 || num(total)
    }
}

function weeksAvailable(doc) {
    var l = dayList(doc)
    if (!l.length) return 1
    var first = weekStart(l[0].day), cur = weekStart(todayOf(doc))
    return Math.max(1, Math.round((parseDay(cur) - parseDay(first)) / (7 * 86400000)) + 1)
}

// ---- Days ----------------------------------------------------------------------------------------
function breakText(b) {
    if (!b) return ""
    var ks = Object.keys(b).sort(function (x, y) { return b[y] - b[x] }), out = []
    for (var i = 0; i < ks.length; i++) out.push(ks[i] + " " + hm(b[ks[i]]))
    return out.join(", ")
}

// newest first, one row per day with a day_class
function dayRows(doc) {
    var l = dayList(doc), out = []
    for (var i = l.length - 1; i >= 0; i--) {
        var d = l[i], sp = []
        for (var j = Math.max(0, i - 13); j <= i; j++) sp.push(l[j].workedMin || 0)
        out.push({
            day: d.day, label: dayLabel(d.day), kind: d.kind || "", working: working(d), isToday: d.day === todayOf(doc),
            login: d.loginTs ? clockTs(d.loginTs) : "", logout: d.logoutTs ? clockTs(d.logoutTs) : "",
            workedMin: d.workedMin, targetMin: d.targetMin, focusMin: d.focusMin, deductionMin: d.deductionMin,
            tasksDone: d.tasksDone, spark: sp,
            ratio: (num(d.workedMin) && d.targetMin > 0) ? Math.min(1.25, d.workedMin / d.targetMin) : 0
        })
    }
    return out
}

function kindText(kind) {
    return { working: "", weekend: "weekend", holiday: "holiday", leave_paid: "paid leave", leave: "leave", sick: "sick" }[kind] || kind || ""
}

function row(k, v, dim) { return { k: k, v: v === undefined || v === "" ? "no data" : v, dim: v === undefined || v === "" || !!dim } }

// the right-hand pane for one day: groups of label and value, nothing invented
function dayDetail(doc, day) {
    var d = dayMap(doc)[day]
    if (!d) return null
    var g = []
    g.push({ cap: "SESSION", rows: [
        row("Login", d.loginTs ? clockTs(d.loginTs) : undefined), row("Logout", d.logoutTs ? clockTs(d.logoutTs) : undefined),
        row("Span", num(d.spanMin) ? hm(d.spanMin) : undefined), row("Worked", num(d.workedMin) ? hm(d.workedMin) : undefined),
        row("Target", num(d.targetMin) ? hm(d.targetMin) : undefined), row("Away", num(d.deductionMin) ? hm(d.deductionMin) : undefined)] })
    var br = []
    if (d.breaks) {
        var ks = Object.keys(d.breaks).sort(function (a, b) { return d.breaks[b] - d.breaks[a] })
        for (var i = 0; i < ks.length; i++) br.push(row(ks[i], hm(d.breaks[ks[i]])))
    }
    if (br.length) g.push({ cap: "BREAKS", rows: br })
    g.push({ cap: "FOCUS", rows: [
        row("Focus", num(d.focusMin) ? hm(d.focusMin) : undefined), row("Deep work", num(d.deepWorkMin) ? hm(d.deepWorkMin) : undefined),
        row("Agents alone", num(d.agentOnlyMin) ? hm(d.agentOnlyMin) : undefined), row("Hands on", num(d.humanMin) ? hm(d.humanMin) : undefined),
        row("Switches", num(d.contextSwitches) ? String(d.contextSwitches) : undefined), row("Interruptions", num(d.interruptions) ? String(d.interruptions) : undefined)] })
    g.push({ cap: "OUTPUT", rows: [
        row("Tasks done", num(d.tasksDone) ? String(d.tasksDone) : undefined), row("PRs merged", num(d.prsMerged) ? String(d.prsMerged) : undefined),
        row("PRs reviewed", num(d.prsReviewed) ? String(d.prsReviewed) : undefined), row("Tickets closed", num(d.ticketsClosed) ? String(d.ticketsClosed) : undefined),
        row("Commits", num(d.commits) ? String(d.commits) : undefined)] })
    g.push({ cap: "HABITS", rows: [
        row("Salah on time", num(d.salahTotal) && d.salahTotal > 0 ? (d.salahOnTime + " of " + d.salahTotal) : undefined),
        row("Screen", num(d.screenSec) ? hmSec(d.screenSec) : undefined)] })
    var apps = []
    if (d.topApps) for (var a = 0; a < d.topApps.length; a++) apps.push(row(d.topApps[a].app, hmSec(d.topApps[a].sec)))
    if (apps.length) g.push({ cap: "TOP APPS", rows: apps })
    var zs = ((doc.zones && doc.zones.byDay) || {})[day] || [], zr = []
    for (var z = 0; z < zs.length; z++) zr.push(row(zs[z].zone, hm(zs[z].min)))
    if (zr.length) g.push({ cap: "FOCUS ZONES", rows: zr })
    return { day: day, title: dayLabel(day), kind: kindText(d.kind), groups: g }
}

// ---- Heatmap and months ------------------------------------------------------------------------
function level(d) {
    var w = d.workedMin
    if (!num(w) || w <= 0) return 0
    var t = d.targetMin
    if (!(t > 0)) return w >= 360 ? 3 : 2
    var r = w / t
    return r >= 1 ? 4 : (r >= 0.75 ? 3 : (r >= 0.4 ? 2 : 1))
}

// weeks as columns, Monday at the top; cells[col * 7 + row]
function heatGrid(doc) {
    var l = dayList(doc), today = todayOf(doc)
    if (!l.length) return { cols: 0, cells: [], months: [] }
    var map = dayMap(doc), start = weekStart(l[0].day), last = today || l[l.length - 1].day
    var cols = Math.floor((parseDay(weekStart(last)) - parseDay(start)) / (7 * 86400000)) + 1
    var cells = [], months = [], prevKey = ""
    for (var c = 0; c < cols; c++) {
        for (var r = 0; r < 7; r++) {
            var day = addDays(start, c * 7 + r), d = map[day]
            cells.push({ day: day, col: c, row: r, has: !!d, empty: !d, level: d ? level(d) : 0, kind: d ? d.kind : "",
                         workedMin: d ? d.workedMin : undefined, targetMin: d ? d.targetMin : undefined })
        }
        var mk = monthKey(addDays(start, c * 7))
        if (mk !== prevKey) { months.push({ col: c, label: MON[+mk.substring(5, 7) - 1] }); prevKey = mk }
    }
    if (months.length > 1 && months[1].col - months[0].col < 3) months.shift()
    return { cols: cols, cells: cells, months: months, start: start, days: l.length }
}

function cursorDay(doc, st) {
    var g = heatGrid(doc)
    if (st.sub === "heatmap") { var c = g.cells[st.col * 7 + st.row]; return c ? c.day : "" }
    if (st.sub === "week") return addDays(addDays(weekStart(todayOf(doc)), 7 * (st.weekOff || 0)), Math.max(0, Math.min(6, st.col)))
    return ""
}

// where the cursor starts on a sub-tab: today, so the first key press moves from somewhere real
function initCursor(doc, sub, weekOff) {
    var today = todayOf(doc)
    if (!today) return { row: 0, col: 0 }
    if (sub === "week") return { row: 0, col: weekOff ? 0 : dow(today) }
    if (sub === "heatmap") {
        var g = heatGrid(doc)
        for (var i = g.cells.length - 1; i >= 0; i--) if (g.cells[i].day === today) return { row: g.cells[i].row, col: g.cells[i].col }
    }
    return { row: 0, col: 0 }
}

// the last `n` weeks, newest first, each against the week before it
function weekRows(doc, n) {
    var l = dayList(doc), today = todayOf(doc)
    if (!l.length || !today) return []
    var map = dayMap(doc), out = []
    for (var k = 0; k < (n || 8); k++) {
        var ws = addDays(weekStart(today), -7 * k), w = 0, t = 0, any = false
        for (var i = 0; i < 7; i++) {
            var d = map[addDays(ws, i)]
            if (!d) continue
            any = true
            if (num(d.workedMin)) w += d.workedMin
            if (working(d) && num(d.targetMin)) t += d.targetMin
        }
        if (!any) break
        out.push({ week: ws, label: shortLabel(ws), workedMin: w, targetMin: t, ratio: t > 0 ? Math.min(1.25, w / t) : 0, partial: k === 0 || !map[ws] })
    }
    for (var j = 0; j < out.length - 1; j++) out[j].deltaMin = out[j].partial ? undefined : out[j].workedMin - out[j + 1].workedMin
    return out
}

// the last `n` days of focus time, stacked by zone with the ranking's colours
function zoneDays(doc, ranks, n) {
    var by = (doc && doc.zones && doc.zones.byDay) || {}, today = todayOf(doc), slot = {}, out = [], mx = 60
    for (var i = 0; i < ranks.rows.length; i++) slot[ranks.rows[i].zone] = ranks.rows[i].slot
    var extra = ranks.rows.length
    for (var k = (n || 14) - 1; k >= 0; k--) {
        var day = addDays(today, -k), zs = by[day] || [], segs = [], tot = 0
        for (var j = 0; j < zs.length; j++) {
            if (slot[zs[j].zone] === undefined) slot[zs[j].zone] = extra++
            segs.push({ zone: zs[j].zone, min: zs[j].min, slot: slot[zs[j].zone] })
            tot += zs[j].min
        }
        segs.sort(function (a, b) { return a.slot - b.slot })
        mx = Math.max(mx, tot)
        out.push({ day: day, label: String(dayNum(day)), total: tot, segs: segs })
    }
    return { days: out, maxMin: Math.ceil(mx / 60) * 60 }
}

// the last `n` months, newest first
function monthRows(doc, n) {
    var l = dayList(doc), by = {}, keys = []
    for (var i = 0; i < l.length; i++) {
        var k = monthKey(l[i].day)
        if (!by[k]) { by[k] = { key: k, label: monthLabel(k), workedMin: 0, targetMin: 0, daysWorked: 0, focusMin: 0, deepWorkMin: 0, tasksDone: 0, days: 0, partial: false }; keys.push(k) }
        var m = by[k], d = l[i]
        m.days++
        if (num(d.workedMin)) { m.workedMin += d.workedMin; if (d.workedMin > 0) m.daysWorked++ }
        if (working(d) && num(d.targetMin)) m.targetMin += d.targetMin
        if (num(d.focusMin)) m.focusMin += d.focusMin
        if (num(d.deepWorkMin)) m.deepWorkMin += d.deepWorkMin
        if (num(d.tasksDone)) m.tasksDone += d.tasksDone
    }
    var out = []
    for (var j = keys.length - 1; j >= 0; j--) {
        var x = by[keys[j]], older = j > 0 ? by[keys[j - 1]] : null
        x.avgMin = x.daysWorked ? Math.round(x.workedMin / x.daysWorked) : 0
        x.attainmentPct = x.targetMin > 0 ? 100 * x.workedMin / x.targetMin : undefined
        x.partial = j === keys.length - 1 || j === 0
        x.deltaMin = older && j >= 2 ? x.workedMin - older.workedMin : undefined
        out.push(x)
    }
    return out.slice(0, n || 5)
}

// ---- KPI cards ------------------------------------------------------------------------------------
var KPI = [
    { key: "workedMin", label: "Worked", kind: "min", good: 1, icon: "clock" },
    { key: "attainmentPct", label: "Target met", kind: "pct", good: 1, icon: "gauge" },
    { key: "focusMin", label: "Focus", kind: "min", good: 1, icon: "crosshair" },
    { key: "deepWorkMin", label: "Deep work", kind: "min", good: 1, icon: "hourglass-medium" },
    { key: "agentOnlyMin", label: "Agents alone", kind: "min", good: 0, icon: "robot" },
    { key: "humanMin", label: "Hands on", kind: "min", good: 0, icon: "person-simple-walk" },
    { key: "breakMin", label: "Breaks", kind: "min", good: 0, icon: "coffee" },
    { key: "daysWorked", label: "Days worked", kind: "count", good: 1, icon: "calendar-check" },
    { key: "avgLoginMin", label: "Average login", kind: "clock", good: 0, icon: "sun-dim" },
    { key: "avgLogoutMin", label: "Average logout", kind: "clock", good: 0, icon: "moon" },
    { key: "salahOnTimePct", label: "Salah on time", kind: "pct", good: 1, icon: "mosque" },
    { key: "contextSwitches", label: "Context switches", kind: "count", good: -1, icon: "stack" },
    { key: "interruptions", label: "Interruptions", kind: "count", good: -1, icon: "bell-ringing" },
    { key: "tasksDone", label: "Tasks done", kind: "count", good: 1, icon: "check-square" },
    { key: "prsMerged", label: "PRs merged", kind: "count", good: 1, icon: "git-pull-request" },
    { key: "prsReviewed", label: "PRs reviewed", kind: "count", good: 1, icon: "eye" },
    { key: "ticketsClosed", label: "Tickets closed", kind: "count", good: 1, icon: "ticket" },
    { key: "commits", label: "Commits", kind: "count", good: 1, icon: "git-branch" },
    { key: "screenSec", label: "Screen time", kind: "sec", good: 0, icon: "app-window" }
]
var KPI_COLS = 4

// the per-day value behind a KPI, or undefined when the day does not carry it
function dayValue(key, d) {
    switch (key) {
    case "attainmentPct": return (num(d.workedMin) && d.targetMin > 0) ? 100 * d.workedMin / d.targetMin : undefined
    case "breakMin": return d.deductionMin
    case "daysWorked": return num(d.workedMin) ? (d.workedMin > 0 ? 1 : 0) : undefined
    case "avgLoginMin": return minOfDay(d.loginTs)
    case "avgLogoutMin": return minOfDay(d.logoutTs)
    case "salahOnTimePct": return d.salahTotal > 0 ? 100 * d.salahOnTime / d.salahTotal : undefined
    }
    return d[key]
}

// up to `n` calendar days ending today, working days only, oldest first
function spark(doc, key, n) {
    var l = dayList(doc), out = []
    for (var i = Math.max(0, l.length - (n || 30)); i < l.length; i++) {
        if (!working(l[i])) continue
        var v = dayValue(key, l[i])
        if (num(v)) out.push(v)
    }
    return out
}

// "4 of 5 days": how many of the days in a period carry screen time, from periods.*.screenSec.
// "" when the file says nothing about coverage.
function screenCover(doc, period) {
    var k = doc && doc.periods && doc.periods[period] ? doc.periods[period].screenSec : null
    if (!k || typeof k !== "object" || !num(k.days) || !num(k.of) || k.of <= 0) return ""
    return k.days + " of " + k.of + (k.of === 1 ? " day" : " days")
}

function kpiCards(doc, period) {
    var p = (doc && doc.periods && doc.periods[period]) || {}, out = []
    for (var i = 0; i < KPI.length; i++) {
        var def = KPI[i], k = p[def.key], has = k !== undefined && k !== null
        var value = has ? (typeof k === "object" ? k.value : k) : undefined
        var prev = has && typeof k === "object" ? k.prev : undefined
        var delta = has && typeof k === "object" ? k.delta : undefined
        var dp = has && typeof k === "object" ? k.deltaPct : undefined
        if (num(value) && num(prev) && !num(delta)) delta = value - prev
        has = has && num(value)
        out.push({
            key: def.key, label: def.label, icon: def.icon, kind: def.kind, has: has,
            value: has ? fmt(def.kind, value) : "", prev: num(prev) ? fmt(def.kind, prev) : "",
            delta: num(delta) ? fmtDelta(def.kind, delta) : "", deltaPct: num(dp) ? signedNum(dp, "%") : "",
            dir: dirOf(delta), tone: toneOf(delta, def.good), spark: spark(doc, def.key, 30),
            note: def.key === "screenSec" ? screenCover(doc, period) : ""
        })
    }
    return out
}

function cardAt(cards, st) { return cards[st.row * KPI_COLS + st.col] || null }

// ---- improvement metrics --------------------------------------------------------------------------
// a window value: a plain number, or { d7, d30 } (also w7, "7", last7)
function win(x, n) {
    if (num(x)) return x
    if (!x || typeof x !== "object") return undefined
    var ks = ["d" + n, "w" + n, String(n), "last" + n, "days" + n]
    for (var i = 0; i < ks.length; i++) if (num(x[ks[i]])) return x[ks[i]]
    return undefined
}

function trendDir(t, key) {
    if (!t) return "flat"
    var d = t.dir
    if (d && typeof d === "object") d = d[key]
    return d === "up" || d === "down" ? d : (d === "flat" ? "flat" : dirOf(t[key]))
}

function improve(doc) {
    var im = doc && doc.improve
    if (!im) return null
    var trends = []
    var defs = [["workedMin", "Worked", "min", 1], ["focusMin", "Focus", "min", 1], ["deepWorkRatioPct", "Deep work share", "pct", 1]]
    for (var i = 0; i < defs.length; i++) {
        var key = defs[i][0], cells = []
        var wins = [["trend7", "7 days"], ["trend30", "30 days"]]
        for (var w = 0; w < wins.length; w++) {
            var t = im[wins[w][0]], s = t ? t[key] : undefined
            cells.push({ win: wins[w][1], has: num(s), slope: num(s) ? (defs[i][2] === "min" ? signedHm(s) : signedNum(s, "pts")) + " a day" : "",
                         dir: trendDir(t, key), tone: num(s) ? toneOf(trendDir(t, key) === "flat" ? 0 : s, defs[i][3]) : "neutral" })
        }
        trends.push({ label: defs[i][1], cells: cells })
    }
    var st = im.streaks || {}, best = st.best || {}, streaks = []
    var sd = [["targetMet", "Target met"], ["onTimeLogin", "On-time login"], ["salahOnTime", "Salah on time"]]
    for (var j = 0; j < sd.length; j++)
        if (num(st[sd[j][0]])) streaks.push({ label: sd[j][1], cur: st[sd[j][0]], best: num(best[sd[j][0]]) ? best[sd[j][0]] : undefined })
    var pu = im.punctuality, punct = null
    if (pu) punct = { target: num(pu.targetLoginMin) ? clockMin(pu.targetLoginMin) : "", late: num(pu.avgLateMin) ? Math.round(pu.avgLateMin) + " min" : "-",
                      onTime: num(pu.onTimeDays) && num(pu.days) ? pu.onTimeDays + " of " + pu.days + " days" : "-",
                      onTimePct: num(pu.onTimeDays) && pu.days > 0 ? 100 * pu.onTimeDays / pu.days : undefined }
    var ratios = [], rd = [["deepWorkRatioPct", "Deep work share", "pct"], ["interruptionsPerHour", "Interruptions an hour", "dec"], ["timeToFirstFocusMin", "Login to first focus", "min"]]
    for (var r = 0; r < rd.length; r++) {
        var x = im[rd[r][0]], a = win(x, 7), b = win(x, 30)
        if (!num(a) && !num(b)) continue
        var f = function (v) { return !num(v) ? "-" : (rd[r][2] === "pct" ? pct(v) : (rd[r][2] === "dec" ? dec(v, 1) : hm(v))) }
        ratios.push({ label: rd[r][1], w7: f(a), w30: f(b) })
    }
    return {
        trends: trends, streaks: streaks, punctuality: punct, ratios: ratios,
        bestDay: im.bestDay ? { label: dayLabel(im.bestDay.day), value: hm(im.bestDay.workedMin) } : null,
        worstDay: im.worstDay ? { label: dayLabel(im.worstDay.day), value: hm(im.worstDay.workedMin) } : null
    }
}

// ---- Focus zones -------------------------------------------------------------------------------------
// window: "week" (the last 7 days) or "month" (the 30 the daemon keeps)
function zoneRanks(doc, window) {
    var by = (doc && doc.zones && doc.zones.byDay) || {}, today = todayOf(doc), from = addDays(today, window === "week" ? -6 : -29)
    var tot = {}, sum = 0
    Object.keys(by).forEach(function (day) {
        if (day < from || day > today) return
        by[day].forEach(function (z) { tot[z.zone] = (tot[z.zone] || 0) + z.min; sum += z.min })
    })
    var names = Object.keys(tot).sort(function (a, b) { return tot[b] - tot[a] || (a < b ? -1 : 1) }), out = []
    for (var i = 0; i < names.length; i++) out.push({ zone: names[i], min: tot[names[i]], share: sum > 0 ? 100 * tot[names[i]] / sum : 0, slot: i })
    return { rows: out, totalMin: sum, from: from, to: today }
}

// twelve weeks, oldest first, stacked by zone with the same slot colours as the ranking
function zoneWeeks(doc, ranks) {
    var bw = (doc && doc.zones && doc.zones.byWeek) || [], slot = {}, out = [], mx = 60
    for (var i = 0; i < ranks.rows.length; i++) slot[ranks.rows[i].zone] = ranks.rows[i].slot
    var extra = ranks.rows.length
    for (var w = 0; w < bw.length; w++) {
        var segs = [], total = 0
        for (var j = 0; j < bw[w].zones.length; j++) {
            var z = bw[w].zones[j]
            if (slot[z.zone] === undefined) slot[z.zone] = extra++
            segs.push({ zone: z.zone, min: z.min, slot: slot[z.zone] })
            total += z.min
        }
        segs.sort(function (a, b) { return a.slot - b.slot })
        mx = Math.max(mx, total)
        out.push({ week: bw[w].week, label: shortLabel(String(bw[w].week)), total: total, segs: segs })
    }
    return { weeks: out, maxMin: Math.ceil(mx / 60) * 60 }
}

function projectRows(doc) {
    var p = (doc && doc.zones && doc.zones.projects) || [], out = []
    for (var i = 0; i < p.length; i++)
        out.push({ project: p[i].project, min: p[i].min, agentMin: p[i].agentMin, agentPct: p[i].min > 0 && num(p[i].agentMin) ? 100 * p[i].agentMin / p[i].min : undefined })
    out.sort(function (a, b) { return b.min - a.min })
    return out.slice(0, 8)
}

// ---- Screen and health (private) ----------------------------------------------------------------------
function screenModel(doc) {
    var s = doc && doc.screen
    if (!s) return null
    var ss = [], b = s.bySession || []
    for (var i = 0; i < b.length; i++)
        ss.push({ start: b[i].openTs ? clockTs(b[i].openTs) : "", end: b[i].closeTs ? clockTs(b[i].closeTs) : "open", active: hmSec(b[i].activeSec), sec: b[i].activeSec || 0 })
    return {
        today: num(s.todayActiveSec) ? hmSec(s.todayActiveSec) : "", idle: num(s.todayIdleSec) ? hmSec(s.todayIdleSec) : "",
        week: num(s.weekActiveSec) ? hmSec(s.weekActiveSec) : "", late: num(s.lateNightSec) ? hmSec(s.lateNightSec) : "",
        longest: num(s.longestStretchMin) ? hm(s.longestStretchMin) : "", sessions: ss, weekCover: screenCover(doc, "week"),
        activePct: num(s.todayActiveSec) && num(s.todayIdleSec) && s.todayActiveSec + s.todayIdleSec > 0 ? 100 * s.todayActiveSec / (s.todayActiveSec + s.todayIdleSec) : undefined,
        lateHigh: num(s.lateNightSec) && s.lateNightSec >= 3600
    }
}

var SLOTS = ["dose", "h1", "h3", "h6", "wrap"]
var SLOT_NAME = { dose: "Dose", h1: "1 h", h3: "3 h", h6: "6 h", wrap: "Wrap" }
function healthModel(doc, today) {
    var h = doc && doc.health
    if (!h) return null
    var cps = h.checkpoints || [], days = {}, order = []
    for (var i = 0; i < cps.length; i++) {
        var c = cps[i]
        if (!days[c.day]) { days[c.day] = {}; order.push(c.day) }
        days[c.day][c.slot] = c
    }
    order.sort()
    var rows = []
    for (var j = Math.max(0, order.length - 14); j < order.length; j++) {
        var cells = []
        for (var s = 0; s < SLOTS.length; s++) { var x = days[order[j]][SLOTS[s]]; cells.push({ slot: SLOTS[s], has: !!x, outcome: x ? x.outcome : "", score: x ? x.score : undefined }) }
        rows.push({ day: order[j], label: shortLabel(order[j]), cells: cells })
    }
    var doses = (h.doses || []).slice(-7).map(function (d) { return { day: shortLabel(d.day), at: clockTs(d.ts) } })
    return { rows: rows, slots: SLOTS.map(function (s) { return SLOT_NAME[s] }), avg7: num(h.scoreAvg7) ? dec(h.scoreAvg7, 1) : "",
             doseToFirst: num(h.doseToFirstCheckpointMin) ? Math.round(h.doseToFirstCheckpointMin) + " min" : "", doses: doses }
}

// ---- Reminders -------------------------------------------------------------------------------------------
function tsOf(v) {
    if (num(v)) return v > 1e11 ? v / 1000 : v
    if (typeof v === "string" && v) { var t = Date.parse(v); if (isFinite(t)) return t / 1000 }
    return NaN
}

function rel(ts, now) {
    if (!num(ts)) return ""
    var d = ts - now, a = Math.abs(d), m = Math.floor(a / 60), h = Math.floor(m / 60), dd = Math.floor(h / 24)
    var t = dd >= 2 ? dd + " days" : (h >= 1 ? h + " h " + pad2(m % 60) + " m" : Math.max(1, m) + " min")
    return d >= 0 ? "in " + t : t + " ago"
}

function whenText(ts) {
    if (!num(ts)) return ""
    var d = new Date(ts * 1000)
    return DOW[(d.getDay() + 6) % 7] + " " + d.getDate() + " " + MON[d.getMonth()] + ", " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// due first, then scheduled; `hidden` maps id to true for rows hidden this session
function reminderRows(doc, hidden, now) {
    var r = doc && doc.reminders
    if (!r) return null
    var out = []
    function add(list, kind, field) {
        for (var i = 0; list && i < list.length; i++) {
            var it = list[i], id = String(it.id)
            if (hidden && hidden[kind + ":" + id]) continue
            var ts = tsOf(it[field])
            out.push({ id: id, key: kind + ":" + id, kind: kind, desc: it.desc, ts: ts, when: whenText(ts), rel: rel(ts, now), overdue: kind === "due" && (it.overdue === true || (num(ts) && ts < now)) })
        }
    }
    add(r.due, "due", "due")
    add(r.scheduled, "scheduled", "scheduled")
    var sn = r.salahNext, salah = null
    if (sn && sn.prayer) { var st = tsOf(sn.iqamahTs); salah = { prayer: sn.prayer, at: clockTs(st), rel: rel(st, now) } }
    return { rows: out, salah: salah, dueCount: out.filter(function (x) { return x.kind === "due" }).length }
}

// ---- Report ---------------------------------------------------------------------------------------------------
function periodRange(doc, period) {
    var today = todayOf(doc), start = today
    if (period === "week") start = weekStart(today)
    else if (period === "month") start = today.substring(0, 8) + "01"
    else if (period === "quarter") start = today.substring(0, 5) + pad2(Math.floor((+today.substring(5, 7) - 1) / 3) * 3 + 1) + "-01"
    return { start: start, end: today, label: start === today ? dayLabel(today) : shortLabel(start) + " to " + shortLabel(today) }
}

function kpi(doc, period, key) {
    var p = doc && doc.periods && doc.periods[period], k = p ? p[key] : undefined
    if (k === undefined || k === null) return undefined
    return typeof k === "object" ? k : { value: k }
}

function sentence(s) { return s.charAt(0).toUpperCase() + s.substring(1) }

function reportLines(doc, period) {
    var out = [], rg = periodRange(doc, period), prevName = PERIOD_PREV[period]
    out.push("# Time report: " + PERIOD_NAME[period].toLowerCase() + " (" + rg.label + ")")
    var w = kpi(doc, period, "workedMin"), t = kpi(doc, period, "targetMin"), a = kpi(doc, period, "attainmentPct")
    if (w && num(w.value)) {
        var s = "- Worked " + hm(w.value)
        if (t && num(t.value)) s += " of " + hm(t.value) + " expected" + (a && num(a.value) ? " (" + pct(a.value) + ")" : "")
        if (num(w.delta)) s += ", " + signedHm(w.delta) + " against " + prevName
        out.push(s + ".")
    }
    var f = kpi(doc, period, "focusMin"), dw = kpi(doc, period, "deepWorkMin")
    if (f && num(f.value)) {
        var fs = "- Focus " + hm(f.value)
        if (dw && num(dw.value)) fs += ", of which deep work " + hm(dw.value) + (w && w.value > 0 ? " (" + pct(100 * dw.value / w.value) + " of worked time)" : "")
        out.push(fs + ".")
    }
    var ag = kpi(doc, period, "agentOnlyMin"), hu = kpi(doc, period, "humanMin")
    if (ag && hu && num(ag.value) && num(hu.value)) out.push("- Agents ran " + hm(ag.value) + " on their own; you were hands on for " + hm(hu.value) + ".")
    var bk = kpi(doc, period, "breakMin"), dwk = kpi(doc, period, "daysWorked"), li = kpi(doc, period, "avgLoginMin"), lo = kpi(doc, period, "avgLogoutMin")
    var parts = []
    if (bk && num(bk.value)) parts.push("breaks " + hm(bk.value))
    if (dwk && num(dwk.value)) parts.push(dwk.value + (dwk.value === 1 ? " day" : " days") + " worked")
    if (li && num(li.value)) parts.push("login about " + clockMin(li.value))
    if (lo && num(lo.value)) parts.push("logout about " + clockMin(lo.value))
    if (parts.length) out.push("- " + sentence(parts.join(", ")) + ".")
    var o = [], names = [["tasksDone", "tasks done"], ["prsMerged", "PRs merged"], ["prsReviewed", "PRs reviewed"], ["ticketsClosed", "tickets closed"], ["commits", "commits"]]
    for (var i = 0; i < names.length; i++) { var k = kpi(doc, period, names[i][0]); if (k && num(k.value)) o.push(Math.round(k.value) + " " + names[i][1]) }
    if (o.length) out.push("- Output: " + o.join(", ") + ".")
    var sa = kpi(doc, period, "salahOnTimePct"), ci = kpi(doc, period, "interruptions"), cs = kpi(doc, period, "contextSwitches"), h = []
    if (sa && num(sa.value)) h.push("salah on time " + pct(sa.value))
    if (ci && num(ci.value)) h.push(Math.round(ci.value) + " interruptions")
    if (cs && num(cs.value)) h.push(Math.round(cs.value) + " context switches")
    if (h.length) out.push("- " + sentence(h.join(", ")) + ".")
    var tp = doc && doc.periods && doc.periods[period] && doc.periods[period].topProjects
    if (tp && tp.length) out.push("- Top projects: " + tp.slice(0, 5).map(function (p) { return p.project + " " + hm(p.min) }).join(", ") + ".")
    var im = doc && doc.improve
    if (im && (period === "week" || period === "month" || period === "quarter")) {
        var tr = im.trend30, ds = []
        if (tr) {
            var nm = { workedMin: "worked time", focusMin: "focus", deepWorkRatioPct: "deep work share" }
            Object.keys(nm).forEach(function (kk) { if (num(tr[kk])) ds.push(nm[kk] + " " + trendDir(tr, kk)) })
        }
        if (ds.length) out.push("- Over 30 days: " + ds.join(", ") + ".")
        var st = im.streaks
        if (st && num(st.targetMet)) out.push("- Streaks: target met " + st.targetMet + (st.best && num(st.best.targetMet) ? " (best " + st.best.targetMet + ")" : "") +
            (num(st.onTimeLogin) ? ", on-time login " + st.onTimeLogin : "") + ".")
    }
    if (out.length === 1) out.push("- No numbers for this period yet.")
    return out
}

function reportText(doc, period) { return reportLines(doc, period).join("\n") + "\n" }
function reportName(doc, period) { return "time-" + period + "-" + todayOf(doc) + ".md" }

// ---- keyboard ----------------------------------------------------------------------------------------------------
// The state the Time page keeps. The view's Keys.resolve() turns a key into { action, arg }; nav()
// applies the Time ones. `sub` is the sub-tab id, `zone` is tabs | list | detail.
function initState(sub) {
    return { sub: sub || "today", zone: "tabs", row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 }
}
function clone(o) { var c = {}; for (var k in o) c[k] = o[k]; return c }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// rows and columns the cursor may use on the current sub-tab
function dims(doc, st, extra) {
    var e = extra || {}, d = { rows: 1, cols: 1, cards: 0 }
    switch (st.sub) {
    case "week": d.rows = Math.max(1, ((e.legend !== undefined ? e.legend : 0) + 1)); d.cols = 7; d.weeks = e.weeks || 1; break
    case "days": d.rows = Math.max(1, dayList(doc).length); break
    case "heatmap": d.rows = 7; d.cols = Math.max(1, heatGrid(doc).cols); break
    case "zones": d.rows = Math.max(1, e.zones || 0); break
    case "progress": d.cards = KPI.length; d.cols = KPI_COLS; d.rows = Math.ceil(KPI.length / KPI_COLS); break
    case "reminders": d.rows = Math.max(1, e.reminders || 0); break
    case "agents": d.rows = Math.max(1, e.agents || 0); break
    }
    return d
}

function fixCard(s, d) {
    if (s.sub !== "progress") return
    while (s.row * KPI_COLS + s.col >= d.cards && s.col > 0) s.col--
    while (s.row * KPI_COLS + s.col >= d.cards && s.row > 0) s.row--
}

// -> { st, effect }  effect: "" | copy | export | openDay | snooze | done | jump
function nav(st, action, arg, d) {
    var s = clone(st), eff = ""
    var maxRow = Math.max(0, d.rows - 1), maxCol = Math.max(0, d.cols - 1)
    var n = Number(arg) || 0
    switch (action) {
    case "subtab":
        s.sub = String(arg); s.row = 0; s.col = 0; s.detail = false; s.scroll = 0
        if (s.zone === "detail") s.zone = "list"
        break
    case "pane":
        s.zone = arg === "detail" || arg === "list" || arg === "tabs" ? arg : s.zone
        if (s.zone !== "detail") { s.detail = false; s.scroll = 0 }
        break
    case "move":
        if (s.zone === "detail") break
        s.row = clamp(s.row + n, 0, maxRow); break
    case "top": s.row = 0; break
    case "bottom": s.row = maxRow; break
    case "page": s.row = clamp(s.row + 10 * n, 0, maxRow); break
    case "col": s.col = clamp(s.col + n, 0, maxCol); break
    case "scroll": s.scroll = Math.max(0, s.scroll + n * 80); break
    case "period":
        if (s.sub === "week") s.weekOff = clamp(s.weekOff + n, -(d.weeks ? d.weeks - 1 : 0), 0)
        else if (s.sub === "progress" || s.sub === "report") s.period = (s.period + (n > 0 ? 1 : PERIODS.length - 1)) % PERIODS.length
        else if (s.sub === "zones") s.period = s.period === 1 ? 2 : 1
        else if (s.sub === "agents") { s.period = (Math.min(2, s.period) + (n > 0 ? 1 : 2)) % 3; s.row = 0 }   // today, week, month
        break
    case "primary":
        if (s.sub === "days") { s.detail = !s.detail; s.zone = s.detail ? "detail" : "list"; s.scroll = 0 }
        else if (s.sub === "week" || s.sub === "heatmap") eff = "openDay"
        else if (s.sub === "report") eff = "export"
        else if (s.sub === "agents") eff = "jump"
        break
    case "act.copy": eff = "copy"; break
    case "act.snooze": eff = "snooze"; break
    case "act.done": eff = "done"; break
    case "act.open": eff = "jump"; break
    }
    fixCard(s, d)
    return { st: s, effect: eff }
}

// jump to a day's detail on the Days tab
function openDay(st, doc, day) {
    var rows = dayRows(doc), s = clone(st)
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].day === day) {
            s.sub = "days"; s.row = i; s.col = 0; s.detail = true; s.zone = "detail"; s.scroll = 0
            return s
        }
    }
    return s
}

// five most useful keys of a sub-tab for the footer line: [key, label]
function hints(sub, zone) {
    if (zone === "tabs") return [["h l", "sub-tab"], ["Enter", "into the page"], ["[ ]", "sub-tab"], ["?", "all keys"], ["Esc", "leave"]]
    if (zone === "detail") return [["Up Down", "scroll"], ["h", "back to list"], ["Esc", "back"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    switch (sub) {
    case "week": return [["h l", "day"], ["j k", "zone"], ["J K", "scroll panel"], ["p P", "week"], ["Enter", "day detail"]]
    case "days": return [["j k", "day"], ["Enter", "detail"], ["g G", "ends"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    case "heatmap": return [["h l", "week"], ["j k", "day"], ["J K", "scroll panels"], ["Enter", "day detail"], ["?", "all keys"]]
    case "zones": return [["j k", "zone"], ["p P", "window"], ["g G", "ends"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    case "progress": return [["h j k l", "card"], ["p P", "period"], ["Tab", "sub-tabs"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    case "report": return [["c", "copy"], ["r", "run report"], ["j k", "scroll"], ["Enter", "save file"], ["p P", "period"]]
    case "screen": return [["j k", "scroll"], ["g G", "ends"], ["Tab", "sub-tabs"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    case "reminders": return [["j k", "row"], ["s", "snooze"], ["d", "done"], ["[ ]", "sub-tab"], ["?", "all keys"]]
    case "agents": return [["j k", "row"], ["p P", "period"], ["Enter", "jump to agent"], ["g G", "ends"], ["?", "all keys"]]
    case "today": return [["j k", "scroll"], ["p P", "group"], ["s", "focus"], ["b", "break"], ["Esc", "tabs"]]
    }
    return [["Tab", "sub-tabs"], ["[ ]", "sub-tab"], ["1-5", "pages"], ["?", "all keys"], ["Esc", "leave"]]
}
