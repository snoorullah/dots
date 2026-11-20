import QtQuick
import QtTest
import "../js/Presets.js" as P
import "../js/Groups.js" as G
import "../js/Restore.js" as R
import "../js/Scratch.js" as S
import "../js/Dispatch.js" as D

TestCase {
    name: "Windows"

    function load(name) {
        var x = new XMLHttpRequest()
        x.open("GET", Qt.resolvedUrl("fixtures/" + name), false)
        x.send()
        return JSON.parse(x.responseText)
    }

    // ---- tiling assistant -----------------------------------------------------------
    function test_six_presets_in_board_order() {
        compare(P.list.length, 6)
        compare(P.list.map(function (p) { return p.name }).join("|"),
                "Main + stack|Half and half|Three columns|Wide centre|Grid|Code + review")
        P.list.forEach(function (p, i) { compare(p.key, i + 1) })
    }
    function test_thumbnails_stay_inside_the_card_and_do_not_overlap() {
        P.list.forEach(function (p) {
            p.rects.forEach(function (r, i) {
                verify(r[0] >= 0 && r[1] >= 0 && r[0] + r[2] <= 1.0001 && r[1] + r[3] <= 1.0001, p.id + " rect " + i + " inside")
                for (var j = 0; j < i; j++) {
                    var q = p.rects[j]
                    var ox = r[0] < q[0] + q[2] - 0.0001 && q[0] < r[0] + r[2] - 0.0001
                    var oy = r[1] < q[1] + q[3] - 0.0001 && q[1] < r[1] + r[3] - 0.0001
                    verify(!(ox && oy), p.id + " rects " + i + " and " + j + " overlap")
                }
            })
        })
    }
    function test_suggest_by_window_count() {
        compare(P.suggest(0), ""); compare(P.suggest(1), "")
        compare(P.suggest(2), "half")
        compare(P.suggest(3), "main-stack")
        compare(P.suggest(4), "grid")
        compare(P.suggest(7), "main-stack")
    }
    function test_build_three_windows_like_the_board() {
        var m = P.build({ n: 3 })
        compare(m.count, "3 windows in this workspace.")
        compare(m.lead, "Main + stack"); compare(m.tail, "fits.")
        verify(m.canApply)
        compare(m.selected, "main-stack")
        compare(m.presets.filter(function (p) { return p.on }).length, 1)
        verify(m.presets[0].fits)
    }
    function test_selection_and_remembered_layout() {
        compare(P.build({ n: 3, remembered: "grid" }).selected, "grid")      // the profile's last choice
        compare(P.build({ n: 3, remembered: "grid", selected: "half" }).selected, "half")
        compare(P.build({ n: 3, selected: "bogus" }).selected, "main-stack")
        var m = P.build({ n: 3, selected: "grid" })
        compare(m.lead, "Main + stack"); compare(m.tail, "fits better.")
    }
    function test_nothing_to_tile_with_one_window() {
        var m = P.build({ n: 1 })
        verify(!m.canApply)
        compare(m.count, "1 window in this workspace.")
        compare(m.lead, "Nothing to tile.")
        compare(Object.keys(P.nav(m, "enter")).length, 0)
    }
    function test_nav() {
        var m = P.build({ n: 3 })
        compare(P.nav(m, "4").selected, "wide-centre")
        compare(P.nav(m, "right").selected, "half")
        compare(P.nav(m, "down").selected, "wide-centre")
        compare(Object.keys(P.nav(m, "left")).length, 0)            // first column: nothing to the left
        compare(Object.keys(P.nav(m, "up")).length, 0)
        var last = P.build({ n: 3, selected: "code-review" })
        compare(Object.keys(P.nav(last, "right")).length, 0)         // no wrap into the next row
        compare(P.nav(m, "enter").act.id, "main-stack")
    }
    function test_preset_steps() {
        var s = P.steps("main-stack", 3)
        compare(s.length, 3)
        compare(s[0].join(" "), 'hyprctl eval hl.workspace_rule({ workspace = "3", layout = "master" })')
        compare(s[1][2], 'hl.dsp.layout("orientationleft")')
        compare(s[2][2], 'hl.dsp.layout("mfact exact 0.6")')
        compare(P.steps("grid", 2).length, 1)                          // dwindle needs no message
        compare(P.steps("nope", 3), null)
        compare(P.steps("grid", "3; x"), null)
        compare(P.steps("grid", 0), null)
        P.list.forEach(function (p) { verify(P.steps(p.id, 1).every(function (a) { return a[0] === "hyprctl" })) })
    }

    // ---- grouped tabs ---------------------------------------------------------------
    function test_group_tabs_in_order_with_the_active_one_marked() {
        var f = load("clients.json")
        var m = G.build(f.clients, f.activeAddr)
        verify(m.show); compare(m.n, 4); compare(m.text, "4 in group")
        compare(m.tabs.map(function (t) { return t.title }).join("|"), "deliver.ts|PR #2288|pane 2|Webhook notes")
        compare(m.tabs.filter(function (t) { return t.active }).length, 1)
        compare(m.tabs[1].active, true)
        compare(m.tabs[1].icon, "globe")
    }
    function test_no_strip_for_an_ungrouped_window() {
        var f = load("clients.json")
        verify(!G.build(f.clients, "0xd1").show)
        verify(!G.build(f.clients, "0xnone").show)
        verify(!G.build([], "").show)
    }
    function test_tab_titles_are_masked_when_sharing() {
        var f = load("clients.json")
        f.clients.push({ addr: "0xc5", cls: "slack", title: "private thread", grouped: ["0xc1", "0xc2", "0xc3", "0xc4", "0xc5"] })
        f.clients.forEach(function (c) { if (c.grouped.length === 4) c.grouped = ["0xc1", "0xc2", "0xc3", "0xc4", "0xc5"] })
        var m = G.build(f.clients, "0xc2", true)
        compare(m.tabs[4].title, "Masked title")
        compare(m.tabs[0].title, "deliver.ts")
    }
    function test_step_wraps() {
        var f = load("clients.json")
        var m = G.build(f.clients, "0xc4")
        compare(G.step(m, 1), "0xc1")
        compare(G.step(m, -1), "0xc3")
        compare(G.step(G.build(f.clients, "0xd1"), 1), "")
    }

    // ---- restore prompt -------------------------------------------------------------
    function test_restore_rows_like_the_board() {
        var m = R.build(load("status.json").layout)
        verify(m.show)
        compare(m.title, "Restore yesterday\u2019s layout?")
        compare(m.saved, "Last saved at 23:27")
        compare(m.rows.map(function (r) { return r.label }).join("|"),
                "Layouts and groups|Apps|herdr panes and directories|Agents, resumed paused|Finished agents")
        compare(m.rows[0].value, "7 profiles, 14 windows")
        compare(m.rows[1].value, "Browser, Editor, Chat, Notes +2")
        compare(m.rows[2].value, "9 panes")
        compare(m.rows[3].value, "3, you press go")
        compare(m.rows[4].value, "2, as plain shells")
        compare(m.rows.map(function (r) { return r.on }).join(), "true,true,true,true,false")
        compare(m.parts.join(), "layout,apps,panes,agents")
        verify(m.canRestore)
    }
    function test_restore_toggle_and_parts() {
        var s = load("status.json").layout
        var m = R.build(s, { finished: true, agents: false })
        compare(m.parts.join(), "layout,apps,panes,finished")
        var apps = R.build(s, { apps: false })
        compare(apps.parts.join(), "panes,agents")                    // no layout part without the apps it places
        var none = R.build(s, { layout: false, apps: false, panes: false, agents: false })
        verify(!none.canRestore)
        compare(Object.keys(R.nav(none, "enter")).length, 0)
    }
    function test_restore_empty_parts_are_disabled() {
        var s = load("status.json").layout
        s.panes = 0; s.agents = 0; s.finished = 0
        var m = R.build(s, { finished: true })
        compare(m.rows[2].disabled, true); compare(m.rows[2].value, "none")
        compare(m.rows[4].on, false)
        compare(m.parts.join(), "layout,apps")
    }
    function test_restore_nothing_saved() {
        var m = R.build(null)
        verify(!m.show); verify(!m.canRestore)
    }
    function test_restore_keys() {
        var m = R.build(load("status.json").layout)
        compare(R.nav(m, "enter").act.type, "restore")
        compare(R.nav(m, "enter").act.parts.join(), "layout,apps,panes,agents")
        compare(R.nav(m, "escape").act.type, "clean")
        compare(R.nav(m, "5").toggle, "finished")
        compare(Object.keys(R.nav(m, "9")).length, 0)
    }
    function test_restore_never_names_a_resume() {
        var txt = JSON.stringify(R.build(load("status.json").layout))
        verify(txt.toLowerCase().indexOf("resume now") < 0)
        compare(R.build(load("status.json").layout).rows[3].value, "3, you press go")
    }

    // ---- scratchpad -----------------------------------------------------------------
    function test_scratch_tabs_and_stubs() {
        var m = S.build({ tab: "note", text: "db-02 needs two vCPUs" })
        compare(m.tabs.map(function (t) { return t.label }).join("|"), "Note|Terminal|Snippet|Math|Ask")
        compare(m.tabs.filter(function (t) { return t.built }).length, 1)
        verify(m.built)
        compare(S.build({ tab: "math" }).built, false)
        compare(S.build({ tab: "bogus" }).tab, "note")
        compare(m.actions.map(function (a) { return a.label }).join("|"), "Turn into task|Send to agent|Save to notes|Pin")
        compare(m.actions[0].stub, true); compare(m.actions[1].stub, true)        // nothing is sent or filed
        compare(m.actions[2].stub, false)
        compare(S.build({ text: "  " }).actions[2].stub, true)                     // nothing to save
        compare(S.build({ pinned: true }).actions[3].on, true)
    }
    function test_scratch_special_workspace_per_profile() {
        compare(D.special("Dev"), "scratch-dev")
        compare(D.scratchToggle("Dev").join(" "), 'hyprctl dispatch hl.dsp.workspace.toggle_special("scratch-dev")')
        compare(D.scratchToggle("Dev; x"), null)
        compare(D.scratchToggle(""), null)
    }

    // ---- argv -----------------------------------------------------------------------
    function test_group_argv() {
        compare(D.groupToggle().join(" "), "hyprctl dispatch hl.dsp.group.toggle()")
        compare(D.groupNext()[2], "hl.dsp.group.next()")
        compare(D.groupPrev()[2], "hl.dsp.group.prev()")
        compare(D.focusTab("0xc2")[2], 'hl.dsp.focus({ window = "address:0xc2" })'.replace("0xc2", "0xc2"))
        compare(D.focusTab("0xc2; x"), null)
        var c = D.closeTab("0xab")
        compare(c[1], "--batch")
        verify(c[2].indexOf("address:0xab") > 0 && c[2].indexOf("window.close()") > 0)
        compare(D.closeTab("zz"), null)
    }
    function test_layout_argv() {
        var t = "/b/dots-layout"
        compare(D.restore(t, ["layout", "apps"]).join(" "), "/b/dots-layout restore --apply --parts layout,apps")
        compare(D.restore(t, []), null)
        compare(D.restore(t, ["apps", "rm"]), null)
        compare(D.status(t).join(" "), "/b/dots-layout status")
        compare(D.dismiss(t)[1], "dismiss")
        compare(D.undo(t)[1], "undo")
        compare(D.noteGet(t, "Dev").join(" "), "/b/dots-layout note get --profile Dev")
        compare(D.noteSet(t, "../x", "a"), null)
        compare(D.noteSet(t, "Dev", "a; rm -rf\nb").slice(2).join("|"), "set|--profile|Dev|--text|a; rm -rf\nb")
        compare(D.noteSet(t, "Dev", new Array(65538).join("a")), null)
        compare(D.noteSave(t, "Dev")[2], "save")
        compare(D.prefSet(t, "Dev", "grid").join(" "), "/b/dots-layout pref set --profile Dev --value grid")
        compare(D.prefSet(t, "Dev", "a b"), null)
        compare(D.prefGet(t, "Dev")[2], "get")
    }
    function test_replies() {
        verify(D.ok("ok\n")); verify(!D.ok("")); verify(!D.ok("ok\nerr"))
        verify(D.okEval("")); verify(!D.okEval("error: bad"))
        verify(D.okJson('{"ok": true}')); verify(!D.okJson('{"ok": false}')); verify(!D.okJson("x"))
        compare(D.reply('noise\n{"ok": true, "launched": 3}').launched, 3)
    }
}
