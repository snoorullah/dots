import QtQuick
import QtTest
import "../js/Keys.js" as K

TestCase {
    name: "Keys"

    function ch(c) { return { key: 0, text: c, shift: false, ctrl: false, alt: false } }
    function qt(code) { return { key: code, text: "", shift: false, ctrl: false, alt: false } }
    function st(o) {
        var s = { page: "queue", sub: "today", zone: "list", mode: "", kind: "msg", pending: "", filterActive: false }
        for (var k in o) s[k] = o[k]
        return s
    }
    function run(ev, o) { return K.resolve(ev, st(o)) }

    function test_tokens() {
        compare(K.tokenOf(ch("j")), "j")
        compare(K.tokenOf(ch("G")), "G")
        compare(K.tokenOf(qt(0x01000001)), "Tab")
        compare(K.tokenOf(qt(0x01000002)), "Backtab")
        compare(K.tokenOf({ key: 0x01000004, text: "\r", ctrl: true }), "Ctrl+Enter")
        compare(K.tokenOf({ key: 0x20, text: "", shift: true }), "")
        compare(K.tokenOf(ch("\u0001")), "")
    }

    function test_digits_jump_tabs() {
        var names = ["queue", "inbox", "agents", "tasks", "time"]
        for (var i = 0; i < 5; i++) {
            var r = run(ch(String(i + 1)), { page: "time" })
            compare(r.action, "tab"); compare(r.arg, names[i])
        }
        compare(run(ch("6"), {}).action, "")
        compare(run(ch("0"), {}).action, "")
    }

    function test_tab_cycles_panes() {
        compare(run(qt(0x01000001), { page: "queue", zone: "list" }).arg, "detail")
        compare(run(qt(0x01000001), { page: "queue", zone: "detail" }).arg, "list")
        compare(run(qt(0x01000002), { page: "queue", zone: "list" }).arg, "detail")
        compare(run(qt(0x01000001), { page: "time", zone: "tabs" }).arg, "list")
        compare(run(qt(0x01000002), { page: "time", zone: "tabs" }).arg, "list")
        compare(run(qt(0x01000001), { page: "tasks", zone: "list" }).arg, "list")
    }

    function test_brackets_switch_subtab_or_chip() {
        compare(run(ch("]"), { page: "time", sub: "today" }).arg, "week")
        compare(run(ch("["), { page: "time", sub: "today" }).arg, "agents")
        compare(run(ch("]"), { page: "time", sub: "reminders" }).arg, "agents")
        compare(run(ch("]"), { page: "time", sub: "agents" }).arg, "today")
        var c = run(ch("]"), { page: "queue" })
        compare(c.action, "chip"); compare(c.arg, 1)
        compare(run(ch("["), { page: "inbox" }).arg, -1)
    }

    function test_move_keys() {
        var moves = ["j", "n", "e", "k"]
        var want = [1, 1, -1, -1]
        for (var i = 0; i < moves.length; i++) {
            var r = run(ch(moves[i]), {})
            compare(r.action, "move"); compare(r.arg, want[i])
        }
        compare(run(qt(0x01000015), {}).arg, 1)
        compare(run(qt(0x01000013), {}).arg, -1)
    }

    function test_gg_and_G() {
        var a = run(ch("g"), {})
        compare(a.action, ""); compare(a.pending, "g")
        var b = run(ch("g"), { pending: "g" })
        compare(b.action, "top"); compare(b.pending, "")
        compare(run(ch("G"), {}).action, "bottom")
        // another key clears the pending g
        var c = run(ch("j"), { pending: "g" })
        compare(c.action, "move"); compare(c.pending, "")
    }

    function test_enter_opens_detail_then_primary() {
        var r = run(qt(0x01000004), { page: "queue", zone: "list", kind: "msg" })
        compare(r.action, "pane"); compare(r.arg, "detail")
        compare(run(qt(0x01000004), { page: "queue", zone: "list", kind: "" }).action, "primary")
        compare(run(qt(0x01000004), { page: "tasks", zone: "list", kind: "" }).action, "primary")
        compare(run(qt(0x01000004), { page: "queue", zone: "detail" }).action, "primary")
    }

    function test_escape_ladder() {
        compare(run(qt(0x01000000), { zone: "detail" }).arg, "list")
        compare(run(qt(0x01000000), { zone: "list", filterActive: true }).action, "filter.clear")
        compare(run(qt(0x01000000), { zone: "list" }).action, "cc.close")
        compare(run(qt(0x01000000), { page: "time", zone: "list" }).arg, "tabs")
        compare(run(qt(0x01000000), { page: "time", zone: "list" }).action, "pane")
        compare(run(qt(0x01000000), { page: "time", zone: "tabs" }).action, "cc.close")
        compare(run(qt(0x01000000), { zone: "panel", mode: "reply" }).action, "panel.close")
        compare(run(qt(0x01000000), { zone: "panel", mode: "snooze" }).action, "panel.close")
        compare(run(qt(0x01000000), { zone: "filter" }).action, "filter.close")
        compare(run(qt(0x01000000), { zone: "help" }).action, "help.close")
    }

    function test_filter_and_help_open() {
        compare(run(ch("/"), {}).action, "filter.open")
        compare(run(ch("?"), {}).action, "help.open")
        compare(run(ch("?"), { zone: "help" }).action, "help.close")
    }

    function test_text_entry_passes_keys_through() {
        // typing j, 1, ? or q in a text field must not navigate
        var zones = [{ zone: "filter" }, { zone: "panel", mode: "reply" }, { zone: "panel", mode: "agent" }]
        var keys = ["j", "1", "?", "q", "/", "[", "g"]
        for (var z = 0; z < zones.length; z++)
            for (var i = 0; i < keys.length; i++)
                compare(run(ch(keys[i]), zones[z]).action, "", zones[z].zone + " " + keys[i])
        compare(run({ key: 0x01000004, text: "\r", ctrl: true }, { zone: "panel", mode: "reply" }).action, "panel.submit")
        compare(run({ key: 0, text: "u", ctrl: true }, { zone: "filter" }).action, "filter.clear")
    }

    function test_snooze_panel_numbers() {
        for (var n = 1; n <= 4; n++) {
            var r = run(ch(String(n)), { zone: "panel", mode: "snooze" })
            compare(r.action, "panel.pick"); compare(r.arg, n)
        }
        compare(run(ch("5"), { zone: "panel", mode: "snooze" }).action, "none")
        compare(run(ch("j"), { zone: "panel", mode: "snooze" }).action, "panel.next")
        compare(run(qt(0x01000004), { zone: "panel", mode: "snooze" }).arg, 0)
    }

    function test_help_overlay_swallows() {
        compare(run(ch("j"), { zone: "help" }).action, "help.down")
        compare(run(ch("3"), { zone: "help" }).action, "none")
        compare(run(ch("r"), { zone: "help" }).action, "none")
    }

    function test_board_action_keys_in_detail_zone() {
        var table = {
            agent: { a: "allow", d: "deny", o: "open", s: "snooze", b: "breakdown", j: "jump" },
            msg: { r: "reply", g: "agent", q: "queue", s: "snooze", o: "open", b: "breakdown", j: "jump" },
            alert: { v: "analysis", f: "fix", q: "queue", s: "snooze" },
            pr: { o: "open", g: "agent", q: "queue", s: "snooze" },
            ticket: { c: "comment", g: "agent", q: "queue", s: "snooze", o: "open" },
            mail: { r: "reply", g: "agent", q: "queue", s: "snooze" },
            capture: { t: "task", g: "agent", x: "dismiss" }
        }
        var pages = ["queue", "inbox"]
        for (var p = 0; p < pages.length; p++)
            for (var kind in table)
                for (var key in table[kind]) {
                    var r = run(ch(key), { page: pages[p], zone: "detail", kind: kind })
                    compare(r.action, "act." + table[kind][key], pages[p] + " " + kind + " " + key)
                }
    }

    function test_action_keys_do_not_fire_from_list_zone() {
        // j and g navigate in the list, Jump and Send to agent live in the detail pane
        compare(run(ch("j"), { zone: "list", kind: "msg" }).action, "move")
        compare(run(ch("r"), { zone: "list", kind: "msg" }).action, "")
        compare(run(ch("j"), { zone: "detail", kind: "msg" }).action, "act.jump")
    }

    function test_wrong_kind_key_is_unhandled() {
        compare(run(ch("a"), { zone: "detail", kind: "msg" }).action, "")
        compare(run(ch("r"), { zone: "detail", kind: "" }).action, "")
    }

    function test_agents_tasks_time_actions() {
        compare(run(ch("o"), { page: "agents", zone: "list" }).action, "act.open")
        compare(run(ch("b"), { page: "tasks", zone: "list" }).action, "act.breakdown")
        compare(run(ch("c"), { page: "time", sub: "report", zone: "list" }).action, "act.copy")
        compare(run(ch("c"), { page: "time", sub: "today", zone: "list" }).action, "")
        compare(run(ch("d"), { page: "time", sub: "reminders", zone: "list" }).action, "act.done")
        compare(run(ch("o"), { page: "time", sub: "agents", zone: "list" }).action, "act.open")
        compare(run(ch("t"), { page: "agents", zone: "list" }).action, "act.time")
        compare(run(qt(0x01000004), { page: "time", sub: "agents", zone: "list" }).action, "primary")
    }

    function test_mouse_only_controls_have_keys() {
        compare(run(ch("u"), { page: "queue" }).action, "undo")
        compare(run(ch("}"), { page: "queue" }).arg, 1)
        compare(run(ch("{"), { page: "inbox" }).action, "view")
        compare(run(ch("="), { page: "queue", zone: "detail" }).action, "group")
        compare(run(ch("}"), { page: "time" }).action, "")
        compare(run({ key: 0x47, text: "", ctrl: true }, { page: "queue", zone: "panel", mode: "agent" }).action, "")
        compare(run({ key: 0x47, text: "g", ctrl: true }, { page: "queue", zone: "panel", mode: "agent" }).action, "panel.grant")
        compare(run({ key: 0x47, text: "g", ctrl: true }, { page: "queue", zone: "panel", mode: "reply" }).action, "")
        // typing stays typing: u in a text field is a letter
        compare(run(ch("u"), { zone: "filter" }).action, "")
        compare(K.nextView("", 1), "VIPs")
        compare(K.nextView("VIPs", -1), "")
        compare(K.nextView("Infra only", 1), "")
        compare(K.nextGroup("Person", 1), "Urgency")
        compare(K.nextBy("App", 1), "Project")
        var keys = K.helpRows(st({ page: "queue" })).map(function (r) { return r.keys })
        verify(keys.indexOf("u") >= 0 && keys.indexOf("{  }") >= 0 && keys.indexOf("=") >= 0)
        verify(K.helpRows(st({ page: "queue", zone: "panel", mode: "agent" })).some(function (r) { return r.keys === "Ctrl+g" }))
    }

    function test_time_today_actions() {
        compare(run(ch("s"), { page: "time", sub: "today", zone: "list" }).action, "act.focus")
        compare(run(ch("b"), { page: "time", sub: "today", zone: "list" }).action, "act.break")
        compare(run(ch("p"), { page: "time", sub: "today", zone: "list" }).action, "period")
        compare(run(ch("s"), { page: "time", sub: "today", zone: "tabs" }).action, "")
    }

    function test_time_columns_and_period() {
        compare(run(ch("l"), { page: "time", sub: "week" }).action, "col")
        compare(run(qt(0x01000012), { page: "time", sub: "heatmap" }).arg, -1)
        compare(run(ch("p"), { page: "time", sub: "progress" }).arg, 1)
        compare(run(ch("P"), { page: "time", sub: "progress" }).arg, -1)
        compare(K.nextPeriod("quarter", 1), "today")
    }

    function test_time_tabs_zone() {
        compare(run(ch("l"), { page: "time", zone: "tabs", sub: "days" }).arg, "heatmap")
        compare(run(qt(0x01000012), { page: "time", zone: "tabs", sub: "days" }).arg, "week")
        compare(run(qt(0x01000004), { page: "time", zone: "tabs", sub: "days" }).arg, "list")
    }

    function test_detail_zone_navigation() {
        compare(run(qt(0x01000015), { zone: "detail" }).action, "scroll")
        compare(run(ch("h"), { zone: "detail" }).arg, "list")
        compare(run(ch("l"), { zone: "list", kind: "msg" }).arg, "detail")
        compare(run(ch("l"), { zone: "list", kind: "" }).action, "")
    }

    function test_every_action_key_is_in_help() {
        var cases = [
            { page: "queue", zone: "detail", kind: "agent" }, { page: "queue", zone: "detail", kind: "msg" },
            { page: "inbox", zone: "detail", kind: "alert" }, { page: "inbox", zone: "detail", kind: "pr" },
            { page: "queue", zone: "detail", kind: "ticket" }, { page: "queue", zone: "detail", kind: "mail" },
            { page: "queue", zone: "detail", kind: "capture" }, { page: "agents" }, { page: "tasks" },
            { page: "time", sub: "report" }, { page: "time", sub: "reminders" }, { page: "time", sub: "agents" }, { page: "time", sub: "today" }
        ]
        for (var c = 0; c < cases.length; c++) {
            var rows = K.helpRows(st(cases[c]))
            var acts = rows.filter(function (r) { return r.group === "Actions" }).map(function (r) { return r.keys })
            var s = st(cases[c])
            var list = K.actionList(s)
            verify(list.length > 0, JSON.stringify(cases[c]))
            for (var i = 0; i < list.length; i++)
                verify(acts.indexOf(list[i][0]) >= 0, list[i][0])
            // and every listed key resolves to its action
            for (var j = 0; j < list.length; j++)
                compare(K.resolve(ch(list[j][0]), s).action, "act." + list[j][1])
        }
    }

    function test_help_has_global_rows() {
        var rows = K.helpRows(st({}))
        var keys = rows.map(function (r) { return r.keys }).join(" | ")
        verify(keys.indexOf("1 2 3 4 5") >= 0)
        verify(keys.indexOf("Tab") >= 0)
        verify(keys.indexOf("g g") >= 0)
        verify(keys.indexOf("?") >= 0)
        verify(K.helpRows(st({ page: "time" })).some(function (r) { return r.keys === "p  P" }))
    }

    function test_time_scroll_and_run_keys() {
        var ev = function (t) { return { key: 0, text: t, shift: t === "J" || t === "K", ctrl: false, alt: false } }
        var base = { page: "time", sub: "heatmap", zone: "list", mode: "", kind: "", pending: "", filterActive: false }
        compare(K.resolve(ev("J"), base).action, "scroll"); compare(K.resolve(ev("K"), base).arg, -1)
        compare(K.resolve(ev("r"), { page: "time", sub: "report", zone: "list", mode: "", kind: "", pending: "", filterActive: false }).action, "act.run")
        verify(K.helpRows(st({ page: "time" })).some(function (r) { return r.keys === "J  K" }))
    }

    function test_focus_ring_rule() {
        var on = K.ring("element", true, true)
        verify(on.visible); compare(on.width, 2); compare(on.color, "accent")
        verify(!K.ring("element", true, false).visible)   // pointer focus draws no ring
        verify(!K.ring("element", false, true).visible)
        compare(K.ring("pane", true, true).width, 1)
    }
}
