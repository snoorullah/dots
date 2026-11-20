import QtQuick
import QtTest
import "../js/Menus.js" as M

TestCase {
    name: "Menus"

    function st() {
        return {
            wifi: { avail: true, on: true, ssid: "Home 5G", nets: [
                { ssid: "Home 5G", cur: true, lock: true, sub: "5 GHz, strong, WPA3" },
                { ssid: "Guest; touch /tmp/x", cur: false, lock: false, sub: "open network" }], wired: { name: "Ethernet", sub: "1 Gb/s, connected" } },
            bt: { avail: true, on: true, connected: [{ addr: "AA:BB", name: "Headphones", sub: "audio, 50% battery", kind: "headphones" }, { addr: "CC:DD", name: "Trackball", sub: "input", kind: "mouse" }], paired: [{ addr: "EE:FF", name: "Laptop keyboard", sub: "last seen 3 days ago", kind: "keyboard" }] },
            quiet: { avail: true, on: false },
            vpn: { conns: [{ name: "Work", cur: false }, { name: "Travel", cur: false }] },
            ts: { installed: true, on: true, peers: [{ name: "laptop", sub: "online, direct", cur: true, ip: "100.64.0.2" }, { name: "nas", sub: "offline", cur: false, ip: "100.64.0.4" }], exit: "None" },
            mic: { avail: true, v: 70, muted: false, inputs: [{ name: "USB microphone", cur: true }], using: [] },
            night: { avail: true, on: true, kelvin: 4300, until: "06:00" },
            awake: { on: false },
            perf: { profile: "balanced", gpu: { temp: 54, busy: 18, vramPct: 38, vramLabel: "9.1 of 24 GB" } },
            theme: { source: "wallpaper", swatches: ["#1f4654"] }
        }
    }

    function test_tiles_order_and_state() {
        var t = M.tiles(st())
        compare(t.length, 10)
        compare(t.map(function (x) { return x.id }).join(","), "wifi,bt,quiet,vpn,ts,mic,night,awake,perf,theme")
        compare(t[0].sub, "Home 5G"); verify(t[0].on)
        compare(t[1].sub, "2 connected")
        verify(!t[2].on); compare(t[2].sub, "off")
        compare(t[3].sub, "off")
        compare(t[4].sub, "1 peer")
        compare(t[6].sub, "until 06:00")
        compare(t[8].sub, "balanced"); verify(!t[8].on)
        compare(t[9].sub, "from wallpaper")
    }

    function test_empty_state_never_invents_values() {
        var t = M.tiles({})
        compare(t[0].sub, "unavailable"); verify(!t[0].on)
        compare(t[4].sub, "not installed")
        compare(t[8].sub, "unknown")
        verify(M.disabled(M.tileAct("wifi", {})))
        verify(M.disabled(M.tileAct("ts", {})))
    }

    function test_perf_argv_uses_dots_ops() {
        compare(JSON.stringify(M.perfAct("performance").argv), '["dots-ops","perf-mode","on"]')
        compare(JSON.stringify(M.perfAct("balanced").argv), '["dots-ops","perf-mode","off"]')
        compare(JSON.stringify(M.perfAct("power-saver").argv), '["powerprofilesctl","set","power-saver"]')
        verify(M.disabled(M.perfAct("turbo")))
        var m = M.menu("perf", st())
        var ch = m.rows[0]
        compare(ch.k, "choice")
        compare(ch.opts.filter(function (o) { return o.on })[0].t, "Balanced")
        compare(ch.opts[2].act.argv[2], "on")
    }

    function test_theme_argv() {
        compare(JSON.stringify(M.themeAct(true).argv), '["dots-theme","wallpaper"]')
        compare(JSON.stringify(M.themeAct(false).argv), '["dots-theme","preset"]')
        var m = M.menu("theme", st())
        compare(m.rows[1].k, "toggle"); verify(m.rows[1].on)
        compare(m.rows[1].act.argv[1], "preset")          // switching off goes to the preset
        verify(M.disabled(m.rows[0].opts[1].act))          // light mode: dots-theme is dark only
    }

    function test_session_argv() {
        var b = M.sessionButtons({}, { sessionId: "3", user: "u" })
        compare(b.length, 6)
        compare(JSON.stringify(b[0].act.argv), '["loginctl","lock-session"]')
        compare(JSON.stringify(b[1].act.argv), '["loginctl","terminate-session","3"]')
        compare(JSON.stringify(b[2].act.argv), '["systemctl","suspend"]')
        compare(JSON.stringify(b[3].act.argv), '["systemctl","reboot"]')
        compare(JSON.stringify(b[4].act.argv), '["systemctl","poweroff"]')
        verify(b[4].danger)
        verify(M.disabled(b[5].act))
        compare(M.sessionButtons({}, { user: "u" })[1].act.argv[1], "terminate-user")
        verify(M.disabled(M.sessionButtons({}, {})[1].act))
        var blocked = M.sessionButtons({ session: { blocker: "terraform apply runs in pane 2" } }, { sessionId: "3" })
        verify(M.disabled(blocked[4].act)); verify(M.disabled(blocked[3].act))
        verify(!M.disabled(blocked[0].act))                // lock is never blocked
    }

    function test_hostile_names_stay_one_argv_element() {
        var m = M.menu("wifi", st())
        var nearby = m.rows.filter(function (r) { return r.k === "item" && r.t.indexOf("Guest") === 0 })[0]
        compare(nearby.act.argv.length, 5)
        compare(nearby.act.argv[4], "Guest; touch /tmp/x")
        var ts = M.menu("ts", st())
        var peer = ts.rows.filter(function (r) { return r.k === "item" && r.t === "laptop" })[0]
        compare(peer.rightAct.argv.slice(0, 4).join(" "), "ghostty -e ssh --")
    }

    function test_every_menu_builds_and_ends_with_actions_or_note() {
        var ids = M.ORDER.concat(M.EXTRA)
        for (var i = 0; i < ids.length; i++) {
            var m = M.menu(ids[i], st())
            verify(m !== null, ids[i])
            verify(m.rows.length > 0, ids[i])
            verify(m.name.length > 0, ids[i])
            for (var j = 0; j < m.rows.length; j++) verify(m.rows[j].k !== undefined, ids[i] + " row " + j)
        }
        compare(M.menu("nope", st()), null)
    }

    function test_no_unwired_row_pretends() {
        // every row act is either an argv array of strings, a named op, or an explicit off
        var ids = M.ORDER.concat(M.EXTRA)
        for (var i = 0; i < ids.length; i++) {
            var rows = M.menu(ids[i], st()).rows
            rows.forEach(function (r) {
                var acts = []
                if (r.act) acts.push(r.act)
                if (r.rightAct) acts.push(r.rightAct)
                ;(r.opts || []).forEach(function (o) { if (o.act) acts.push(o.act) })
                ;(r.btns || []).forEach(function (b) { acts.push(b.act) })
                acts.forEach(function (a) {
                    verify(typeof a.op === "string")
                    if (a.op === "argv") a.argv.forEach(function (x) { compare(typeof x, "string") })
                    if (a.op === "off") verify(a.why.length > 0)
                })
            })
        }
    }

    function test_context_menus() {
        var w = M.contextMenu("window")
        compare(w.rows.filter(function (r) { return !r.sep }).length, 7)
        var shot = w.rows.filter(function (r) { return r.label === "Send screenshot to agent" })[0]
        compare(shot.act.why, "read-only for now")
        var d = M.contextMenu("desktop")
        compare(d.rows[d.rows.length - 1].act.argv[1], "lock-session")
    }

    function test_warmth_slider_matches_kelvin() {
        var m = M.menu("night", st())
        var s = m.rows.filter(function (r) { return r.k === "slider" })[0]
        compare(s.v, 55); compare(s.right, "4300 K")
    }
}
