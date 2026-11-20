import QtQuick
import QtTest
import "../js/Agents.js" as A

TestCase {
    name: "Agents"

    function item(o) {
        var d = { id: "h1", kind: "blocker", title: "Run tests in sample-api", ref: "pane:1", src: "herdr", url: "",
                  urgency: "active", waiting: true, ageSec: 120, actor: "sample-agent", jump: { pane: "p1" } }
        for (var k in o) d[k] = o[k]
        return d
    }

    function test_cards_only_from_herdr_waiting() {
        var m = A.build([item({}), item({ id: "x", src: "gh" }), item({ id: "y", waiting: false })], null, {})
        compare(m.cards.length, 1)
        compare(m.cards[0].agent, "sample-agent")
        compare(m.cards[0].age, "2m")
        compare(m.cards[0].canJump, true)
        compare(m.pill, "Needs you 1")
        compare(m.lit, true)
        compare(m.quiet, false)
    }

    function test_oldest_first() {
        var m = A.build([item({ id: "a", ageSec: 60 }), item({ id: "b", ageSec: 600 })], null, {})
        compare(m.cards[0].id, "b")
    }

    function test_quiet() {
        var m = A.build([], null, {})
        compare(m.quiet, true)
        compare(m.pill, "All clear")
        compare(m.lit, false)
        compare(A.build(null, null, {}).quiet, true)
    }

    function test_focus_default_first() {
        var m = A.build([item({ id: "a", ageSec: 60 }), item({ id: "b", ageSec: 600 })], null, {})
        compare(m.cards[0].focused, true)
        compare(m.cards[1].focused, false)
        var f = A.build([item({ id: "a", ageSec: 60 }), item({ id: "b", ageSec: 600 })], null, { focusId: "a" })
        compare(f.cards[1].focused, true)
    }

    function test_agents_doc() {
        var doc = { v: 1, running: [{ name: "docs-agent", task: "Update README", elapsedSec: 1860, progress: 0.3 },
                                    { name: "triage-agent", task: "Sort notes", elapsedSec: 240, progress: null }],
                    paused: [{ name: "old-agent", why: "you paused it" }], done: ["tests passed", "inbox sorted"],
                    budget: { used: 0.38, cap: 1 } }
        var m = A.build([], doc, {})
        compare(m.running.length, 2)
        compare(m.running[0].el, "31m")
        compare(m.running[0].pct, 30)
        compare(m.running[1].pct, -1)
        compare(m.paused.length, 1)
        compare(m.done.length, 2)
        compare(m.budget.text, "$0.38 / $1")
        compare(m.budget.pct, 38)
        compare(m.quiet, true)         // running agents do not need you
    }

    function test_bad_doc() {
        compare(A.build([], { v: 2, running: [{ name: "a" }] }, {}).running.length, 0)
        compare(A.build([], "junk", {}).running.length, 0)
    }
}
