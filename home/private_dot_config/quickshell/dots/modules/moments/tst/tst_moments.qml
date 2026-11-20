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
}
