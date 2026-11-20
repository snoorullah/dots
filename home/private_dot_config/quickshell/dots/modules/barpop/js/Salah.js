// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The salah popup's model: parse ~/.config/adhd/prayer-times.conf (written by
// adhd-prayer-times.sh) and work out the hero, the rows and the window state for a
// given moment. Pure functions, no QML imports.
.pragma library

var NAMES = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

function pad2(n) { return (n < 10 ? "0" : "") + n }

// "05:32" -> 332, anything else -> -1
function toMin(s) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(s))
    if (!m) return -1
    var h = +m[1], mi = +m[2]
    return (h > 23 || mi > 59) ? -1 : h * 60 + mi
}

function hm(min) {
    var m = ((Math.round(min) % 1440) + 1440) % 1440
    return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60)
}

// 164 -> "2h 44m", 45 -> "45m", 60 -> "1h 00m"
function dur(min) {
    var m = Math.max(0, Math.round(Number(min) || 0))
    return m >= 60 ? Math.floor(m / 60) + "h " + pad2(m % 60) + "m" : m + "m"
}

// Lines look like `Fajr 05:32    # adhan 05:12 · adhan+20m · ends 06:31`. The listed time is
// the iqamah; the comment carries the calculated adhan and the end of the window.
function parseConf(text) {
    var out = { date: "", rows: [] }
    var lines = String(text === null || text === undefined ? "" : text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var ln = lines[i].trim()
        var h = /^#\s*auto-generated\s+(\d{4}-\d{2}-\d{2})/.exec(ln)
        if (h) { out.date = h[1]; continue }
        var m = /^(Fajr|Dhuhr|Asr|Maghrib|Isha)\s+(\d{1,2}:\d{2})(?:\s*#\s*(.*))?$/.exec(ln)
        if (!m) continue
        var iq = toMin(m[2])
        if (iq < 0) continue
        var cm = m[3] || ""
        var a = /\badhan\s+(\d{1,2}:\d{2})/.exec(cm)
        var e = /\bends\s+(\d{1,2}:\d{2})/.exec(cm)
        var adhan = a && toMin(a[1]) >= 0 ? toMin(a[1]) : iq
        var ends = e && toMin(e[1]) >= 0 ? toMin(e[1]) : -1
        if (ends >= 0 && ends <= adhan) ends += 1440      // Isha ends at tomorrow's Fajr
        out.rows.push({ name: m[1], adhan: adhan, iqamah: iq, ends: ends })
    }
    // a window without an end runs to the next adhan, or 90 minutes
    for (var j = 0; j < out.rows.length; j++) {
        var r = out.rows[j]
        if (r.ends < 0) r.ends = j + 1 < out.rows.length ? out.rows[j + 1].adhan : r.adhan + 90
    }
    return out
}

function windowEnd(r) { return Math.max(r.iqamah, r.adhan) + 15 }

function isoDay(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }

// parsed: parseConf output; now: Date.
// -> { ok, stale, jumuah, cur, next, rows[], hero{}, sunrise }
function build(parsed, now) {
    var rows = (parsed && parsed.rows) ? parsed.rows : []
    var res = { ok: rows.length > 0, stale: false, jumuah: false, cur: -1, next: -1, rows: [], sunrise: "",
                hero: { label: "", name: "", cd: "", pct: 0, soon: false, stale: false } }
    if (!res.ok) return res
    var nowMin = now.getHours() * 60 + now.getMinutes()
    res.stale = !!parsed.date && parsed.date !== isoDay(now)
    res.jumuah = now.getDay() === 5

    // NOW = from the adhan until fifteen minutes after the iqamah: the time it is actually prayed
    var cur = -1
    for (var i = 0; i < rows.length; i++)
        if (nowMin >= rows[i].adhan && nowMin < windowEnd(rows[i])) { cur = i; break }
    var next = -1
    for (var k = 0; k < rows.length; k++) if (rows[k].adhan > nowMin) { next = k; break }
    var tomorrow = next < 0
    if (tomorrow) next = 0
    res.cur = cur
    res.next = next

    function nm(i) { return res.jumuah && rows[i].name === "Dhuhr" ? "Jumuah" : rows[i].name }
    var focus = cur >= 0 ? cur : next
    for (var j = 0; j < rows.length; j++) {
        var past = tomorrow || j < focus
        res.rows.push({ name: nm(j), time: hm(rows[j].adhan), iq: rows[j].iqamah > rows[j].adhan ? "+" + (rows[j].iqamah - rows[j].adhan) : "",
                        past: past && j !== focus, focus: j === focus })
    }
    res.sunrise = hm(rows[0].ends)

    var h = res.hero
    h.stale = res.stale
    if (cur >= 0) {
        var we = windowEnd(rows[cur])
        h.label = "NOW"
        h.name = "Now: " + nm(cur)
        h.cd = "ends in " + dur(we - nowMin)
        h.pct = (nowMin - rows[cur].adhan) / Math.max(1, we - rows[cur].adhan)
    } else if (tomorrow) {
        var toNext = 1440 - nowMin + rows[0].adhan
        h.label = "TOMORROW"
        h.name = nm(0) + " " + hm(rows[0].adhan)
        h.cd = res.stale ? "cached" : "in " + dur(toNext)
        h.pct = Math.max(0, (nowMin - rows[rows.length - 1].adhan) / Math.max(1, 1440 - rows[rows.length - 1].adhan + rows[0].adhan))
    } else {
        var d = rows[next].adhan - nowMin
        var prev = next > 0 ? rows[next - 1].adhan : 0
        h.label = "NEXT"
        h.name = nm(next) + " " + hm(rows[next].adhan)
        h.soon = !res.stale && d <= 15
        h.cd = res.stale ? "cached" : (h.soon ? dur(d) : "in " + dur(d))
        h.pct = (nowMin - prev) / Math.max(1, rows[next].adhan - prev)
    }
    h.pct = Math.max(0, Math.min(1, h.pct))
    return res
}
