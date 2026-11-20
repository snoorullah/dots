.pragma library
// Bar logic with no QML in it: ages, ordering, overflow, salah runway, workspace apps,
// faults, metrics. Bar.qml feeds it plain data; BarView draws what it returns.

function num(v) { var n = Number(v); return isFinite(n) ? n : 0 }

// 45 -> "now", 720 -> "12m", 7200 -> "2h", 200000 -> "2d"
function age(sec) {
  var s = Math.max(0, num(sec))
  if (s < 60) return "now"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  return Math.floor(s / 86400) + "d"
}

// what each kind of waiting thing looks like. tone is a status tone, never a colour.
var kinds = {
  agent:   { icon: "sparkle", tone: "waiting", name: "Agent waits on you", popout: "agent" },
  vip:     { icon: "star", tone: "waiting", name: "VIP message", popout: "waiting" },
  alert:   { icon: "warning", tone: "failed", name: "New alert", popout: "waiting" },
  review:  { icon: "git-pull-request", tone: "waiting", name: "Review requested", popout: "waiting" },
  mail:    { icon: "envelope", tone: "waiting", name: "VIP mail", popout: "waiting" },
  ticket:  { icon: "ticket", tone: "waiting", name: "Ticket due today", popout: "waiting" },
  blocker: { icon: "ticket", tone: "waiting", name: "Blocked on you", popout: "waiting" }
}

// Oldest first, at most `max` shown, the rest as `more`.
function waitSymbols(items, max) {
  var list = []
  var src = items || []
  for (var i = 0; i < src.length; i++) {
    var it = src[i]
    if (!it) continue
    var k = kinds[it.kind] || { icon: "circle", tone: "waiting", name: it.title || "Waiting on you", popout: "waiting" }
    list.push({ id: String(it.id), kind: it.kind || "", icon: k.icon, tone: k.tone, name: k.name,
                popout: k.popout, ageSec: num(it.ageSec), age: age(it.ageSec), order: i })
  }
  list.sort(function (a, b) { return (b.ageSec - a.ageSec) || (a.order - b.order) })
  var cap = max > 0 ? max : 3
  return { shown: list.slice(0, cap), more: Math.max(0, list.length - cap) }
}

// "<zero-width>→ Isha 22:52" at 22:28 -> "Isha 24m". No clock time in it: shown cleaned.
function salahLabel(text, now) {
  var t = String(text === undefined || text === null ? "" : text).replace(/[​-‏⁠﻿]/g, "")
    .replace(/[→←➜>]+/g, " ").replace(/\s+/g, " ").trim()
  if (t === "" || t === "—" || t === "-") return ""
  var m = /([^\d\s][^\d]*?)\s+(\d{1,2}):(\d{2})\b/.exec(t)
  if (!m) return t
  var d = now || new Date()
  var mins = (+m[2]) * 60 + (+m[3]) - (d.getHours() * 60 + d.getMinutes())
  if (mins < 0) mins += 1440
  var name = m[1].trim()
  if (mins === 0) return name + " now"
  if (mins < 60) return name + " " + mins + "m"
  var mm = mins % 60
  return name + " " + Math.floor(mins / 60) + "h" + (mm ? " " + (mm < 10 ? "0" : "") + mm + "m" : "")
}

// workspaces: [{id,name}], toplevels: [{wsId, cls, icon}] -> one entry per workspace with
// its distinct apps (first `maxApps`, the rest counted in `more`)
function workspaces(ws, toplevels, activeId, maxApps) {
  var out = []
  var cap = maxApps > 0 ? maxApps : 3
  var w = ws || []
  for (var i = 0; i < w.length; i++) {
    var seen = {}, apps = []
    var tl = toplevels || []
    for (var j = 0; j < tl.length; j++) {
      if (!tl[j] || tl[j].wsId !== w[i].id) continue
      var c = String(tl[j].cls || "")
      if (c === "" || seen[c]) continue
      seen[c] = true
      apps.push({ cls: c, icon: tl[j].icon || "" })
    }
    out.push({ id: w[i].id, name: String(w[i].name), active: w[i].id === activeId,
               apps: apps.slice(0, cap), more: Math.max(0, apps.length - cap) })
  }
  return out
}

// ops: {level, text, stale}. A failure outranks a stale source; warn is a wait, not a fault.
function fault(ops, degraded) {
  var o = ops || {}
  if (o.level === "fail") return { kind: "failed", text: String(o.text || "failed") }
  if (o.stale || degraded) return { kind: "unknown", text: "data stale" }
  return { kind: "none", text: "" }
}

function hm(sec) {
  var m = Math.floor(Math.max(0, num(sec)) / 60), h = Math.floor(m / 60)
  if (h <= 0) return m + "m"
  return h + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
}

// today's numbers: only the ones with a real value are listed
function metrics(v) {
  var o = v || {}, out = []
  function has(x) { return x !== undefined && x !== null }
  if (has(o.prs)) out.push({ key: "prs", icon: "git-pull-request", text: String(o.prs), title: "PRs merged today", accent: false })
  if (has(o.tasks)) out.push({ key: "tasks", icon: "check-circle", text: String(o.tasks), title: "Tickets closed today", accent: false })
  if (has(o.workedSec)) out.push({ key: "worked", icon: "timer", text: hm(o.workedSec), title: "Worked today", accent: false })
  if (has(o.xp)) out.push({ key: "xp", icon: "", text: "+" + o.xp, title: "XP today", accent: true })
  return out
}

// "Logout 03:12" (the Bar board): time left until today reaches its worked-hours target, so a
// break pushes it later. Past the target it counts up with a "+". "" when there is no figure.
var DAY_TARGET_SEC = 8 * 3600
function logoutLeft(workedSec, targetSec) {
  if (workedSec === undefined || workedSec === null) return ""
  var t = targetSec > 0 ? targetSec : DAY_TARGET_SEC
  var d = t - num(workedSec), over = d < 0
  var m = Math.floor(Math.abs(d) / 60)
  var h = Math.floor(m / 60), mm = m % 60
  return (over ? "+" : "") + (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm
}

// a running focus block -> "24:27" left (mm:ss, a countdown stopwatch; h:mm:ss past an hour).
// "" when no block runs or its time is up.
function focusLeft(focus, nowSec) {
  if (!focus || focus.state !== "running") return ""
  var target = num(focus.targetSec), start = num(focus.startedAt)
  if (target <= 0 || start <= 0) return ""
  var left = Math.ceil(target - (num(nowSec) - start))
  if (left <= 0) return ""
  var h = Math.floor(left / 3600), m = Math.floor(left % 3600 / 60), sec = left % 60
  function p2(x) { return (x < 10 ? "0" : "") + x }
  return (h > 0 ? h + ":" + p2(m) : p2(m)) + ":" + p2(sec)
}

// Owner rule: the bar's waiting symbols carry only today's GitHub items (reviews, PRs). "Today"
// is the session: anything older than this login stays in the control centre, off the bar.
function todaysOnly(items, nowSec, loginTs) {
  var since = num(loginTs) > 0 ? num(nowSec) - num(loginTs) : 24 * 3600
  return (items || []).filter(function (i) {
    if (!i || i.src !== "gh") return true
    return num(i.ageSec) <= since
  })
}

function taskText(task) {
  if (!task) return ""
  var ref = task.ref ? String(task.ref) : "", d = task.desc ? String(task.desc) : ""
  return (ref && d) ? ref + " " + d : (ref || d)
}

// the profile whose name the focused workspace carries, else none (no source yet)
function activeProfile(profiles, wsName) {
  var n = String(wsName || "").toLowerCase()
  if (n === "") return ""
  for (var i = 0; i < profiles.length; i++)
    if (profiles[i].toLowerCase() === n) return profiles[i]
  return ""
}
