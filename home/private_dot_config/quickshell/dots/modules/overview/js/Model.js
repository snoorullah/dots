// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
// Fresh implementation, inspired by tally-screentime (MIT).
//
// View-model rules for the overview: validation, staleness, urgency order, what
// the pill shows, onset coalescing, focus arithmetic. Pure functions with no QML
// imports, so qmltestrunner covers them without a compositor.
.pragma library

var SPEC_V = 1
var STALE_SEC = 180            // a file older than this is a dead writer, not a quiet one
var ONSET_GAP_MS = 10 * 60000  // at most one onset per 10 minutes in steady state

// Parses one state file. status:
//   missing  no file or empty       -> treated as "no data", renders nothing
//   bad      not JSON / not object  -> hollow ?
//   version  v != 1                 -> hollow ?
//   stale    ts older than 180 s    -> hollow ?
//   ok
// doc is returned for ok and stale (stale numbers are shown dimmed), else null.
function parseDoc(text, nowSec) {
    if (text === null || text === undefined || String(text).trim() === "")
        return { status: "missing", doc: null, ageSec: 0 }
    var doc
    try { doc = JSON.parse(text) } catch (e) { return { status: "bad", doc: null, ageSec: 0 } }
    if (!doc || typeof doc !== "object" || Array.isArray(doc))
        return { status: "bad", doc: null, ageSec: 0 }
    if (doc.v !== SPEC_V) return { status: "version", doc: null, ageSec: 0, v: doc.v }
    var ts = Number(doc.ts)
    var age = isFinite(ts) && ts > 0 ? Math.max(0, nowSec - ts) : 0
    if (!(ts > 0) || age > STALE_SEC) return { status: "stale", doc: doc, ageSec: age }
    return { status: "ok", doc: doc, ageSec: age }
}

// "Needs the hollow ?" for a parse status.
function isDegraded(status) {
    return status === "bad" || status === "version" || status === "stale"
}

// ---- urgency --------------------------------------------------------------

var RANK = { critical: 3, time: 2, active: 1, passive: 0 }

function urgencyRank(u) { return RANK.hasOwnProperty(u) ? RANK[u] : 0 }

// Most urgent first; someone waiting beats not waiting at the same rung; then
// the longest wait. Never mutates the input.
function sortItems(items) {
    return (items || []).slice().sort(function (a, b) {
        var r = urgencyRank(b.urgency) - urgencyRank(a.urgency)
        if (r) return r
        var w = (b.waiting ? 1 : 0) - (a.waiting ? 1 : 0)
        if (w) return w
        return (+b.ageSec || 0) - (+a.ageSec || 0)
    })
}

// "Next up" is work I picked (kind task); the attention list is everything
// else. Mail never reaches the UI: the source is unavailable by decision.
function splitItems(items) {
    var all = sortItems((items || []).filter(function (i) { return i && i.kind !== "mail" }))
    return {
        next: all.filter(function (i) { return i.kind === "task" }),
        attention: all.filter(function (i) { return i.kind !== "task" })
    }
}

// waiting: someone waits on me (amber). failed: an alert nobody waits on (red).
function counts(att) {
    var items = (att && att.items) || []
    var w = 0, f = 0
    for (var i = 0; i < items.length; i++) {
        if (items[i].kind === "mail") continue
        if (items[i].waiting) w++
        else if (items[i].kind === "alert") f++
    }
    return { waiting: w, failed: f, total: w + f }
}

// ---- pill -----------------------------------------------------------------

// Priority: focus running > failed (red) > waiting (amber) > stale ? > nothing.
// kind "none" means width 0.
function pillState(focus, cnt, degraded) {
    if (focus && focus.state === "running") return { kind: "focus", waiting: cnt.waiting, failed: cnt.failed }
    if (cnt.failed > 0) return { kind: "failed", waiting: cnt.waiting, failed: cnt.failed }
    if (cnt.waiting > 0) return { kind: "waiting", waiting: cnt.waiting, failed: cnt.failed }
    if (degraded) return { kind: "stale", waiting: 0, failed: 0 }
    return { kind: "none", waiting: 0, failed: 0 }
}

// Onset coalescing. Returns { fire, last }: fire = animate the entry; last = the
// timestamp to store. A badge that appears inside the gap still appears, just
// without the entry animation, so the user is never told less, only moved less.
function onset(lastMs, nowMs, gapMs) {
    var gap = gapMs === undefined ? ONSET_GAP_MS : gapMs
    if (!(lastMs > 0) || nowMs - lastMs >= gap) return { fire: true, last: nowMs }
    return { fire: false, last: lastMs }
}

// ---- focus ----------------------------------------------------------------

// startedAt / endsAt arrive as epoch seconds or an ISO string.
function toEpoch(v) {
    if (v === null || v === undefined || v === "") return 0
    if (typeof v === "number") return v > 1e11 ? Math.floor(v / 1000) : v
    var t = Date.parse(String(v))
    return isFinite(t) ? Math.floor(t / 1000) : 0
}

// Elapsed seconds clamped to [0, target]. While running it is derived from
// startedAt so the 1 s ring timer needs no new file; otherwise the stored value.
function focusElapsed(focus, nowSec) {
    if (!focus) return 0
    var target = Math.max(0, +focus.targetSec || 0)
    var el = +focus.elapsedSec || 0
    if (focus.state === "running") {
        var s = toEpoch(focus.startedAt)
        if (s > 0) el = nowSec - s
    }
    return Math.max(0, Math.min(target > 0 ? target : el, el))
}

// Degrees of arc from 12 o'clock, clockwise. 0 when there is no target.
function ringAngle(elapsedSec, targetSec) {
    if (!(targetSec > 0)) return 0
    return 360 * Math.max(0, Math.min(1, elapsedSec / targetSec))
}
