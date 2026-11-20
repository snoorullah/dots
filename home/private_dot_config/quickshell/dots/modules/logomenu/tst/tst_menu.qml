import QtQuick
import QtTest
import "../js/Menu.js" as M

TestCase {
    name: "Menu"

    function mk(st, extra) {
        var inp = { health: { state: "ok", fix: "", up: "2d 4h" }, mode: "Heavy work", salah: { on: false }, st: st || { sel: "", query: "", logout: 0 } }
        for (var k in extra) inp[k] = extra[k]
        return M.build(inp)
    }
    function kinds(m) { return m.secs.map(function (s) { return s.kind }) }
    function labels(m) {
        var out = []
        m.secs.forEach(function (s) { s.rows.forEach(function (r) { out.push(r.label) }) })
        return out
    }

    function test_healthy_layout_and_preselected_first_row() {
        var m = mk()
        compare(m.head.t, "Shell ok")
        compare(m.head.r, "up 2d 4h")
        compare(m.sel, "control")
        compare(kinds(m).join(), "label,rows,label,modes,rule,label,rows,rule,label,session,rule,foot")
        compare(m.secs[1].rows.length, 6)
        verify(m.secs[1].rows[0].selected)
        compare(m.secs[1].rows[0].combo, "Super+C")
        compare(m.secs[3].chips.length, 6)
        verify(m.secs[3].chips[3].on)
    }
    function test_row_cap_holds_in_every_state() {
        verify(mk().rowCount <= M.ROW_CAP)
        verify(mk({ sel: "", query: "e", logout: 0 }).rowCount <= M.ROW_CAP)
        verify(mk({ sel: "", query: "", logout: 0 }, { health: { state: "degraded", fix: "reload", up: "1h" } }).rowCount <= M.ROW_CAP)
    }
    function test_degraded_floats_the_broken_row_first_and_preselects_it() {
        var m = mk({ sel: "", query: "", logout: 0 }, { health: { state: "degraded", fix: "hypr", up: "1h 2m" } })
        compare(m.head.t, "Hyprland not responding")
        compare(m.head.tone, "warn")
        compare(m.sel, "hypr")
        var fix = m.secs[6].rows
        compare(fix[0].id, "hypr")
        verify(fix[0].hot)
        compare(fix[0].combo, "Enter")
        compare(m.secs[7].kind, "ask")
    }
    function test_why_is_the_shell_red_shows_a_local_hint_only_when_asked() {
        var d = { health: { state: "degraded", fix: "reload", up: "" } }
        verify(kinds(mk({ sel: "", query: "", logout: 0 }, d)).indexOf("note") < 0)
        var m = mk({ sel: "", query: "", logout: 0, ai: true }, d)
        verify(kinds(m).indexOf("note") >= 0)
    }
    function test_safe_mode_has_one_way_back_and_the_log() {
        var m = mk({ sel: "", query: "", logout: 0 }, { health: { state: "safe", fix: "", up: "" } })
        compare(m.head.t, "Safe mode")
        compare(m.sel, "back")
        compare(labels(m).join(), "Back to full shell,Show shell log,Lock,Logout")
        verify(kinds(m).indexOf("modes") < 0)
    }
    function test_salah_locks_chips_dims_logout_and_refuses_it() {
        var m = mk({ sel: "", query: "", logout: 0 }, { salah: { on: true, ends: "13:42", next: "Asr 16:05" } })
        compare(m.head.t, "Salah active")
        compare(m.head.r, "then Asr 16:05")
        compare(m.mode, "Salah")
        verify(m.secs[3].chips.filter(function (c) { return c.locked }).length === 5)
        verify(m.secs[4].text.indexOf("ends 13:42") > 0)
        compare(m.secs.filter(function (x) { return x.kind === "session" })[0].sub, "after salah")
        compare(M.nav(m, { logout: 0 }, "q", true).side, null)
        compare(M.nav(m, { logout: 0 }, "q", true).st.toast, "Logout waits until salah ends")
    }
    function test_filter_narrows_every_row_and_empty_says_so() {
        var m = mk({ sel: "", query: "re", logout: 0 })
        compare(m.filtering, true)
        compare(kinds(m).join(), "filter,rows")
        verify(labels(m).indexOf("Reload shell") >= 0)
        verify(labels(m).indexOf("Lock") < 0)
        compare(m.sel, m.secs[1].rows[0].id)
        var none = mk({ sel: "", query: "zz", logout: 0 })
        compare(none.secs[1].kind, "empty")
        compare(none.secs[1].text, "Nothing here. Esc")
    }
    function test_letters_run_rows_and_other_letters_start_the_filter() {
        var m = mk()
        compare(M.nav(m, m, "r").side.act.name, "reload-shell")
        compare(M.nav(m, m, "g").side.act.fn, "cc")
        compare(M.nav(m, m, "l").side.act.name, "lock")
        var f = M.nav(m, m, "z")
        compare(f.st.query, "z")
        compare(f.side, null)
        compare(M.nav(m, m, "q", false).st.query, "q")           // plain q filters, only Shift+Q logs out
        compare(M.nav(m, m, "q", true).st.logout, 3)
    }
    function test_arrows_wrap_and_home_end_jump() {
        var m = mk()
        compare(M.nav(m, m, "down").st.sel, "sidebar")
        compare(M.nav(m, m, "up").st.sel, "logout")
        compare(M.nav(m, m, "end").st.sel, "logout")
        compare(M.nav(m, m, "home").st.sel, "control")
        compare(M.nav(m, m, "j").st.sel, "sidebar")
    }
    function test_enter_runs_the_selected_row_and_recovery_rows_toast() {
        var m = mk({ sel: "hypr", query: "", logout: 0 })
        var r = M.nav(m, m, "enter")
        compare(r.side.type, "act")
        compare(r.side.act.name, "reload-hypr")
        compare(r.st.toast, "Hyprland reloaded")
    }
    function test_logout_counts_down_inline_and_esc_cancels_it() {
        var m = mk()
        var r = M.nav(m, m, "enter")                               // control
        compare(r.side.type, "act")
        var lo = mk({ sel: "logout", query: "", logout: 0 })
        var start = M.nav(lo, lo, "enter")
        compare(start.st.logout, 3)
        compare(start.side.type, "countdown")
        var c = mk({ sel: "logout", query: "", logout: 3 })
        compare(c.secs[9].kind, "countdown")
        compare(c.countdownText, "3... 2... 1...")
        compare(mk({ sel: "logout", query: "", logout: 2 }).countdownText, "2... 1...")
        var esc = M.nav(c, c, "esc")
        compare(esc.st.logout, 0)
        compare(esc.st.toast, "Logout cancelled")
        compare(M.nav(c, c, "down").side, null)                    // nothing else works mid-countdown
        compare(M.tickLogout(1), 0)
        compare(M.tickLogout(0), 0)
    }
    function test_esc_clears_a_filter_then_closes() {
        var f = mk({ sel: "", query: "re", logout: 0 })
        compare(M.nav(f, f, "esc").st.query, "")
        compare(M.nav(mk(), mk(), "esc").side.type, "close")
    }
    function test_focus_note_only_for_focus_mode_and_once() {
        var m = mk({ sel: "", query: "", logout: 0, focusNote: true }, { mode: "Focus" })
        verify(kinds(m).indexOf("note") >= 0)
        verify(kinds(mk({ sel: "", query: "", logout: 0, focusNote: true })).indexOf("note") < 0)
    }
    function test_uptime_text() {
        compare(M.uptimeText(0), "up 0m")
        compare(M.uptimeText(95 * 60000), "up 1h 35m")
        compare(M.uptimeText((2 * 1440 + 4 * 60) * 60000), "up 2d 4h")
    }
    function test_argv_builders_whitelist_everything() {
        compare(M.modeArgv("/r.py", "Focus").join("|"), "python3|/r.py|mode|set|Focus")
        compare(M.modeArgv("/r.py", "Salah"), null)
        compare(M.modeArgv("/r.py", "x; rm"), null)
        compare(M.recoverArgv("/r.py", "lock").join("|"), "python3|/r.py|lock")
        compare(M.recoverArgv("/r.py", "rm -rf"), null)
        compare(M.ipcArgv("/qs", "dots.launcher", "toggle").join("|"), "quickshell|ipc|-p|/qs|call|dots.launcher|toggle")
        compare(M.ipcArgv("/qs", "x;y", "toggle"), null)
    }
    function test_no_task_names_anywhere_in_the_model() {
        var json = JSON.stringify(mk())
        compare(json.toLowerCase().indexOf("task"), -1)
        compare(json.toLowerCase().indexOf("ticket"), -1)
    }

    function test_a_click_runs_that_row_not_the_selected_one() {
        var m = mk()
        var r = M.nav(m, m, "enter", false, "reload")
        compare(r.side.act.name, "reload-shell")
        compare(M.nav(m, m, "enter", false, "logout").st.logout, 3)
    }
}
