import QtQuick
import QtTest
import "../js/Moments.js" as M

TestCase {
    name: "Moments"

    function test_captureArgv() {
        compare(M.captureArgv("ask sam about ballooning"), ["task", "add", "+capture", "--", "ask sam about ballooning"])
        compare(M.captureArgv("   "), null)
        compare(M.captureArgv(""), null)
        compare(M.captureArgv(undefined), null)
        compare(M.captureArgv("  a\nb  "), ["task", "add", "+capture", "--", "a b"])
        // shell metacharacters and a leading dash stay one inert argument after "--"
        compare(M.captureArgv("-x $(id); `id`")[4], "-x $(id); `id`")
        compare(M.captureArgv(new Array(700).join("a"))[4].length, 500)
    }

    function test_renudgeDelay() {
        compare(M.renudgeDelayMs(0), 600000)
        compare(M.renudgeDelayMs(1), 1800000)
        compare(M.renudgeDelayMs(7), 1800000)
        compare(M.renudgeDelayMs(-1), 600000)
        compare(M.renudgeDelayMs(NaN), 600000)
    }

    function test_renudgeDue() {
        compare(M.renudgeDue(true, true), true)
        compare(M.renudgeDue(true, false), false)
        compare(M.renudgeDue(false, true), false)
    }

    function test_isWaiting() {
        compare(M.isWaiting("Claude Code"), true)
        compare(M.isWaiting("Slack"), false)
        compare(M.isWaiting(""), false)
        compare(M.isWaiting(undefined), false)
    }

    function test_fmtAge() {
        compare(M.fmtAge(0), "0m")
        compare(M.fmtAge(59), "0m")
        compare(M.fmtAge(120), "2m")
        compare(M.fmtAge(600), "10m")
        compare(M.fmtAge(3600), "1h 00m")
        compare(M.fmtAge(3900), "1h 05m")
        compare(M.fmtAge(-4), "0m")
        compare(M.fmtAge(NaN), "0m")
        compare(M.fmtAge(undefined), "0m")
    }

    function test_backLabel() {
        compare(M.backLabel({ ref: "HD 4412", desc: "x" }), "HD 4412")
        compare(M.backLabel({ ref: "local:6f2d51", desc: "Fix the thing" }), "Fix the thing")
        compare(M.backLabel({ ref: null, desc: "Fix the thing" }), "Fix the thing")
        compare(M.backLabel({ ref: "", desc: "a very long description that will not fit in the chip" }), "a very long description th…")
        compare(M.backLabel(null), "your task")
        compare(M.backLabel({ ref: "", desc: "" }), "your task")
    }

    function test_detour() {
        var task = { ref: "HD 4412", desc: "d" }
        var d = M.detour({ task: task, clock: { state: "away", sinceTs: 1000 } }, 1240)
        compare(d.active, true)
        compare(d.sec, 240)
        compare(d.age, "4m")
        compare(d.label, "HD 4412")
        compare(d.text, "Detour 4m · back to HD 4412")
        compare(M.detour({ task: task, clock: { state: "in", sinceTs: 1000 } }, 1240).active, false)
        compare(M.detour({ task: null, clock: { state: "away", sinceTs: 1000 } }, 1240).active, false)
        compare(M.detour({ task: task, clock: { state: "away", sinceTs: null } }, 1240).active, false)
        compare(M.detour(null, 1240).active, false)
        compare(M.detour({ ts: 1000, task: task, clock: { state: "away", sinceTs: 900 } }, 1100).active, true)
        compare(M.detour({ ts: 1000, task: task, clock: { state: "away", sinceTs: 900 } }, 1181).active, false)
        compare(M.detour({ task: task, clock: { state: "away", sinceTs: 2000 } }, 1240).sec, 0)
    }

    function test_jumpArgv() {
        compare(M.jumpArgv({ ref: "HD 4412" }), ["dots-jump", "HD 4412"])
        compare(M.jumpArgv({ ref: "-rf" }), null)
        compare(M.jumpArgv({ ref: "" }), null)
        compare(M.jumpArgv(null), null)
    }

    function test_handedModel() {
        var m = M.handedModel({ ask: "a", said: "s", permission: "p", steps: [{ at: "22:04", text: "t" }, { at: 5 }, null] })
        compare(m.steps.length, 2)
        compare(m.steps[0].at, "22:04")
        compare(m.steps[1].text, "")
        compare(m.empty, false)
        compare(M.handedModel(null).empty, true)
        compare(M.handedModel({}).empty, true)
        compare(M.handedModel({ steps: "no" }).steps.length, 0)
    }

    // the chip says the ticket a person would say aloud, not an internal id
    function test_backLabel_ticket() {
        compare(M.backLabel({ ticket: "HD 8580", ref: "TASK-2026-00896", desc: "CI sizing" }), "HD 8580")
        compare(M.backLabel({ ticket: null, ref: "TASK-2026-00906", desc: "TASK-2026-00781 verify SSH host keys" }), "verify SSH host keys")
        compare(M.backLabel({ ref: "gh:acme/infra#212", desc: "x" }), "infra#212")
        compare(M.backLabel({ ref: "8635", desc: "x" }), "HD 8635")
        compare(M.backLabel({ ref: "TASK-2026-00906", desc: "" }), "your task")
    }

    function test_focusKind() {
        compare(M.focusKind({ cls: "com.mitchellh.ghostty", profile: "Agents" }), "terminal")
        compare(M.focusKind({ cls: "alacritty", profile: "Dev" }), "terminal")
        compare(M.focusKind({ cls: "Slack", profile: "Comms" }), "other")
        compare(M.focusKind({ cls: "zen-browser", profile: "Web" }), "other")
        // a popup of the shell, nothing focused, a special workspace: no information
        compare(M.focusKind({ cls: "dots.otter", profile: "Agents" }), "neutral")
        compare(M.focusKind({ cls: "", profile: "Agents" }), "neutral")
        compare(M.focusKind({ cls: "Slack", profile: "" }), "neutral")
        compare(M.focusKind(null), "neutral")
    }

    function test_focusStep_leaveAndReturn() {
        var s = M.freshFocus()
        var term = { cls: "com.mitchellh.ghostty", profile: "Agents", ws: 1 }
        var web = { cls: "zen", profile: "Web", ws: 2 }
        s = M.focusStep(s, term, 1000, "t1")
        compare(s.home, "Agents"); compare(s.homeWs, 1); compare(s.offSince, 0)
        s = M.focusStep(s, web, 1010, "t1")
        compare(s.offSince, 1010)
        // staying off does not move the clock
        s = M.focusStep(s, { cls: "Slack", profile: "Comms", ws: 4 }, 1100, "t1")
        compare(s.offSince, 1010)
        // a popup is not a return and not a departure
        s = M.focusStep(s, { cls: "dots.otter", profile: "Comms", ws: 4 }, 1105, "t1")
        compare(s.offSince, 1010)
        // back on the terminal clears it
        s = M.focusStep(s, term, 1200, "t1")
        compare(s.offSince, 0)
    }

    function test_focusStep_defaultHomeIsAgentsAndDev() {
        var s = M.freshFocus()
        // nothing learned yet: the work surfaces are home, the rest are away
        s = M.focusStep(s, { cls: "Code", profile: "Dev", ws: 3 }, 500, "t1")
        compare(s.offSince, 0)
        s = M.focusStep(s, { cls: "Slack", profile: "Comms", ws: 4 }, 600, "t1")
        compare(s.offSince, 600)
    }

    function test_focusStep_homeIsWhereTheTerminalWas() {
        var s = M.freshFocus()
        s = M.focusStep(s, { cls: "ghostty", profile: "Comms", ws: 4 }, 100, "t1")
        compare(s.home, "Comms")
        // Slack shares that profile: not a detour. Dev is not home any more.
        s = M.focusStep(s, { cls: "Slack", profile: "Comms", ws: 4 }, 110, "t1")
        compare(s.offSince, 0)
        s = M.focusStep(s, { cls: "Code", profile: "Dev", ws: 3 }, 120, "t1")
        compare(s.offSince, 120)
    }

    function test_focusStep_newTaskResets() {
        var s = M.freshFocus()
        s = M.focusStep(s, { cls: "ghostty", profile: "Agents", ws: 1 }, 100, "t1")
        s = M.focusStep(s, { cls: "zen", profile: "Web", ws: 2 }, 110, "t1")
        s = M.focusStep(s, { cls: "zen", profile: "Web", ws: 2 }, 130, "t2")
        compare(s.home, ""); compare(s.homeWs, 0)
        // the new task starts counting from the moment it was first seen off
        compare(s.offSince, 130)
    }

    function test_detour_fromFocus() {
        var task = { ticket: "HD 8635", ref: "TASK-2026-00906", desc: "d" }
        var doc = { task: task, clock: { state: "in", sinceTs: 1 } }
        var fs = { home: "Agents", homeWs: 1, offSince: 1000, key: "x" }
        // under two minutes: nothing yet
        compare(M.detour(doc, 1119, fs).active, false)
        var d = M.detour(doc, 1120, fs)
        compare(d.active, true)
        compare(d.sec, 120)
        compare(d.text, "Detour 2m · back to HD 8635")
        compare(M.detour(doc, 1300, fs).text, "Detour 5m · back to HD 8635")
        // on the task again
        compare(M.detour(doc, 1300, { home: "Agents", homeWs: 1, offSince: 0, key: "x" }).active, false)
        // no task, no detour; a dead writer is not a detour
        compare(M.detour({ task: null, clock: { state: "in" } }, 1300, fs).active, false)
        compare(M.detour({ ts: 1000, task: task, clock: { state: "in" } }, 1300, fs).active, false)
        // logged out: not a detour
        compare(M.detour({ task: task, clock: { state: "out" } }, 1300, fs).active, false)
        // the away clock still counts and wins
        compare(M.detour({ task: task, clock: { state: "away", sinceTs: 1250 } }, 1300, fs).sec, 50)
    }

    function test_backArgvs() {
        var task = { ref: "local:6f2d51" }
        compare(M.focusWsArgv(2), ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"2\" })"])
        compare(M.focusWsArgv(0), null)
        compare(M.focusWsArgv(-98), null)
        compare(M.backArgvs(task, 1), [["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"1\" })"], ["dots-jump", "local:6f2d51"]])
        compare(M.backArgvs(task, 0), [["dots-jump", "local:6f2d51"]])
        compare(M.backArgvs({ ref: "-x" }, 3), [["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"3\" })"]])
        compare(M.backArgvs(null, 0), [])
    }

    function test_chipHint() {
        compare(M.BACK_KEY, "Super+Alt+B")
    }
}
