// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The system panel's data model. `st` is a plain object assembled from the services
// (see SystemPanel.qml); every function here is pure. QML draws what these return and
// emits the `act` of whatever was clicked. An act is one of
//   {op:"argv", argv:[...]}   run a local command, argv only, never a shell string
//   {op:"off", why:"..."}     no local backend: the control renders disabled
//   {op:<name>, ...}          a service setter that SystemPanel owns (wifi, bt, dnd, ...)
// Icons are returned as KEYS; SysIcons.qml maps a key to a Phosphor name.
.pragma library
.import "Parse.js" as Parse

var NOT_WIRED = "not wired yet"
var READ_ONLY = "read-only for now"

function argv() { return { op: "argv", argv: Array.prototype.slice.call(arguments) } }
function off(why) { return { op: "off", why: why || NOT_WIRED } }
function op(name, extra) {
    var a = { op: name }
    for (var k in (extra || {})) a[k] = extra[k]
    return a
}
function disabled(act) { return !act || act.op === "off" }

// ---- state defaults -------------------------------------------------------------------
function dflt(st) {
    st = st || {}
    var g = function (k, d) { return st[k] || d }
    return {
        host: st.host || "", uptime: st.uptime || "",
        bright: g("bright", { avail: false, v: 0 }),
        vol: g("vol", { avail: false, v: 0, muted: false, out: "" }),
        mic: g("mic", { avail: false, v: 0, muted: false, inputs: [], using: [], ptt: "Off", denoise: false }),
        wifi: g("wifi", { avail: false, on: false, ssid: "", nets: [], wired: null }),
        bt: g("bt", { avail: false, on: false, connected: [], paired: [] }),
        quiet: g("quiet", { avail: false, on: false, mode: "Off", held: 0 }),
        vpn: g("vpn", { conns: [] }),
        ts: g("ts", { installed: false, on: false, peers: [], exit: "None" }),
        night: g("night", { avail: false, on: false, kelvin: 4000, until: "" }),
        awake: g("awake", { on: false, command: "" }),
        perf: g("perf", { profile: "", gpu: null, models: [] }),
        theme: g("theme", { source: "preset", swatches: [] }),
        screens: g("screens", []),
        media: st.media || null,
        notifs: g("notifs", []),
        session: g("session", { blocker: "", logoutNote: "Ends your day" })
    }
}

// ---- row constructors -----------------------------------------------------------------
function head(t) { return { k: "head", t: t } }
function toggle(t, sub, on, act) { return { k: "toggle", t: t, sub: sub || "", on: !!on, act: act || off() } }
function item(t, sub, o) {
    o = o || {}
    return { k: "item", t: t, sub: sub || "", kind: o.kind || "", cur: !!o.cur, lock: !!o.lock, act: o.act || off(),
             right: o.right || "", rightAct: o.rightAct || (o.right ? off() : null) }
}
function choice(t, opts, sel, mk) {
    return { k: "choice", t: t, opts: opts.map(function (name) {
        var a = mk ? mk(name) : off()
        return { t: name, on: name === sel, act: a || off() }
    }) }
}
function slider(t, v, right, act) { return { k: "slider", t: t, v: v, right: right || (v + "%"), act: act || off() } }
function actions(list) { return { k: "actions", btns: list.map(function (b) { return { t: b[0], act: b[1] || off() } }) } }
function note(t) { return { k: "note", t: t } }

// ---- tiles ----------------------------------------------------------------------------
var ORDER = ["wifi", "bt", "quiet", "vpn", "ts", "mic", "night", "awake", "perf", "theme"]
var EXTRA = ["sound", "display"]

function vpnActive(s) { return s.vpn.conns.filter(function (c) { return c.cur }) }

function tiles(st) {
    var s = dflt(st)
    var peers = s.ts.peers.filter(function (p) { return p.cur }).length
    var ac = vpnActive(s)
    var btn = s.bt.connected.length
    var theme = s.theme.source === "wallpaper"
    return [
        { id: "wifi", name: "Wi-Fi", icon: s.wifi.on ? "wifi" : "wifiOff", on: s.wifi.on, avail: s.wifi.avail,
          sub: !s.wifi.avail ? "unavailable" : !s.wifi.on ? "off" : (s.wifi.ssid || "not connected") },
        { id: "bt", name: "Bluetooth", icon: s.bt.on ? "bt" : "btOff", on: s.bt.on, avail: s.bt.avail,
          sub: !s.bt.avail ? "unavailable" : !s.bt.on ? "off" : (btn > 0 ? btn + " connected" : "on") },
        { id: "quiet", name: "Quiet", icon: "quiet", on: s.quiet.on, avail: s.quiet.avail,
          sub: s.quiet.on ? "VIPs still reach you" : "off" },
        { id: "vpn", name: "VPN", icon: "vpn", on: ac.length > 0, avail: true,
          sub: ac.length > 0 ? ac[0].name : "off" },
        { id: "ts", name: "Tailscale", icon: "ts", on: s.ts.on, avail: s.ts.installed,
          sub: !s.ts.installed ? "not installed" : !s.ts.on ? "off" : peers + (peers === 1 ? " peer" : " peers") },
        { id: "mic", name: "Mic mute", icon: s.mic.muted ? "micOff" : "mic", on: s.mic.muted, avail: s.mic.avail,
          sub: s.mic.muted ? "muted" : "" },
        { id: "night", name: "Night light", icon: "night", on: s.night.on, avail: s.night.avail,
          sub: s.night.on ? (s.night.until ? "until " + s.night.until : s.night.kelvin + " K") : "" },
        { id: "awake", name: "Stay awake", icon: "awake", on: s.awake.on, avail: true, sub: s.awake.on ? "on" : "" },
        { id: "perf", name: "Performance", icon: "perf", on: s.perf.profile === "performance", avail: s.perf.profile !== "",
          sub: s.perf.profile ? s.perf.profile : "unknown" },
        { id: "theme", name: "Theme", icon: "theme", on: false, avail: true,
          sub: theme ? "from wallpaper" : "preset" }
    ]
}

// Primary (tile body) action per tile.
function tileAct(id, st) {
    var s = dflt(st)
    switch (id) {
    case "wifi": return s.wifi.avail ? op("wifi", { on: !s.wifi.on }) : off()
    case "bt": return s.bt.avail ? op("bt", { on: !s.bt.on }) : off()
    case "quiet": return s.quiet.avail ? op("dnd", { on: !s.quiet.on }) : off()
    case "vpn":
        var ac = vpnActive(s)
        return ac.length ? argv("nmcli", "connection", "down", "id", ac[0].name) : op("open", { id: "vpn" })
    case "ts": return s.ts.installed ? argv("tailscale", s.ts.on ? "down" : "up") : off()
    case "mic": return s.mic.avail ? argv("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", s.mic.muted ? "0" : "1") : off()
    case "night": return s.night.avail ? op("nightlight") : off()
    case "awake": return op("caffeine")
    case "perf": return perfAct(s.perf.profile === "performance" ? "balanced" : "performance")
    case "theme": return op("open", { id: "theme" })
    }
    return off()
}

function perfAct(profile) {
    if (profile === "power-saver") return argv("powerprofilesctl", "set", "power-saver")
    if (profile === "performance") return argv("dots-ops", "perf-mode", "on")
    if (profile === "balanced") return argv("dots-ops", "perf-mode", "off")
    return off()
}

function themeAct(fromWallpaper) { return argv("dots-theme", fromWallpaper ? "wallpaper" : "preset") }

// ---- menus ----------------------------------------------------------------------------
function menuName(id) {
    var names = { wifi: "Wi-Fi", bt: "Bluetooth", quiet: "Quiet", vpn: "VPN", ts: "Tailscale", mic: "Mic mute",
                  night: "Night light", awake: "Stay awake", perf: "Performance", theme: "Theme",
                  sound: "Sound", display: "Display" }
    return names[id] || ""
}
function menuIcon(id, st) {
    var t = tiles(st).filter(function (x) { return x.id === id })[0]
    return t ? t.icon : (id === "sound" ? "sound" : id === "display" ? "display" : "gear")
}

function menu(id, st) {
    var s = dflt(st)
    var rows = []
    switch (id) {
    case "wifi": rows = wifiRows(s); break
    case "bt": rows = btRows(s); break
    case "quiet": rows = quietRows(s); break
    case "vpn": rows = vpnRows(s); break
    case "ts": rows = tsRows(s); break
    case "mic": rows = micRows(s); break
    case "night": rows = nightRows(s); break
    case "awake": rows = awakeRows(s); break
    case "perf": rows = perfRows(s); break
    case "theme": rows = themeRows(s); break
    case "sound": rows = soundRows(s); break
    case "display": rows = displayRows(s); break
    default: return null
    }
    return { id: id, name: menuName(id), icon: menuIcon(id, st), rows: rows }
}

function wifiRows(s) {
    var w = s.wifi, r = []
    r.push(toggle("Wi-Fi", w.wired ? "Wired is primary, Wi-Fi is the fallback" : "", w.on,
                  w.avail ? op("wifi", { on: !w.on }) : off()))
    var cur = w.nets.filter(function (n) { return n.cur })
    var rest = w.nets.filter(function (n) { return !n.cur })
    if (cur.length) {
        r.push(head("CONNECTED"))
        cur.forEach(function (n) { r.push(item(n.ssid, n.sub, { cur: true, lock: n.lock, right: "Details" })) })
    }
    if (rest.length) {
        r.push(head("NEARBY"))
        rest.forEach(function (n) {
            r.push(item(n.ssid, n.sub, { lock: n.lock, act: argv("nmcli", "device", "wifi", "connect", n.ssid) }))
        })
    }
    if (w.wired) {
        r.push(head("WIRED"))
        r.push(item(w.wired.name, w.wired.sub, { right: "Details" }))
    }
    var btns = [["Join other network", off("needs a password prompt")], ["Share as QR", off()]]
    if (cur.length) btns.push(["Forget " + cur[0].ssid, argv("nmcli", "connection", "delete", "id", cur[0].ssid)])
    btns.push(["Network settings", argv("nm-connection-editor")])
    r.push(actions(btns))
    return r
}

function btRows(s) {
    var b = s.bt, r = []
    r.push(toggle("Bluetooth", "Visible only while this menu is open", b.on,
                  b.avail ? op("bt", { on: !b.on }) : off()))
    if (b.connected.length) {
        r.push(head("CONNECTED"))
        b.connected.forEach(function (d) {
            r.push(item(d.name, d.sub, { cur: true, right: "Disconnect",
                        rightAct: op("btdev", { addr: d.addr, does: "disconnect" }), kind: d.kind }))
        })
    }
    if (b.paired.length) {
        r.push(head("PAIRED, NOT NEARBY"))
        b.paired.forEach(function (d) {
            r.push(item(d.name, d.sub, { right: "Forget", rightAct: op("btdev", { addr: d.addr, does: "forget" }), kind: d.kind }))
        })
    }
    r.push(actions([["Pair new device", off("needs a pairing prompt")], ["Audio codec", off()],
                    ["Bluetooth settings", argv("blueman-manager")]]))
    return r
}

function quietRows(s) {
    var q = s.quiet, r = []
    r.push(choice("Mode", ["Off", "Quiet", "Focus", "Silent"], q.on ? "Quiet" : "Off", function (n) {
        return n === "Off" ? op("dnd", { on: false }) : n === "Quiet" ? op("dnd", { on: true }) : off()
    }))
    r.push(choice("For", ["30m", "1h", "Next prayer", "Logout", "Until off"], "Until off"))
    r.push(head("STILL REACHES YOU"))
    r.push(toggle("VIP mail and DMs", "", false))
    r.push(toggle("Production alerts", "critical only", false))
    r.push(toggle("Agent waiting on you", "after 5 minutes", false))
    r.push(toggle("Salah reminders", "always on, cannot be turned off here", true))
    r.push(head("SCHEDULE"))
    r.push(item("Weekdays", "", { right: "Edit" }))
    r.push(actions([["Held notifications" + (q.held ? " (" + q.held + ")" : "")], ["Quiet settings"]]))
    return r
}

function vpnRows(s) {
    var ac = vpnActive(s), r = []
    r.push(toggle("VPN", ac.length ? "Connected: " + ac.map(function (c) { return c.name }).join(", ") : "Nothing connected",
                  ac.length > 0, ac.length ? argv("nmcli", "connection", "down", "id", ac[0].name) : off("pick a connection below")))
    r.push(head("CONNECTIONS"))
    s.vpn.conns.forEach(function (c) {
        r.push(item(c.name, c.sub || (c.cur ? "connected" : ""), { cur: c.cur, right: c.cur ? "Disconnect" : "Connect",
                    rightAct: argv("nmcli", "connection", c.cur ? "down" : "up", "id", c.name) }))
    })
    if (!s.vpn.conns.length) r.push(item("No VPN profiles", "", {}))
    r.push(head("OPTIONS"))
    r.push(toggle("Connect on untrusted Wi-Fi", "Guest and open networks", false))
    r.push(toggle("Block traffic if it drops", "kill switch", false))
    r.push(actions([["Import config"], ["VPN settings", argv("nm-connection-editor")]]))
    r.push(note("Configs stay in your secrets store, never in the public repo."))
    return r
}

function tsRows(s) {
    var t = s.ts, r = []
    r.push(toggle("Tailscale", t.on ? "Signed in, this machine is online" : (t.installed ? "Off" : "Not installed"), t.on,
                  t.installed ? argv("tailscale", t.on ? "down" : "up") : off()))
    r.push(head("PEERS"))
    t.peers.forEach(function (p) {
        var ssh = p.cur && p.name
        r.push(item(p.name, p.sub, { cur: p.cur, right: ssh ? "SSH" : "Copy IP",
                    rightAct: ssh ? argv("ghostty", "-e", "ssh", "--", p.name) : (p.ip ? argv("wl-copy", p.ip) : off()) }))
    })
    if (!t.peers.length) r.push(item("No peers", "", {}))
    r.push(head("ROUTING"))
    var exits = ["None"].concat(t.peers.filter(function (p) { return p.exitCapable }).map(function (p) { return p.name }))
    r.push(choice("Exit node", exits, t.exit || "None", function (n) {
        return t.installed ? argv("tailscale", "set", "--exit-node=" + (n === "None" ? "" : n)) : off()
    }))
    r.push(toggle("MagicDNS", "", !!t.magicDns, t.installed ? argv("tailscale", "set", "--accept-dns=" + (!t.magicDns)) : off()))
    r.push(toggle("Accept subnet routes", "", !!t.acceptRoutes, t.installed ? argv("tailscale", "set", "--accept-routes=" + (!t.acceptRoutes)) : off()))
    r.push(actions([["Send a file"], ["Admin page", off(READ_ONLY)], ["Sign out"]]))
    return r
}

function micRows(s) {
    var m = s.mic, r = []
    r.push(toggle("Mute microphone", "A red dot shows on the bar while muted", m.muted,
                  m.avail ? argv("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", m.muted ? "0" : "1") : off()))
    r.push(head("INPUT"))
    m.inputs.forEach(function (i) { r.push(item(i.name, i.sub || (i.cur ? "default" : ""), { cur: i.cur })) })
    r.push(slider("Input level", m.v, m.muted ? "muted" : (m.speaking ? "speaking" : m.v + "%"), m.avail ? op("micvol") : off()))
    r.push(toggle("Noise suppression", "local, no cloud", m.denoise))
    if (m.using.length) {
        r.push(head("USING THE MIC NOW"))
        m.using.forEach(function (u) { r.push(item(u.name, u.sub, { right: "Block" })) })
    }
    r.push(choice("Push to talk", ["Off", "Hold Caps", "Hold Mouse 5"], m.ptt || "Off"))
    r.push(actions([["Sound settings", argv("pavucontrol")]]))
    return r
}

function nightRows(s) {
    var n = s.night, r = []
    r.push(toggle("Night light", n.on ? "On now" : "Off", n.on, n.avail ? op("nightlight") : off()))
    r.push(slider("Warmth", Parse.kelvinToWarmth(n.kelvin), n.kelvin + " K", n.avail ? op("kelvin") : off()))
    r.push(choice("Schedule", ["Sunset to sunrise", "Maghrib to Fajr", "Custom", "Off"], n.schedule || "Off"))
    r.push(head("EXCEPTIONS"))
    r.push(toggle("Pause for colour work", "Colour picker and image apps", false))
    r.push(toggle("Pause while recording", "", false))
    r.push(actions([["Display settings"]]))
    return r
}

function awakeRows(s) {
    var a = s.awake, r = []
    r.push(toggle("Stay awake", "Screen may still lock; no suspend", a.on, op("caffeine")))
    r.push(choice("For", ["30m", "1h", "2h", "Until a command ends", "Until off"], "Until off"))
    if (a.command) r.push(item("Command", a.command, { right: "Change" }))
    r.push(toggle("Keep the screen on too", "For reading or a long build log", false))
    r.push(note("The bar shows a coffee cup while this is on, so it is never forgotten."))
    return r
}

function perfRows(s) {
    var p = s.perf, r = []
    var label = { "power-saver": "Power saver", balanced: "Balanced", performance: "Performance" }
    var back = { "Power saver": "power-saver", Balanced: "balanced", Performance: "performance" }
    r.push(choice("Profile", ["Power saver", "Balanced", "Performance"], label[p.profile] || "", function (n) { return perfAct(back[n]) }))
    if (p.gpu) {
        r.push(head("GPU"))
        r.push(item("Graphics card", p.gpu.temp + " C, " + p.gpu.busy + "% busy", {}))
        r.push(slider("Video memory", p.gpu.vramPct, p.gpu.vramLabel))
    }
    ;(p.models || []).forEach(function (m) {
        r.push(item("Local models", m.sub, { right: "Unload", rightAct: argv("ollama", "stop", m.name) }))
    })
    r.push(head("RULES"))
    r.push(toggle("Performance while a local model runs", "", false))
    r.push(toggle("Balanced again after 10 idle minutes", "", false))
    r.push(actions([["Open system monitor", argv("ghostty", "-e", "btop")]]))
    return r
}

function themeRows(s) {
    var t = s.theme, r = []
    var wall = t.source === "wallpaper"
    r.push(choice("Mode", ["Dark", "Light", "Follow time"], "Dark", function (n) { return n === "Dark" ? null : off("dots-theme is dark only") }))
    r.push(toggle("Accent from wallpaper", "Status colours stay fixed", wall, themeAct(!wall)))
    if (t.swatches.length) {
        r.push(head("WALLPAPER"))
        r.push({ k: "swatches", sw: t.swatches, act: off() })
    }
    r.push(actions([["Pick wallpaper"], ["Theme settings"]]))
    return r
}

function soundRows(s) {
    var v = s.vol, r = []
    r.push(slider("Volume", v.v, v.out || (v.muted ? "muted" : ""), v.avail ? op("volume") : off()))
    if (v.out) {
        r.push(head("OUTPUT"))
        r.push(item(v.out, "default", { cur: true }))
    }
    r.push(actions([["Sound settings", argv("pavucontrol")]]))
    return r
}

function displayRows(s) {
    var r = []
    if (s.bright.avail) r.push(slider("Brightness", s.bright.v, "", op("brightness")))
    if (s.screens.length) {
        r.push(head("LAYOUT"))
        r.push({ k: "monitors", screens: s.screens })
    }
    r.push(choice("Scale", ["100%", "125%", "150%"], ""))
    r.push(toggle("Same brightness on all", "", false))
    r.push(actions([["Display settings"]]))
    return r
}

// ---- session --------------------------------------------------------------------------
function sessionButtons(st, env) {
    var s = dflt(st)
    env = env || {}
    var logout = env.sessionId ? argv("loginctl", "terminate-session", String(env.sessionId))
        : env.user ? argv("loginctl", "terminate-user", String(env.user)) : off()
    var blocked = s.session.blocker ? off("Blocked: " + s.session.blocker) : null
    return [
        { id: "lock", icon: "lock", title: "Lock", sub: "Keeps the day open", act: argv("loginctl", "lock-session") },
        { id: "logout", icon: "logout", title: "Log out", sub: s.session.logoutNote || "Ends your day", act: blocked || logout },
        { id: "suspend", icon: "suspend", title: "Suspend", sub: "Saves state first", act: argv("systemctl", "suspend") },
        { id: "reboot", icon: "reboot", title: "Reboot", sub: "Restores after login", act: blocked || argv("systemctl", "reboot") },
        { id: "poweroff", icon: "power", title: "Shut down", sub: "Saves state first", danger: true,
          act: blocked || argv("systemctl", "poweroff") },
        { id: "backup", icon: "backup", title: "Back up, then shut down", sub: "Company and personal",
          act: off("needs a chained command") }
    ]
}

// ---- right-click menus ----------------------------------------------------------------
function contextMenu(kind) {
    var sep = { sep: true }
    if (kind === "window") return {
        title: "Right click: window", rows: [
            { icon: "fullscreen", label: "Full screen", hint: "WM F", act: op("wm", { does: "fullscreen" }) },
            { icon: "tile", label: "Tile with…", hint: "WM T", act: op("wm", { does: "tile" }) },
            { icon: "tabgroup", label: "Add to tab group", hint: "WM G", act: op("wm", { does: "tabgroup" }) },
            { icon: "pin", label: "Pin on all workspaces", hint: "", act: op("wm", { does: "pin" }) },
            { icon: "profile", label: "Move to profile…", hint: "", act: op("wm", { does: "profile" }) },
            sep,
            { icon: "screenshot", label: "Send screenshot to agent", hint: "", act: off(READ_ONLY) },
            sep,
            { icon: "close", label: "Close", hint: "WM Q", danger: true, act: op("wm", { does: "close" }) }
        ] }
    return {
        title: "Right click: desktop", rows: [
            { icon: "wallpaper", label: "Change wallpaper", hint: "WM W", act: op("wm", { does: "wallpaper" }) },
            { icon: "workspace", label: "New workspace", hint: "", act: op("wm", { does: "workspace" }) },
            { icon: "capture", label: "Quick capture", hint: "WM C", act: op("wm", { does: "capture" }) },
            { icon: "settings", label: "Settings", hint: "", act: op("wm", { does: "settings" }) },
            sep,
            { icon: "lock", label: "Lock", hint: "WM L", act: argv("loginctl", "lock-session") }
        ] }
}
