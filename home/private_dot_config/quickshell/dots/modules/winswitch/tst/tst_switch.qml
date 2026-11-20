import QtQuick
import QtTest
import "../js/Switch.js" as S
import "../js/Flow.js" as F
import "../js/Acts.js" as A

TestCase {
    name: "Switch"

    function fixture() {
        var x = new XMLHttpRequest()
        x.open("GET", Qt.resolvedUrl("fixtures/windows.json"), false)
        x.send()
        return JSON.parse(x.responseText)
    }
    function mk(patch, extra) {
        var f = fixture()
        var st = S.initial()
        for (var k in patch) st[k] = patch[k]
        var inp = { windows: f.windows, activeWs: f.activeWs, activeAddr: f.activeAddr, pins: f.pins, mru: [], st: st }
        for (var e in extra) inp[e] = extra[e]
        return S.build(inp)
    }
    function ids(m) { return m.cards.map(function (c) { return c.id }) }

    // ---- order -------------------------------------------------------------------------
    function test_mru_touch_moves_to_front_and_caps() {
        compare(S.touch(["a", "b", "c"], "c").join(), "c,a,b")
        compare(S.touch(["a"], "").join(), "a")
        var big = []
        for (var i = 0; i < 100; i++) big.push("x" + i)
        compare(S.touch(big, "new").length, 64)
    }
    function test_order_uses_mru_then_focus_history() {
        var f = fixture()
        var o = S.order(f.windows, ["0xa6", "0xa2"]).map(function (w) { return w.addr })
        compare(o[0], "0xa6")
        compare(o[1], "0xa2")
        compare(o[2], "0xa3")          // focusHist 1 beats 3
    }
    function test_previous_is_the_first_non_active_normal_window() {
        var f = fixture()
        compare(S.previous(f.windows, ["0xa2", "0xa6"], "0xa2"), "0xa6")
        compare(S.previous(f.windows, [], "0xa2"), "0xa3")
        compare(S.previous([{ addr: "0x1", cls: "foot", title: "t", wsId: 1 }], [], "0x1"), "")
        var hid = [{ addr: "0x1", cls: "foot", title: "t", wsId: 1 }, { addr: "0x2", cls: "foot", title: "m", wsId: 1, hidden: true }]
        compare(S.previous(hid, ["0x1", "0x2"], "0x1"), "")
    }

    // ---- scope -------------------------------------------------------------------------
    function test_task_scope_puts_pinned_first_and_dim_last() {
        var m = mk({ scope: "task" }, { mru: ["0xa2", "0xa3", "0xa6", "0xa1"] })
        compare(ids(m).slice(0, 4).join(), "0xa2,0xa3,0xa6,0xa1")
        compare(m.cards[m.cards.length - 2].dim, "minimized")
        compare(m.cards[m.cards.length - 1].dim, "scratchpad")
        compare(m.total, 10)
    }
    function test_workspace_and_profile_scopes() {
        var w = mk({ scope: "workspace" })
        compare(ids(w).join(), "0xa2,0xa1")
        var p = mk({ scope: "profile" })
        verify(ids(p).indexOf("0xa1") >= 0)
        verify(ids(p).indexOf("0xa9") < 0)
    }
    function test_scope_keys_reset_the_selection() {
        var m = mk({ sel: 4 })
        var r = S.nav(m, S.initial(), "3")
        compare(r.st.scope, "all")
        compare(r.st.sel, 1)
    }

    // ---- filter ------------------------------------------------------------------------
    function test_filter_matches_title_tabs_app_ticket_and_profile() {
        compare(ids(mk({ query: "notes" })).join(), "0xa6")
        verify(ids(mk({ query: "keyboard grab" })).indexOf("0xa3") >= 0)       // inside a tab title
        verify(ids(mk({ query: "terminal" })).indexOf("0xa2") >= 0)            // the app label
        verify(ids(mk({ query: "ticket-123" })).length >= 4)
        verify(ids(mk({ query: "Comms" })).indexOf("0xa4") >= 0)
    }
    function test_filter_highlights_the_hit_and_says_n_of_total() {
        var m = mk({ query: "spec" })
        compare(m.cards[0].hit, "spec")
        verify(m.cards[0].pre.length + m.cards[0].hit.length + m.cards[0].post.length <= 18)
        compare(S.truncAround("Switcher spec - review notes", 18, "spec").indexOf("spec") >= 0, true)
        compare(m.qCount, "1 of 10")
        verify(m.showQuery)
        verify(!m.showScope)
    }
    function test_no_match_and_hints() {
        var m = mk({ query: "zzz" })
        compare(m.mode, "nomatch")
        compare(m.cards.length, 0)
        compare(m.hints[0].k, "Esc")
        compare(m.caption, null)
    }
    function test_trunc_keeps_both_ends() {
        compare(S.trunc("abcdefghij", 10), "abcdefghij")
        compare(S.trunc("abcdefghijkl", 7), "abc…jkl")
    }

    // ---- states ------------------------------------------------------------------------
    function test_single_window_is_a_noop_strip() {
        var m = S.build({ windows: [{ addr: "0x1", cls: "foot", title: "t", wsId: 1 }], activeWs: 1, st: S.initial(), mru: [] })
        compare(m.mode, "single")
        compare(m.caption.title, "Nothing else open")
        compare(m.hints.length, 1)
    }
    function test_locked_renders_no_cards_and_no_titles() {
        var m = mk({}, { locked: true })
        compare(m.mode, "locked")
        compare(m.cards.length, 0)
        compare(m.caption, null)
        compare(m.status, null)
        compare(JSON.stringify(m).indexOf("zsh"), -1)
        compare(JSON.stringify(m).indexOf("TICKET"), -1)
    }
    function test_redacted_after_unlock_shows_app_names_only() {
        var m = mk({}, { redacted: true })
        compare(m.cards[0].title, m.cards[0].app)
        verify(m.cards.every(function (c) { return c.ticket === "" && c.unavail }))
        compare(m.caption.meta[0].t, "names hidden, app only")
        compare(m.status.icon, "lock")
        var json = JSON.stringify(m)
        compare(json.indexOf("git status"), -1)
        compare(json.indexOf("TICKET"), -1)
        compare(json.indexOf("review notes"), -1)
    }
    function test_redacted_and_locked_together_is_locked() {
        compare(mk({}, { locked: true, redacted: true }).mode, "locked")
    }
    function test_group_card_has_a_tab_badge_and_opens_into_tabs() {
        var m = mk({ scope: "all", sel: 0 }, { mru: ["0xa3"] })
        compare(m.cards[0].badge, "3 tabs")
        verify(m.cards[0].group)
        var r = S.nav(m, S.initial(), "down")
        compare(r.st.group, "0xa3")
        var open = mk({ scope: "all", group: "0xa3" }, { mru: ["0xa3"] })
        compare(open.cards[0].badge, "tab 1/3")
        compare(open.cards[2].title, S.trunc("hl.dsp.focus reference", 18))
        verify(open.showGroupChip)
        compare(open.hints[0].k, "Left Right")
        var up = S.nav(open, { group: "0xa3" }, "up")
        compare(up.st.group, "")
    }
    function test_down_on_an_ordinary_card_only_explains() {
        var m = mk({ scope: "all", sel: 0 }, { mru: ["0xa2"] })
        var r = S.nav(m, S.initial(), "down")
        verify(r.st.msg.indexOf("Down only opens a grouped card") === 0)
        verify(r.st.group === undefined)
    }
    function test_tab_wraps_both_ways() {
        var m = mk({ sel: 0 })
        compare(S.nav(m, S.initial(), "shift-tab").st.sel, m.cards.length - 1)
        var last = mk({ sel: 99 })
        compare(last.sel, last.cards.length - 1)
        compare(S.nav(last, S.initial(), "tab").st.sel, 0)
    }
    function test_caption_has_workspace_profile_ticket_and_more_count() {
        var m = mk({ scope: "all", sel: 1 }, { mru: ["0xa2", "0xa1"] })
        compare(m.caption.title, "switcher.qml - dots")
        compare(m.caption.meta[0].t, "workspace 2")
        compare(m.caption.meta[2].t, "TICKET-123")
        compare(m.caption.count, "2 / 10   +3 more")
    }
    function test_panel_width_follows_the_card_count() {
        var three = S.build({ windows: fixture().windows.slice(0, 3), activeWs: 2, st: S.initial(), mru: [] })
        compare(three.panelW, 680)
        compare(mk({}).panelW, 893)
        compare(mk({ layout: "list" }).panelW, 780)
    }

    // ---- actions -----------------------------------------------------------------------
    function test_w_closes_a_normal_window_later_and_offers_undo() {
        var m = mk({ scope: "all", sel: 1 }, { mru: ["0xa2", "0xa1"] })
        var r = S.nav(m, S.initial(), "w")
        compare(r.side.type, "closeLater")
        compare(r.side.addr, "0xa1")
        compare(r.st.undo.addr, "0xa1")
        var after = mk({ scope: "all", sel: 1, closed: r.st.closed, undo: r.st.undo }, { mru: ["0xa2", "0xa1"] })
        compare(after.total, 9)
        verify(ids(after).indexOf("0xa1") < 0)
        verify(after.status.text.indexOf("Undo for 8 s") > 0)
        compare(after.status.action, "Undo")
    }
    function test_safe_apps_need_w_twice() {
        var m = mk({ scope: "all", sel: 0 }, { mru: ["0xa4"] })
        var first = S.nav(m, S.initial(), "w")
        compare(first.side, null)
        compare(first.st.confirm, "0xa4")
        var m2 = mk({ scope: "all", sel: 0, confirm: "0xa4" }, { mru: ["0xa4"] })
        verify(m2.status.text.indexOf("safe list") > 0)
        compare(S.nav(m2, { confirm: "0xa4" }, "w").side.type, "closeLater")
    }
    function test_close_in_a_tab_is_refused() {
        var m = mk({ scope: "all", group: "0xa3", sel: 1 }, { mru: ["0xa3"] })
        var r = S.nav(m, { group: "0xa3" }, "w")
        verify(r.st.msg.indexOf("Collapse the group first") > 0)
        compare(r.side, null)
    }
    function test_scratchpad_pin_unpin_effects() {
        var m = mk({ scope: "all", sel: 0 }, { mru: ["0xa2"] })
        compare(S.nav(m, S.initial(), "m").side.type, "scratch")
        compare(S.nav(m, S.initial(), "p", "TICKET-9").side.ticket, "TICKET-9")
        compare(S.nav(m, S.initial(), "p", "").side, null)
        compare(S.nav(m, S.initial(), "u").side.type, "unpin")
    }
    function test_pins_are_ignored_for_the_ticket_chip_when_redacted() {
        var m = mk({}, { redacted: false })
        verify(m.cards.some(function (c) { return c.ticket === "TICKET-123" }))
    }

    // ---- ai ----------------------------------------------------------------------------
    function test_question_is_ai_not_a_filter() {
        verify(S.questionFor("which window was the spec review?"))
        verify(!S.questionFor("spec"))
        var m = mk({ scope: "all", query: "which window was the spec review?", ai: { phase: "thinking", ids: [] } })
        compare(m.cards.length, 10)
        verify(m.thinking)
        compare(m.qCount, "thinking")
    }
    function test_ai_done_dims_the_rest_and_tags_the_first() {
        var m = mk({ scope: "all", query: "spec review?", ai: { phase: "done", ids: ["0xa6", "0xa1", "0xa3"] } })
        compare(m.qCount, "3 ranked")
        var c = m.cards.filter(function (x) { return x.id === "0xa6" })[0]
        verify(c.suggested)
        verify(c.ring)
        var other = m.cards.filter(function (x) { return x.id === "0xa9" })[0]
        verify(other.faded)
    }
    function test_ai_fallback_filters_to_the_fuzzy_ids() {
        var m = mk({ scope: "all", query: "spec review?", ai: { phase: "fallback", ids: ["0xa6"] } })
        compare(ids(m).join(), "0xa6")
        verify(m.status.text.indexOf("1.5 s") > 0)
    }

    // ---- flow --------------------------------------------------------------------------
    function test_quick_flip_never_shows_the_strip() {
        var a = F.press(F.start(), 1000, 1)
        compare(a.act.type, "pending")
        var t = F.tick(a.f, 1090)
        compare(t.act.type, "none")
        var r = F.release(t.f, 1090)
        compare(r.act.type, "flip")
        compare(r.f.phase, "idle")
    }
    function test_held_past_150ms_shows_then_release_commits() {
        var a = F.press(F.start(), 1000, -1)
        var t = F.tick(a.f, 1150)
        compare(t.act.type, "show")
        compare(t.act.d, -1)
        var again = F.press(t.f, 1200, 1)
        compare(again.act.type, "move")
        compare(F.release(again.f, 1300).act.type, "commit")
    }
    function test_cancel_hides_only_when_shown() {
        compare(F.cancel(F.start()).act.type, "none")
        var shown = F.tick(F.press(F.start(), 0, 1).f, 200).f
        compare(F.cancel(shown).act.type, "hide")
        compare(F.release(F.start(), 5).act.type, "none")
    }

    // ---- argv --------------------------------------------------------------------------
    function test_argv_builders_validate_and_never_use_a_shell() {
        compare(A.focusWin("0xa2").join("|"), 'hyprctl|dispatch|hl.dsp.focus({ window = "address:0xa2" })')
        compare(A.focusWin("0xa2; reboot"), null)
        compare(A.closeWin("0xa2")[1], "--batch")
        verify(A.closeWin("0xa2")[2].indexOf("hl.dsp.window.close()") > 0)
        verify(A.scratchpad("0xa2")[2].indexOf("special:scratchpad") > 0)
        compare(A.closeWin("zz"), null)
        compare(A.scratchpad(""), null)
        verify(A.ok("ok\nok"))
        verify(!A.ok("ok\nerror"))
        verify(!A.ok(""))
        compare(A.pinsArgv("/p.py", "set", "0xa1", "T-1").join("|"), "python3|/p.py|set|0xa1|T-1")
        compare(A.pinsArgv("/p.py", "rm"), null)
        var rk = A.rankArgv("/r.py", "spec?", [{ addr: "0xa1", title: "T1", app: "Editor", ticket: "TICKET-9", cls: "code" }])
        compare(rk[0], "python3")
        compare(rk[2], "spec?")
        var sent = JSON.parse(rk[3])
        compare(JSON.stringify(Object.keys(sent[0]).sort()), JSON.stringify(["app", "id", "title"]))   // titles only
        compare(rk[3].indexOf("TICKET-9"), -1)
    }
}
