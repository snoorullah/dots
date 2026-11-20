// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The calendar popup's model: clock header, the NEXT strip, today's timeline (events,
// prayers, the now marker, free gaps), the week strip and the month grid. Events come from
// the optional calendar.json (v1), prayers from barpop/js/Salah.js. Nothing is written
// anywhere. Pure functions, no QML imports.
.pragma library
.import "../../barpop/js/Salah.js" as Salah

var DOW = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
var DOW3 = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var STALE_SEC = 1800
var SOON_MIN = 10

function pad2(n) { return (n < 10 ? "0" : "") + n }
function isoDay(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }

function validDoc(doc) { return !!doc && typeof doc === "object" && doc.v === 1 && Array.isArray(doc.events) }

// events of one ISO day with valid times, sorted by start
function dayEvents(doc, day) {
    if (!validDoc(doc)) return []
    return doc.events.filter(function (e) {
        return e && e.date === day && Salah.toMin(e.start) >= 0 && Salah.toMin(e.end) >= 0
    }).map(function (e) {
        return { id: String(e.id), title: String(e.title || "Untitled"), s: Salah.toMin(e.start), e: Salah.toMin(e.end),
                 link: !!e.link, worked: !!e.worked, held: !!e.held }
    }).sort(function (a, b) { return a.s - b.s })
}

function countOn(doc, day) {
    if (!validDoc(doc)) return 0
    return doc.events.filter(function (e) { return e && e.date === day }).length
}

function weekStart(now) {
    var d = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7))
    return d
}

function monthGrid(doc, now, shown, stale) {
    var y = shown.getFullYear(), mo = shown.getMonth()
    var lead = (new Date(y, mo, 1).getDay() + 6) % 7
    var today = isoDay(now), out = []
    for (var i = 0; i < 42; i++) {
        var d = new Date(y, mo, 1 - lead + i)
        var iso = isoDay(d)
        out.push({ n: d.getDate(), inMonth: d.getMonth() === mo, today: iso === today,
                   dots: Math.min(2, countOn(doc, iso)), hollow: !!stale })
    }
    return out
}

// parsedSalah: Salah.parseConf output or null; now: Date;
// opts: { openId, month: Date }
function build(doc, parsedSalah, now, opts) {
    opts = opts || {}
    var nowMin = now.getHours() * 60 + now.getMinutes()
    var day = isoDay(now)
    var hasDoc = validDoc(doc)
    var stale = hasDoc && (now.getTime() / 1000 - (Number(doc.ts) || 0)) > STALE_SEC
    var sal = Salah.build(parsedSalah, now)
    var evs = dayEvents(doc, day)
    var staleTime = hasDoc && doc.ts ? Salah.hm(new Date(doc.ts * 1000).getHours() * 60 + new Date(doc.ts * 1000).getMinutes()) : ""

    // ---- timeline -------------------------------------------------------
    var winEnd = sal.ok && sal.cur >= 0 ? Salah.windowEnd(parsedSalah.rows[sal.cur]) : -1
    var nextEv = null, curEv = null
    evs.forEach(function (e) {
        if (!nextEv && e.s > nowMin && !e.held) nextEv = e
        if (!curEv && nowMin >= e.s && nowMin < e.e && !e.held) curEv = e
    })
    var entries = []        // { at, end, row }; end is -1 for rows that take no time
    evs.forEach(function (e) {
        var dim = winEnd >= 0 && e.e > nowMin
        var active = nowMin >= e.s && nowMin < e.e
        var row
        if (e.held) {
            row = { k: "held", t: Salah.hm(e.s), range: Salah.hm(e.s) + " to " + Salah.hm(e.e), dim: dim, active: active,
                    prog: active ? Math.round(100 * (nowMin - e.s) / Math.max(1, e.e - e.s)) : 0 }
        } else {
            row = { k: "ev", id: e.id, t: Salah.hm(e.s), title: e.title, dur: Salah.dur(e.e - e.s),
                    past: nowMin >= e.e, active: active, next: !!nextEv && nextEv.id === e.id, link: e.link && !stale, tick: e.worked && !stale,
                    dim: dim, unk: stale, open: opts.openId === e.id,
                    prog: active ? Math.round(100 * (nowMin - e.s) / Math.max(1, e.e - e.s)) : 0,
                    d1: Salah.hm(e.s) + " to " + Salah.hm(e.e) + (e.link ? " · join link ready" : ""),
                    d2: stale ? "Last synced " + staleTime + ". Unknown, not confirmed." : (e.worked ? "Counts as worked time (advisory)" : "") }
        }
        entries.push({ at: e.s, end: e.e, row: row })
    })
    if (sal.ok) sal.rows.forEach(function (r, i) {
        if (r.past) return                       // prayers that are over leave the timeline
        var cur = sal.cur === i
        var note = ""
        if (cur) note = "window open · ends " + Salah.hm(winEnd)
        else if (sal.hero.label === "NEXT" && sal.next === i && !sal.stale) note = "in " + Salah.dur(parsedSalah.rows[i].adhan - nowMin)
        entries.push({ at: parsedSalah.rows[i].adhan, end: -1, row: { k: "pr", t: r.time, name: r.name, note: note, cur: cur, unv: sal.stale } })
    })
    entries.push({ at: nowMin + 0.5, end: -1, row: { k: "now", t: Salah.hm(nowMin) } })
    entries.sort(function (a, b) { return a.at - b.at })

    var rows = []
    entries.forEach(function (x, i) {
        rows.push(x.row)
        if (x.end < 0) return
        for (var j = i + 1; j < entries.length; j++) {
            if (entries[j].row.k === "now") continue
            var gap = entries[j].at - x.end
            if (gap >= 30 && entries[j].row.k !== "free") rows.push({ k: "free", t: "", title: Salah.dur(gap) + " free" })
            break
        }
    })
    if (evs.length === 0) {
        var ni = 0
        for (var q = 0; q < rows.length; q++) if (rows[q].k === "now") { ni = q + 1; break }
        rows.splice(ni, 0, { k: "empty", t: "", title: "Nothing scheduled", sub: "Only the prayers are on the timeline." })
    }

    // ---- strip ----------------------------------------------------------
    var strip = null
    var prayerWin = sal.ok && sal.cur >= 0
    var toPrayer = sal.ok && sal.cur < 0 && sal.hero.label === "NEXT" ? parsedSalah.rows[sal.next].adhan - nowMin : -1
    if (prayerWin) {
        strip = { tone: "prayer", icon: "mosque", label: "NEXT · SALAH", title: sal.rows[sal.cur].name + " window open",
                  sub: "until " + Salah.hm(winEnd) + (nextEv ? " · " + nextEv.title + " waits" : ""), btn: "", kind: "none" }
    } else if (curEv) {
        strip = { tone: "meeting", icon: "video", label: "NOW · IN MEETING", title: "In meeting, " + Salah.dur(curEv.e - nowMin) + " left",
                  sub: curEv.title + (curEv.worked ? " · counts as worked" : ""), btn: "", kind: "none" }
    } else if (nextEv && (toPrayer < 0 || nextEv.s - nowMin <= toPrayer)) {
        var soon = nextEv.s - nowMin <= SOON_MIN
        strip = { tone: soon ? "amber" : "info", icon: soon ? "clock" : "video", label: soon ? "NEXT · SOON" : "NEXT · MEETING",
                  title: nextEv.title + " in " + Salah.dur(nextEv.s - nowMin),
                  sub: Salah.hm(nextEv.s) + " · " + Salah.dur(nextEv.e - nextEv.s) + (nextEv.link ? " · link ready" : ""),
                  btn: nextEv.link ? "Join" : "", kind: soon ? "amber" : "ghost" }
    } else if (toPrayer >= 0) {
        var nm = sal.rows[sal.next].name
        strip = { tone: "prayer", icon: "mosque", label: "NEXT · SALAH", title: nm + " in " + Salah.dur(toPrayer),
                  sub: Salah.hm(parsedSalah.rows[sal.next].adhan) + (sal.stale ? " · prayer times unverified" : " · prayer times verified") + (evs.length === 0 ? " · nothing scheduled today" : ""),
                  btn: "", kind: "none" }
    } else {
        strip = { tone: "empty", icon: "calendar-blank", label: "NEXT", title: "Nothing coming up", sub: "no events, no prayer times", btn: "", kind: "none" }
    }
    if (evs.length === 0 && strip.tone === "prayer" && !prayerWin) strip.tone = "empty"

    // ---- banner, footer -------------------------------------------------
    var banner = null
    if (stale) banner = { kind: "unknown", text: "Events may be missing or old. Check your calendar yourself." }
    else if (sal.ok && sal.stale) banner = { kind: "unknown", text: "Prayer times unverified, check the time yourself. File is from " + (parsedSalah.date || "an earlier day") + "." }
    var foot = !hasDoc ? { t: "no calendar source", stale: true } : (stale ? { t: "stale " + staleTime, stale: true } : { t: "synced " + staleTime, stale: false })

    // ---- week, month ----------------------------------------------------
    var ws = weekStart(now)
    var week = []
    for (var i = 0; i < 7; i++) {
        var d = new Date(ws.getFullYear(), ws.getMonth(), ws.getDate() + i)
        var iso = isoDay(d)
        week.push({ dow: DOW[i], n: d.getDate(), today: iso === day, dots: Math.min(3, countOn(doc, iso)), hollow: !!stale })
    }
    var shown = opts.month || now
    return {
        time: Salah.hm(nowMin), dateLine: DOW3[now.getDay()] + " " + now.getDate() + " " + MON[now.getMonth()],
        today: !stale, stale: stale, strip: strip, banner: banner, rows: rows, week: week, foot: foot,
        month: monthGrid(doc, now, shown, stale), monthLabel: MONTHS[shown.getMonth()] + " " + shown.getFullYear(),
        weekLabel: "WEEK · DOTS BUSY"
    }
}
