import QtQuick
import QtTest
import "../js/Waiting.js" as W

TestCase {
    name: "Waiting"

    function item(o) {
        var d = { id: "x", kind: "review", title: "T", ref: "R", src: "gh", url: "https://example.invalid/x",
                  urgency: "active", waiting: true, ageSec: 600, actor: "ada", jump: null }
        for (var k in o) d[k] = o[k]
        return d
    }

    function test_fmt() {
        compare(W.fmtAge(0), "0m")
        compare(W.fmtAge(59 * 60), "59m")
        compare(W.fmtAge(3600), "1h")
        compare(W.fmtAge(3600 + 1500), "1h 25m")
    }

    function test_category() {
        compare(W.category(item({ kind: "alert", waiting: false })), "problem")
        compare(W.category(item({ kind: "dm" })), "chat")
        compare(W.category(item({ kind: "mail" })), "mail")
        compare(W.category(item({ kind: "review", src: "herdr" })), "agent")
        compare(W.category(item({ kind: "erp" })), "other")
    }

    function test_included() {
        var m = W.build([item({ id: "a" }), item({ id: "b", kind: "task", waiting: false }),
                         item({ id: "c", kind: "alert", waiting: false, urgency: "critical" }),
                         item({ id: "d", waiting: false })], { filter: "all" })
        compare(m.rows.length, 2)       // task and non-waiting review are not waiting on me
        compare(m.counts.all, 2)
        compare(m.counts.problem, 1)
    }

    function test_tone() {
        compare(W.tone(item({ urgency: "time", ageSec: 60 * 10 })), "dim")       // rule 60, age 10
        compare(W.tone(item({ urgency: "time", ageSec: 60 * 40 })), "amber")     // 0.67
        compare(W.tone(item({ urgency: "time", ageSec: 60 * 95 })), "red")       // 1.58
        compare(W.tone(item({ kind: "alert", waiting: false, urgency: "critical" })), "red")
        compare(W.tone(item({ kind: "dm", urgency: "critical", waiting: true, ageSec: 5 })), "amber")   // rule 0: amber
    }

    function test_order() {
        var items = [
            item({ id: "old-dim", urgency: "passive", ageSec: 60 * 20 }),
            item({ id: "amber-old", urgency: "time", ageSec: 60 * 50 }),
            item({ id: "amber-new", urgency: "time", ageSec: 60 * 40 }),
            item({ id: "red", urgency: "time", ageSec: 60 * 100 }),
            item({ id: "prob", kind: "alert", waiting: false, urgency: "critical", ageSec: 60 * 3 })
        ]
        var m = W.build(items, { filter: "all" })
        compare(m.rows.map(function (r) { return r.id }).join(","), "prob,red,amber-old,amber-new,old-dim")
        compare(m.banner.kind, "red")
        compare(m.banner.text, "1 problem. Fix it first, the rest wait.")
        compare(m.order, "problems first, then oldest")
    }

    function test_cap_and_more() {
        var items = []
        for (var i = 0; i < 9; i++) items.push(item({ id: "i" + i, ageSec: 60 * (i + 1) }))
        var m = W.build(items, { filter: "all" })
        compare(m.rows.length, 6)
        compare(m.moreN, 3)
        compare(m.moreLabel, "3 more, open sidebar")
        var one = W.build(items.slice(0, 2), { filter: "all" })
        compare(one.moreLabel, "Open sidebar")
    }

    function test_filter_and_chips() {
        var items = [item({ id: "m", kind: "mail" }), item({ id: "c", kind: "dm" }), item({ id: "r" })]
        var m = W.build(items, { filter: "chat" })
        compare(m.rows.length, 1)
        compare(m.rows[0].id, "c")
        compare(m.title, "Chat")
        compare(m.chips.map(function (c) { return c.key + c.n }).join(","), "all3,mail1,chat1,agent0,problem0")
        compare(m.order, "rule: reply within 1h")
    }

    function test_row_fields() {
        var m = W.build([item({ id: "a", title: "Review parser", actor: "grace", kind: "review", urgency: "active", ageSec: 7200,
                                jump: { pane: "p" } })], { filter: "all", focusId: "a" })
        var r = m.rows[0]
        compare(r.subj, "Review parser")
        compare(r.age, "2h")
        compare(r.tone, "amber")             // rule 120, age 120 = 1.0
        compare(r.icon, "clipboard-text")
        compare(r.focused, true)
        compare(r.canJump, true)
        compare(r.canOpen, true)
        verify(r.muted.indexOf("grace") === 0)
    }

    function test_open_only_https() {
        var m = W.build([item({ id: "a", url: "javascript:alert(1)" }), item({ id: "b", url: "http://x" }),
                         item({ id: "c", url: "https://example.invalid" })], { filter: "all" })
        var by = {}
        m.rows.forEach(function (r) { by[r.id] = r.canOpen })
        compare(by.a, false)
        compare(by.b, false)
        compare(by.c, true)
    }

    function test_empty_and_stale() {
        var m = W.build([], { filter: "all" })
        compare(m.empty, true)
        compare(m.rows.length, 0)
        var s = W.build([item({})], { filter: "all", stale: true })
        compare(s.banner.kind, "unknown")
        var n = W.build(null, { filter: "all" })
        compare(n.empty, true)
    }

    function test_prayer_hint() {
        var m = W.build([item({})], { filter: "all", prayerIn: 12 })
        compare(m.prayer, "prayer in 12m")
        compare(W.build([item({})], { filter: "all" }).prayer, "")
        compare(W.build([item({})], { filter: "mail", prayerIn: 12 }).prayer, "")
    }

    function test_focus_first() {
        var items = [item({ id: "a", ageSec: 60 }), item({ id: "b", ageSec: 600 })]
        compare(W.build(items, { filter: "all", focusFirst: true }).rows[0].focused, true)
        compare(W.build(items, { filter: "all", focusFirst: true, focusId: "a" }).rows[1].focused, true)
        compare(W.build(items, { filter: "all", focusFirst: true, focusId: "gone" }).rows[0].focused, true)
        compare(W.build(items, { filter: "all" }).rows[0].focused, false)
    }
}
