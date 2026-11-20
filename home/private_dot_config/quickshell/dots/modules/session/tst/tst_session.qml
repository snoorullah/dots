import QtQuick
import QtTest
import "../js/Session.js" as S

TestCase {
    name: "Session"

    function choices() {
        return [{ key: "washroom", label: "Washroom / pantry", lead: true }, { key: "walk", label: "Walk / short break", lead: false },
                { key: "meal", label: "Lunch / long break", lead: false }, { key: "meeting", label: "Meeting", lead: false },
                { key: "salah", label: "Salah", lead: false }, { key: "logout", label: "Log out for today", lead: false }]
    }

    function test_away_rows() {
        var r = S.awayRows(choices())
        compare(r.length, 6)
        compare(r[0].hint, "1"); verify(r[0].lead)
        compare(r.filter(function (x) { return x.lead }).length, 1)
        compare(S.awayRows(null).length, 0)
    }

    function test_navigation() {
        compare(S.step(0, 6, -1), 5)
        compare(S.step(5, 6, 1), 0)
        compare(S.step(2, 6, 1), 3)
        compare(S.step(0, 0, 1), 0)
        compare(S.jump("3", 6), 2)
        compare(S.jump("7", 6), -1)
        compare(S.jump("x", 6), -1)
    }

    function test_helper_argv_is_an_array() {
        compare(JSON.stringify(S.helperArgv("/p/session.py", "declare", "meal")), '["python3","-I","/p/session.py","declare","meal"]')
        compare(S.helperArgv("/p/s.py", "choices").length, 4)
    }

    function test_session_buttons_idle() {
        var b = S.sessionButtons({ sessionId: "3", user: "u" }, { blocked: false })
        compare(b.map(function (x) { return x.id }).join(","), "lock,logout,suspend,reboot,poweroff,backup")
        compare(JSON.stringify(b[0].act.argv), '["loginctl","lock-session"]')
        compare(JSON.stringify(b[1].act.argv), '["loginctl","terminate-session","3"]')
        compare(JSON.stringify(b[2].act.argv), '["systemctl","suspend"]')
        compare(JSON.stringify(b[3].act.argv), '["systemctl","reboot"]')
        compare(JSON.stringify(b[4].act.argv), '["systemctl","poweroff"]')
        verify(b[4].danger)
        verify(S.disabled(b[5].act))
        compare(b[5].act.why, "no backup command yet")
    }

    function test_blocked_greys_the_destructive_ones_only() {
        var b = S.sessionButtons({ sessionId: "3" }, { blocked: true, cmd: "terraform apply", pane: "2" })
        verify(!S.disabled(b[0].act)); verify(!S.disabled(b[2].act))
        verify(S.disabled(b[1].act)); verify(S.disabled(b[3].act)); verify(S.disabled(b[4].act))
        compare(b[4].act.why, "Blocked while terraform apply runs in pane 2")
    }

    function test_pending_check_keeps_destructive_buttons_off() {
        var b = S.sessionButtons({ sessionId: "3", backup: ["x"] }, { pending: true })
        verify(!S.disabled(b[0].act)); verify(!S.disabled(b[2].act))
        for (var i = 0; i < 6; i++) {
            if (["logout", "reboot", "poweroff", "backup"].indexOf(b[i].id) >= 0) {
                verify(S.disabled(b[i].act), b[i].id)
                compare(b[i].act.why, "Checking running commands...")
            }
        }
    }

    function test_unchecked_is_live_after_the_check_finished() {
        var b = S.sessionButtons({ sessionId: "3" }, { blocked: false, unchecked: true })
        verify(!S.disabled(b[1].act)); verify(!S.disabled(b[3].act)); verify(!S.disabled(b[4].act))
    }

    function test_logout_falls_back_to_user_then_off() {
        compare(S.sessionButtons({ user: "u" }, null)[1].act.argv[1], "terminate-user")
        verify(S.disabled(S.sessionButtons({}, null)[1].act))
    }

    function test_logout_sub_names_early_minutes() {
        compare(S.sessionButtons({ sessionId: "1", early: "3:18" }, null)[1].sub, "Ends your day, 3:18 early")
        compare(S.sessionButtons({ sessionId: "1" }, null)[1].sub, "Ends your day")
    }

    function test_backup_uses_the_given_argv_and_is_still_guarded() {
        var b = S.sessionButtons({ sessionId: "1", backup: ["dots-backup", "--then-poweroff"] }, null)
        compare(b[5].act.argv[0], "dots-backup")
        verify(S.disabled(S.sessionButtons({ backup: ["x"] }, { blocked: true, cmd: "rsync", pane: "1" })[5].act))
    }

    function test_polkit_view() {
        var v = S.polkitView({ message: "Restart a system service", actionId: "org.freedesktop.systemd1.manage-units",
                               inputPrompt: "Password: ", responseVisible: false, supplementaryMessage: "Sorry, try again.",
                               supplementaryIsError: true, responseRequired: true })
        compare(v.title, "Restart a system service")
        compare(v.prompt, "Password")
        compare(v.error, "Sorry, try again.")
        compare(v.info, "")
        verify(!v.denyFirst)
        verify(v.canAllow)
        var e = S.polkitView({})
        compare(e.title, "Authentication needed")
        compare(e.prompt, "Password")
        var a = S.polkitView({ agentHint: "An agent is working in pane 2" })
        verify(a.denyFirst)
    }

    function test_agent_hint() {
        compare(S.agentHint([{ pane_id: "w1:p1" }, { pane_id: "w1:p2", agent: "claude", agent_status: "working" }]), "An agent is working in pane 2")
        compare(S.agentHint([{ pane_id: "w1:p1", agent: "claude", agent_status: "done" }]), "")
        compare(S.agentHint(null), "")
    }

    function test_fmt_gap() {
        compare(S.fmtGap(9 * 60), "9 min")
        compare(S.fmtGap(60 * 60), "1 h")
        compare(S.fmtGap(72 * 60), "1 h 12 min")
        compare(S.fmtGap(-5), "0 min")
    }

    function test_return_rows() {
        var d = S.returnRows({ key: "meal", label: "Lunch / long break", since: 1000 }, 1000 + 45 * 60, 0, null, null)
        compare(d.length, 1)
        compare(d[0].a, "Declared"); compare(d[0].b, "Lunch break, set by you"); compare(d[0].d, "45 min")
        var s = S.returnRows({ key: "salah", label: "Salah · Asr", since: 0 }, 600, 100, null, null)
        compare(s[0].a, "Detected")
        var x = S.returnRows(null, 1000 + 9 * 60, 1000, { text: "Draft patch ready, not applied", note: "needs your click" }, { text: "2 new, read-only, nothing sent", note: "inbox" })
        compare(x.map(function (r) { return r.a }).join(","), "Detected,Agent,Mail")
        compare(x[0].b, "Idle, no input")
        compare(x[1].tone, "waiting")
        compare(S.returnRows(null, 5, 0, null, null).length, 0)
    }
}
