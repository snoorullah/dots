// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Parsers and formatters for the system panel. Pure functions, no QML imports, so they
// run under qmltestrunner. Each takes the stdout of one local command (argv, never a
// shell string) and returns plain data, or empty / null when the output cannot be read.
.pragma library

function num(x) { return String(x).trim() === "" ? NaN : Number(x) }

// "/proc/uptime" text -> "up 19h", "up 42m", "up 1d 1h". Unreadable -> "".
function uptime(text) {
    var s = num(String(text || "").trim().split(/\s+/)[0])
    if (!isFinite(s) || s < 0) return ""
    var m = Math.floor(s / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
    if (d > 0) return "up " + d + "d " + (h % 24) + "h"
    if (h > 0) return "up " + h + "h"
    return "up " + m + "m"
}

// nmcli -t escapes ':' as '\:' and '\' as '\\'.
function splitNmcli(line) {
    var out = [], cur = ""
    for (var i = 0; i < line.length; i++) {
        var c = line[i]
        if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
        if (c === ":") { out.push(cur); cur = ""; continue }
        cur += c
    }
    out.push(cur)
    return out
}

function band(freq) {
    var f = parseInt(freq)
    if (!isFinite(f)) return ""
    return f >= 5900 ? "6 GHz" : f >= 4900 ? "5 GHz" : "2.4 GHz"
}

function strength(sig) { return sig >= 60 ? "strong" : sig >= 35 ? "ok" : "weak" }

// `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY,FREQ dev wifi list` -> one entry per SSID
// (strongest wins), connected first, then by signal.
function wifiList(text) {
    var by = {}
    String(text || "").split("\n").forEach(function (ln) {
        if (!ln.trim()) return
        var f = splitNmcli(ln)
        if (f.length < 5 || !f[1]) return
        var sec = f[3].trim()
        var e = { ssid: f[1], signal: parseInt(f[2]) || 0, cur: f[0].trim() === "*",
                  lock: sec !== "" && sec !== "--", sec: sec, freq: f[4] }
        var old = by[e.ssid]
        if (old && !(e.cur || (!old.cur && e.signal > old.signal))) return
        by[e.ssid] = e
    })
    var out = Object.keys(by).map(function (k) {
        var e = by[k]
        e.sub = [band(e.freq), strength(e.signal), e.lock ? e.sec : "open network"]
            .filter(function (x) { return x }).join(", ")
        return e
    })
    out.sort(function (a, b) { return (b.cur ? 1 : 0) - (a.cur ? 1 : 0) || b.signal - a.signal })
    return out
}

var PROFILES = ["power-saver", "balanced", "performance"]
function profile(text) {
    var t = String(text || "").trim()
    return PROFILES.indexOf(t) >= 0 ? t : ""
}

// `wpctl get-volume <node>` -> {v: 0..100, muted} or null.
function mic(text) {
    var m = /^Volume:\s*([0-9.]+)(\s+\[MUTED\])?/.exec(String(text || "").trim())
    if (!m) return null
    return { v: clampPct(parseFloat(m[1])), muted: !!m[2] }
}

// `nmcli -t -f NAME,TYPE,ACTIVE connection show` -> vpn and wireguard profiles only.
function vpnList(text) {
    var out = []
    String(text || "").split("\n").forEach(function (ln) {
        var f = splitNmcli(ln)
        if (f.length < 3 || (f[1] !== "vpn" && f[1] !== "wireguard")) return
        out.push({ name: f[0], cur: f[2] === "yes" })
    })
    return out
}

// `tailscale status --json` -> {on, peers[]} or null.
function tailscale(text) {
    var j
    try { j = JSON.parse(text) } catch (e) { return null }
    if (!j || typeof j !== "object") return null
    var peers = []
    var P = j.Peer || {}
    Object.keys(P).forEach(function (k) {
        var p = P[k]
        var online = !!p.Online
        var sub = !online ? "offline" : (p.CurAddr ? "online, direct" : "online, relayed")
        peers.push({ name: String(p.HostName || ""), sub: sub, cur: online,
                     ip: (p.TailscaleIPs && p.TailscaleIPs[0]) || "" })
    })
    peers.sort(function (a, b) { return (b.cur ? 1 : 0) - (a.cur ? 1 : 0) })
    return { on: j.BackendState === "Running", peers: peers }
}

// `nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total
//  --format=csv,noheader,nounits` -> {temp, busy, vramPct, vramLabel} or null.
function gpu(text) {
    var f = String(text || "").trim().split(/\s*,\s*/).map(Number)
    if (f.length < 4 || f.some(function (x) { return !isFinite(x) })) return null
    var usedGb = f[2] / 1024, totalGb = f[3] / 1024
    return { temp: f[0], busy: f[1], vramPct: Math.round(100 * f[2] / f[3]),
             vramLabel: (Math.round(usedGb * 10) / 10) + " of " + Math.round(totalGb) + " GB" }
}

function clampPct(x) { return Math.max(0, Math.min(100, Math.round(100 * (Number(x) || 0)))) }

// Night-light warmth slider: 0 = 6500 K (neutral) .. 100 = 2500 K (warmest).
function warmthToKelvin(v) { return Math.round(6500 - 4000 * Math.max(0, Math.min(100, v)) / 100) }
function kelvinToWarmth(k) { return Math.max(0, Math.min(100, Math.round((6500 - k) / 40))) }

// `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device` -> the wired link, or null.
function wired(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var f = splitNmcli(lines[i])
        if (f.length >= 3 && f[1] === "ethernet" && f[2] === "connected") return { name: "Ethernet", sub: "connected" }
    }
    return null
}
