import QtQuick
import QtTest
import "../js/Model.js" as Model

TestCase {
    name: "Model"

    function doc(extra) {
        var o = { v: 1, ts: 1000 }
        for (var k in extra) o[k] = extra[k]
        return JSON.stringify(o)
    }

    // ---- validation / staleness ----
    function test_parseDoc_statuses() {
        compare(Model.parseDoc(null, 1000).status, "missing")
        compare(Model.parseDoc("", 1000).status, "missing")
        compare(Model.parseDoc("  \n", 1000).status, "missing")
        compare(Model.parseDoc("{not json", 1000).status, "bad")
        compare(Model.parseDoc("[1]", 1000).status, "bad")
        compare(Model.parseDoc("3", 1000).status, "bad")
        compare(Model.parseDoc(doc({ v: 2 }), 1000).status, "version")
        compare(Model.parseDoc(doc({ v: 2 }), 1000).doc, null)
        compare(Model.parseDoc(JSON.stringify({ ts: 1000 }), 1000).status, "version")   // no v at all
        compare(Model.parseDoc(doc({}), 1000).status, "ok")
        compare(Model.parseDoc(doc({}), 1180).status, "ok")        // exactly 180 s is still fresh
        compare(Model.parseDoc(doc({}), 1181).status, "stale")
        compare(Model.parseDoc(doc({}), 1600).status, "stale")
        compare(Model.parseDoc(doc({}), 1600).ageSec, 600)
        compare(Model.parseDoc(JSON.stringify({ v: 1 }), 1000).status, "stale")           // no ts
        compare(Model.parseDoc(doc({}), 900).status, "ok")         // clock skew: future ts is not stale
    }

    function test_stale_keeps_doc_for_dimmed_numbers() {
        verify(Model.parseDoc(doc({ x: 1 }), 5000).doc !== null)
        compare(Model.parseDoc(doc({ x: 1 }), 5000).doc.x, 1)
    }

    function test_isDegraded() {
        verify(Model.isDegraded("stale"))
        verify(Model.isDegraded("version"))
        verify(Model.isDegraded("bad"))
        verify(!Model.isDegraded("ok"))
        verify(!Model.isDegraded("missing"))
    }

    // ---- urgency ----
    function test_sortItems_urgency_then_waiting_then_age() {
        var items = [
            { id: "a", urgency: "passive", waiting: true, ageSec: 9999 },
            { id: "b", urgency: "critical", waiting: false, ageSec: 1 },
            { id: "c", urgency: "active", waiting: false, ageSec: 500 },
            { id: "d", urgency: "active", waiting: true, ageSec: 10 },
            { id: "e", urgency: "active", waiting: true, ageSec: 400 },
            { id: "f", urgency: "time", waiting: false, ageSec: 1 },
            { id: "g", urgency: "bogus", waiting: false, ageSec: 0 }
        ]
        var order = Model.sortItems(items).map(function (i) { return i.id }).join("")
        compare(order, "bfedcag")
        compare(items[0].id, "a")      // input untouched
        compare(Model.sortItems(null).length, 0)
    }

    function test_splitItems_drops_mail_and_separates_tasks() {
        var s = Model.splitItems([
            { id: "m", kind: "mail", urgency: "critical" },
            { id: "t1", kind: "task", urgency: "passive" },
            { id: "t2", kind: "task", urgency: "time" },
            { id: "r", kind: "review", urgency: "active", waiting: true }
        ])
        compare(s.next.map(function (i) { return i.id }).join(), "t2,t1")
        compare(s.attention.map(function (i) { return i.id }).join(), "r")
    }

    function test_counts() {
        var c = Model.counts({ items: [
            { kind: "review", waiting: true }, { kind: "blocker", waiting: true },
            { kind: "alert", waiting: false }, { kind: "alert", waiting: true },
            { kind: "task", waiting: false }, { kind: "mail", waiting: true }
        ] })
        compare(c.waiting, 3)       // the waiting alert counts as amber, mail never counts
        compare(c.failed, 1)
        compare(c.total, 4)
        compare(Model.counts(null).total, 0)
        compare(Model.counts({}).waiting, 0)
    }

    // ---- pill ----
    function test_pillState_priority() {
        var run = { state: "running" }
        compare(Model.pillState(run, { waiting: 2, failed: 1 }, true).kind, "focus")
        compare(Model.pillState({ state: "idle" }, { waiting: 2, failed: 1 }, true).kind, "failed")
        compare(Model.pillState(null, { waiting: 2, failed: 0 }, true).kind, "waiting")
        compare(Model.pillState(null, { waiting: 0, failed: 0 }, true).kind, "stale")
        compare(Model.pillState(null, { waiting: 0, failed: 0 }, false).kind, "none")
        compare(Model.pillState({ state: "break" }, { waiting: 0, failed: 0 }, false).kind, "none")
    }

    // ---- onset coalescing ----
    function test_onset_coalesces_to_one_per_ten_minutes() {
        var t0 = 1000000
        var a = Model.onset(0, t0)
        verify(a.fire); compare(a.last, t0)
        var b = Model.onset(a.last, t0 + 60000)           // 1 min later
        verify(!b.fire); compare(b.last, t0)              // timestamp does not slide
        var c = Model.onset(b.last, t0 + 599999)
        verify(!c.fire)
        var d = Model.onset(c.last, t0 + 600000)          // exactly 10 min
        verify(d.fire); compare(d.last, t0 + 600000)
        verify(Model.onset(5, 100, 50).fire)              // custom gap
        verify(!Model.onset(80, 100, 50).fire)
    }

    // ---- focus ----
    function test_toEpoch() {
        compare(Model.toEpoch(1761600000), 1761600000)
        compare(Model.toEpoch(1761600000000), 1761600000)    // ms input
        compare(Model.toEpoch("2025-10-27T22:40:00Z"), 1761604800)
        compare(Model.toEpoch(null), 0)
        compare(Model.toEpoch("junk"), 0)
    }

    function test_focusElapsed() {
        var f = { state: "running", startedAt: 1000, elapsedSec: 5, targetSec: 1500 }
        compare(Model.focusElapsed(f, 1300), 300)             // derived from startedAt
        compare(Model.focusElapsed(f, 9999), 1500)            // clamped to target
        compare(Model.focusElapsed(f, 500), 0)                // clock behind start
        compare(Model.focusElapsed({ state: "idle", elapsedSec: 42, targetSec: 1500 }, 9999), 42)
        compare(Model.focusElapsed({ state: "running", elapsedSec: 77, targetSec: 1500 }, 5), 77)   // no startedAt
        compare(Model.focusElapsed(null, 5), 0)
    }

    function test_ringAngle() {
        compare(Model.ringAngle(0, 1500), 0)
        compare(Model.ringAngle(375, 1500), 90)
        compare(Model.ringAngle(750, 1500), 180)
        compare(Model.ringAngle(1500, 1500), 360)
        compare(Model.ringAngle(9000, 1500), 360)
        compare(Model.ringAngle(10, 0), 0)
        compare(Model.ringAngle(-4, 1500), 0)
    }
}
