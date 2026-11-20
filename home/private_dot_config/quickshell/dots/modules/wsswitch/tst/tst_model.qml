import QtQuick
import QtTest
import "../js/Model.js" as M
import "../js/Dispatch.js" as D

TestCase {
    name: "WsModel"

    function fixture() {
        var x = new XMLHttpRequest()
        x.open("GET", Qt.resolvedUrl("fixtures/hypr.json"), false)
        x.send()
        return JSON.parse(x.responseText)
    }
    function build(st, patch) {
        var f = fixture()
        if (patch) patch(f)
        f.st = st || {}
        return M.build(f)
    }
    function prof(m, n) { return m.profiles.filter(function (p) { return p.name === n })[0] }

    function test_profiles_and_counts() {
        var m = build()
        compare(m.profiles.length, 7)
        compare(m.active, "Dev")
        compare(m.focus, "Dev")
        compare(prof(m, "Dev").total, 4)
        compare(prof(m, "Agents").total, 4)
        compare(prof(m, "Comms").total, 2)
        compare(prof(m, "Notes").total, 0)
        verify(prof(m, "Notes").empty)
        compare(prof(m, "Other").total, 4)          // ws 8 and the unowned ws 11
        compare(prof(m, "Other").ws.length, 2)
        compare(m.totalWins, 20)
    }
    function test_needs_and_order() {
        var m = build()
        compare(prof(m, "Agents").needs, 2)
        compare(prof(m, "Comms").needs, 1)
        compare(m.order[0].name, "Agents")          // needs you first
        compare(m.order[1].name, "Comms")
        compare(m.order[2].name, "Dev")             // then board order
    }
    function test_urgent_workspace_counts_once() {
        var m = build({}, function (f) { f.windows.forEach(function (w) { delete w.needs }); f.workspaces[2].urgent = true })
        compare(prof(m, "Dev").needs, 1)
        compare(prof(m, "Agents").needs, 0)
    }
    function test_first_workspace_always_listed() {
        var m = build()
        compare(prof(m, "Notes").ws.length, 1)
        compare(prof(m, "Notes").ws[0].id, 7)
    }
    function test_app_classification() {
        compare(M.appOf("foot").kind, "terminal")
        compare(M.appOf("zen-beta").kind, "browser")
        compare(M.appOf("code").kind, "editor")
        compare(M.appOf("org.gnome.Nautilus").kind, "files")
        compare(M.appOf("thunderbird").icon, "envelope")
        compare(M.appOf("never-heard").kind, "other")
        compare(M.appOf("").kind, "other")
    }
    function test_window_state() {
        var m = build()
        var rows = prof(m, "Dev").ws[0].wins
        compare(rows[1].state, "active")
        compare(rows[0].state, "running")
        compare(prof(m, "Agents").ws[0].wins[0].state, "needs")
    }
    function test_selection_targets() {
        var m = build({ sel: "0xd2" })
        compare(m.sel.addr, "0xd2")
        compare(m.targets.length, 7)
        verify(m.targets[1].cur)                     // Dev
        verify(m.targets[1].disabled)
        verify(!m.targets[2].disabled)
    }
    function test_salah_dims_all_but_active() {
        var m = build({ salah: true, sel: "0xd2" })
        verify(prof(m, "Web").dim)
        verify(!prof(m, "Dev").dim)
        verify(m.targets[2].disabled)                // cannot move out during salah
    }
    function test_filter_groups_only_in_full() {
        var pop = build({ query: "term", mode: "pop" })
        verify(!pop.filtering)
        var m = build({ query: "term", mode: "full" })
        verify(m.filtering)
        verify(m.resultCount >= 5)
        compare(m.groups[0].name, "Agents")
        var hl = m.groups[0].rows.filter(function (r) { return r.mid !== "" })[0]
        compare(hl.mid.toLowerCase(), "term")           // the title match is split for highlighting
        compare(m.groups[0].rows[0].mid, "")            // matched by app name only: nothing to highlight
        var none = build({ query: "zzz", mode: "full" })
        verify(none.noResults)
        compare(none.resultCount, 0)
        compare(none.resultsText, "0 results")
    }
    function test_sub_labels() {
        var m = build({ hover: "Web" })
        compare(prof(m, "Web").sub, "Workspace 2")
        compare(prof(m, "Agents").sub, "4 windows")
        compare(prof(m, "Notes").sub, "Nothing open")
        compare(m.hoverName, "Web")
    }
    function test_tiles_main_plus_stack() {
        compare(M.tile(0).length, 0)
        compare(M.tile(1)[0][2], 1)
        var t = M.tile(4)
        compare(t.length, 4)
        verify(t[0][2] > 0.5 && t[0][3] === 1)
        verify(t[1][0] > t[0][0] + t[0][2] - 0.001)
        verify(t[3][1] + t[3][3] <= 1.0001)
    }
    function test_nav_right_follows_order() {
        compare(M.nav(build(), "right").focus, "Web")  // order: Agents Comms Dev Web ...
    }
    function test_nav_pop_follows_strip_order() {
        // needs on Agents and Comms: order is Agents Comms Dev Web, the strip is fixed
        var m = build({ focus: "Dev" })
        var names = m.profiles.map(function (p) { return p.name })
        var at = names.indexOf("Dev")
        compare(M.nav(m, "left").focus, names[at - 1])
        compare(M.nav(m, "right").focus, names[at + 1])
        var f = build({ focus: "Dev", variant: "a", mode: "full" })
        compare(M.nav(f, "left").focus, "Comms")     // full mode: rail uses needs-first order
    }
    function test_nav_order_walk() {
        var m = build({ focus: "Agents" })
        compare(M.nav(m, "right").focus, "Dev")      // pop: strip order
        compare(M.nav(m, "left").focus, "Agents")    // clamped at the first
        var d = build({ focus: "Dev" })
        compare(M.nav(d, "down").sel, "0xd1")
        var d2 = build({ focus: "Dev", sel: "0xd1" })
        compare(M.nav(d2, "down").sel, "0xd2")
        compare(M.nav(d2, "up").sel, "")
        var d3 = build({ focus: "Dev", sel: "0xd4" })
        compare(M.nav(d3, "down").sel, "0xd4")       // clamped at the last
    }
    function test_nav_enter_and_move() {
        var d = build({ focus: "Dev", sel: "0xd3" })
        compare(M.nav(d, "enter").act.type, "focusWin")
        compare(M.nav(d, "enter").act.addr, "0xd3")
        var n = build({ focus: "Dev" })
        compare(M.nav(n, "enter").act.type, "focusWs")
        compare(M.nav(n, "enter").act.id, 3)         // already on 3
        var w = build({ focus: "Web" })
        compare(M.nav(w, "enter").act.id, 2)
        var s = M.nav(w, "shift-enter").act
        compare(s.type, "moveWin"); compare(s.id, 2); verify(s.follow); compare(s.addr, "")
    }
    function test_nav_enter_in_filter_takes_first_result() {
        var m = build({ query: "claude", mode: "full" })
        compare(M.nav(m, "enter").act.type, "focusWin")
        compare(M.nav(m, "enter").act.addr, "0xa1")
        compare(M.nav(m, "down").sel, "0xa1")
    }
    function test_nav_digits() {
        var m = build()
        compare(M.nav(m, "3").focus, "Web")
        var mv = M.nav(m, "s4").act
        compare(mv.id, 4); verify(!mv.follow); compare(mv.profile, "Comms")
        compare(Object.keys(M.nav(m, "9")).length, 0)
    }
    function test_grid_nav_rows() {
        var m = build({ variant: "b", focus: "Agents" })
        compare(M.nav(m, "down").focus, "Review")   // a row is 4 cards: Agents Comms Dev Web | Review
    }
    function test_dispatch_argv() {
        compare(D.focusWs(3).join(" "), 'hyprctl dispatch hl.dsp.focus({ workspace = "3" })')
        compare(D.focusWs("3; rm"), null)
        compare(D.focusWs(0), null)
        compare(D.focusWin("0xd2").length, 3)
        compare(D.focusWin("0xd2; x"), null)
        compare(D.moveWin("", 4, true)[2], 'hl.dsp.window.move({ workspace = "4", follow = true })')
        var b = D.moveWin("0xd2", 4, false)
        compare(b[1], "--batch")
        verify(b[2].indexOf('address:0xd2') > 0 && b[2].indexOf('follow = false') > 0)
        compare(D.moveWin("zz", 4, false), null)
    }
    function test_dispatch_ok() {
        verify(D.ok("ok\n"))
        verify(D.ok("ok\nok"))
        verify(!D.ok(""))
        verify(!D.ok("Invalid dispatcher"))
        verify(!D.ok("ok\nerr"))
    }
}
