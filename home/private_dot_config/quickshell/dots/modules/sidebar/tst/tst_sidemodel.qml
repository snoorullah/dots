import QtQuick
import QtTest
import "../js/SideModel.js" as S

TestCase {
    name: "SideModel"

    function it(id, kind, o) {
        var b = { id: id, kind: kind, title: "t " + id, ref: null, src: null, urgency: "passive", waiting: false, ageSec: 600, actor: null }
        for (var k in o) b[k] = o[k]
        return b
    }

    function test_tabs() {
        compare(S.TABS.map(function (t) { return t.label }).join(","), "Queue,Inbox,Agents,Work,Time")
        compare(S.TABS.map(function (t) { return t.key }).join(","), "queue,inbox,agents,work,time")
    }

    function test_filter() {
        var items = [it("a", "dm"), it("b", "review"), it("c", "task"), it("d", "blocker", { src: "agent" }),
                     it("e", "untracked"), it("f", "erp"), it("g", "alert")]
        function ids(t) { return S.filterTab(items, t).map(function (i) { return i.id }).join("") }
        compare(ids("queue"), "abcdefg")
        compare(ids("inbox"), "af")
        compare(ids("agents"), "d")
        compare(ids("work"), "bcd")
        compare(ids("time"), "e")
        compare(ids("nope"), "abcdefg")
        compare(S.filterTab(null, "queue").length, 0)
    }

    function test_mark() {
        compare(S.mark(it("a", "dm", { waiting: true })), "waiting")
        compare(S.mark(it("a", "alert")), "failed")
        compare(S.mark(it("a", "alert", { waiting: true })), "waiting")
        compare(S.mark(it("a", "task")), "")
    }

    function test_group() {
        var items = [
            it("t1", "task", { ageSec: 3 * 3600 }),
            it("w1", "dm", { waiting: true, ageSec: 540, urgency: "active" }),
            it("f1", "alert", { ageSec: 120, urgency: "critical" }),
            it("y1", "dm", { ageSec: 90000 }),
            it("a1", "dm", { ageSec: 7200, away: true }),
            it("r1", "review", { ageSec: 3600 })
        ]
        var rows = S.group(items)
        var heads = rows.filter(function (r) { return r.head }).map(function (r) { return r.head })
        compare(heads.join("|"), "WAITING ON YOU|TODAY|WHILE YOU WERE AWAY|FROM YESTERDAY")
        // critical alert ranks first; then oldest first within a rung
        compare(rows.filter(function (r) { return r.item }).map(function (r) { return r.item.id }).join(","), "f1,w1,t1,r1,a1,y1")
        compare(rows[0].head, "WAITING ON YOU")
        compare(rows[0].key, "head:waiting")
    }

    function test_group_skips_empty() {
        compare(S.group([]).length, 0)
        var rows = S.group([it("y", "dm", { ageSec: 100000 })])
        compare(rows.length, 2)
        compare(rows[0].head, "FROM YESTERDAY")
    }

    function test_src() {
        compare(S.srcLabel(it("a", "dm", { src: "slack" })), "Slack")
        compare(S.srcLabel(it("a", "review", { src: "gh" })), "GitHub")
        compare(S.srcLabel(it("a", "erp", { src: "erp" })), "ERP")
        compare(S.srcLabel(it("a", "blocker", { src: "agent" })), "Agent")
        compare(S.srcLabel(it("a", "alert", { src: "monitoring" })), "Alert")
        compare(S.srcLabel(it("a", "untracked", { src: "timetrack" })), "You")
        compare(S.srcLabel(it("a", "dm")), "")
    }

    function test_who_and_sub() {
        compare(S.srcKey(it("a", "dm", { src: "slack" })), "slack")
        compare(S.srcKey(it("a", "review", { src: "gh" })), "github")
        compare(S.srcKey(it("a", "alert")), "alert")
        compare(S.srcKey(it("a", "task")), "")
        compare(S.who(it("a", "dm", { actor: "Sam R." })), "Sam R.")
        compare(S.who(it("a", "dm")), "")
    }

    function test_pickTitle() {
        compare(S.pickTitle(null), "Pick an item")
        compare(S.pickTitle(it("a", "dm")), "t a")
    }

    function test_ccTab() {
        compare(S.ccTab("queue"), "queue")
        compare(S.ccTab("bogus"), "queue")
    }
}
