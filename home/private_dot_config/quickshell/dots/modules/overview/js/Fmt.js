// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
// Fresh implementation, inspired by tally-screentime (MIT).
//
// Duration and label formatting for the overview surfaces. The shape of this
// module (small pure functions, no QML imports, tested under qmltestrunner)
// follows tally-screentime; none of its source is copied.
.pragma library

function pad2(n) { return (n < 10 ? "0" : "") + n }

// 1500 -> "25:00". Negative and non-finite input is clamped to 0.
function mmss(sec) {
    var s = Math.max(0, Math.floor(Number(sec) || 0))
    return pad2(Math.floor(s / 60)) + ":" + pad2(s % 60)
}

// 7500 -> "2h 05m", 2700 -> "45m", 0 -> "0m". Seconds are dropped, never rounded up.
function hm(sec) {
    var m = Math.floor(Math.max(0, Number(sec) || 0) / 60)
    var h = Math.floor(m / 60)
    if (h <= 0) return m + "m"
    return h + "h " + pad2(m % 60) + "m"
}

// Whole-number percent of total; 0 when total is 0.
function pct(part, total) {
    if (!(total > 0)) return 0
    return Math.round(100 * part / total)
}

// 45 -> "now", 300 -> "5m", 7200 -> "2h", 200000 -> "2d"
function age(sec) {
    var s = Math.max(0, Number(sec) || 0)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
}

// "2026-10-27" -> "Tue 27 Oct". Parsed as UTC parts so a time zone cannot shift the day.
function dayLabel(key) {
    var p = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key))
    if (!p) return String(key)
    var d = new Date(Date.UTC(+p[1], +p[2] - 1, +p[3]))
    var wd = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()]
    var mo = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()]
    return wd + " " + (+p[3]) + " " + mo
}

// Count badge text: 0 -> "", 7 -> "7", 120 -> "99+"
function badge(n) {
    n = Math.floor(Number(n) || 0)
    if (n <= 0) return ""
    return n > 99 ? "99+" : String(n)
}

// Single line, trimmed to max chars with an ellipsis.
function clip(text, max) {
    var t = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
    if (t.length <= max) return t
    return t.substring(0, Math.max(0, max - 1)) + "…"
}
