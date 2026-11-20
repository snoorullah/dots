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

    // ---- mask, agent states, suggestions, launcher row, sets ----------------------------
    function titles(m, name) { return prof(m, name).ws.reduce(function (a, w) { return a.concat(w.wins.map(function (x) { return x.title })) }, []) }
    function test_mask_hides_sensitive_titles_only() {
        var raw = build({ mask: false })
        compare(titles(raw, "Comms")[0], "Chat")
        verify(!raw.mask)
        var m = build({ mask: true })
        verify(m.mask)
        compare(titles(m, "Comms")[0], "Masked title")      // chat
        compare(titles(m, "Comms")[1], "Masked title")      // mail
        compare(titles(m, "Web")[2], "Masked title")        // "Private window"
        compare(titles(m, "Web")[0], "Search")              // an ordinary browser window keeps its title
        compare(titles(m, "Dev")[0], "main.go - Editor")
    }
    function test_masked_titles_are_not_searchable() {
        var m = build({ mask: true, query: "private", mode: "full" })
        compare(m.resultCount, 0)                           // the hidden text must not leak through the filter
        var n = build({ mask: false, query: "private", mode: "full" })
        compare(n.resultCount, 1)
    }
    function test_agent_states() {
        var m = build({}, function (f) {
            f.windows[0].agent = "working"; f.windows[1].agent = "paused"; f.windows[2].agent = "needs"
        })
        var rows = prof(m, "Agents").ws[0].wins
        compare(rows[0].state, "needs")                      // needs outranks working (the window also has needs)
        compare(rows[1].state, "paused"); verify(rows[1].resumed)
        compare(rows[2].state, "needs")
        var w = build({}, function (f) { f.windows[1].agent = "working" })
        compare(prof(w, "Agents").ws[0].wins[1].state, "working")
        verify(!prof(w, "Agents").ws[0].wins[1].resumed)
    }
    function test_suggest_only_in_other() {
        var m = build()
        var other = prof(m, "Other").ws.reduce(function (a, w) { return a.concat(w.wins) }, [])
        var term = other.filter(function (x) { return x.addr === "0xf2" })[0]
        compare(term.suggest, "Dev")
        compare(other.filter(function (x) { return x.addr === "0xf1" })[0].suggest, "")    // files: no guess
        compare(other.filter(function (x) { return x.addr === "0xf3" })[0].suggest, "")    // settings: no guess
        compare(prof(m, "Dev").ws[0].wins[1].suggest, "")                                  // already in a profile
        compare(M.suggestFor("browser", "Other"), "Web")
        compare(M.suggestFor("chat", "Other"), "Comms")
    }
    function test_launcher_row_and_enter() {
        var m = build({ query: "zzz", mode: "full" })
        compare(m.launcher.query, "zzz")
        verify(m.launcher.text.indexOf("zzz") > 0 && m.launcher.text.indexOf("launcher") > 0)
        var a = M.nav(m, "enter").act
        compare(a.type, "launcher"); compare(a.query, "zzz")
        var hit = build({ query: "term", mode: "full" })
        compare(M.nav(hit, "enter").act.type, "focusWin")     // a match still wins
        verify(hit.launcher !== null)                          // the row stays as a way out
        compare(build({ query: "term", mode: "pop" }).launcher, null)
        compare(build().launcher, null)
    }
    function test_sets_from_layout() {
        var now = Date.parse("2026-11-20T09:00:00")
        var layout = { saved_at: "2026-11-20T08:20:00", clients: [
            { class: "code", workspace: 3 }, { class: "foot", workspace: 3 }, { class: "foot", workspace: 3 },
            { class: "zen-beta", workspace: 2 }, { class: "foot", workspace: 11 } ] }
        var m = build({}, function (f) { f.layout = layout; f.now = now })
        verify(m.setsKnown)
        var dev = prof(m, "Dev").ret
        verify(dev.has); compare(dev.n, 3)
        compare(dev.text, "3 win, 40 min ago")
        compare(dev.sub, "3 windows, 40 min ago")
        compare(dev.sum, "Editor, 2 terminals")
        compare(dev.ws.length, 1); compare(dev.ws[0], 3)
        compare(prof(m, "Comms").ret.has, false)
        compare(prof(m, "Comms").ret.text, "No saved set")
        compare(prof(m, "Other").ret.n, 1)                     // ws 11 is nobody's: Other
        verify(!build().setsKnown)                             // no status yet: the rows stay hidden
        var b = M.nav(build({ focus: "Dev" }, function (f) { f.layout = layout; f.now = now }), "b").act
        compare(b.type, "backSet"); compare(b.ws[0], 3); compare(b.n, 3)
        compare(Object.keys(M.nav(build({ focus: "Comms" }, function (f) { f.layout = layout; f.now = now }), "b")).length, 0)
    }
    function test_ago() {
        compare(M.ago(0, 20 * 1000), "just now")
        compare(M.ago(0, 12 * 60000), "12 min")
        compare(M.ago(0, 2 * 3600000), "2 h")
        compare(M.ago(0, 3 * 86400000), "3 d")
    }
    function test_new_workspace_key() {
        var c = build({ focus: "Comms" }, function (f) { f.windows = f.windows.filter(function (w) { return w.wsId !== 5 }) })
        compare(c.newWs, 5)                                    // Comms owns 4 and 5; 5 is free
        compare(M.nav(c, "n").act.id, 5)
        var d = build({ focus: "Dev" })
        compare(d.newWs, 0)                                    // Dev owns only 3 and it is in use
        compare(Object.keys(M.nav(d, "n")).length, 0)
    }
    function test_set_argv() {
        compare(D.backSet("/b/dots-layout", [3, 6]).join(" "), "/b/dots-layout restore --apply --parts layout,apps --workspaces 3,6")
        compare(D.backSet("/b/dots-layout", []), null)
        compare(D.backSet("/b/dots-layout", [3, "x; rm"]), null)
        compare(D.undoSet("/b/dots-layout").join(" "), "/b/dots-layout undo")
        compare(D.startSet("/b/dots-layout", "Dev", 3).join(" "), "/b/dots-layout startup --workspace 3 --name Dev")
        compare(D.startSet("/b/dots-layout", "Dev; x", 3), null)
        var q = D.launcherQuery("kubectl get pods; rm -rf", "/qs")
        compare(q[q.length - 1], "kubectl get pods; rm -rf")   // one argv element, nothing is parsed
        compare(q.length, 8)
        compare(q.slice(0, 4).join(" "), "quickshell ipc -p /qs")
        compare(D.launcherQuery("", "/qs"), null)
        compare(D.launcherQuery("x"), null)
        verify(D.okJson('{"ok": true, "launched": 2}'))
        verify(!D.okJson('{"ok": false}'))
        verify(!D.okJson("garbage"))
        compare(D.reply("noise\n{\"ok\": true}").ok, true)
    }
}
