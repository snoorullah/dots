import QtQuick
import QtTest
import "../js/Queue.js" as Q

TestCase {
    name: "Queue"

    readonly property int now: 1761600000
    readonly property int since: 1761592800   // 7200 s ago

    function feed() {
        return [
            { id: "a1", kind: "review", title: "Review the parser", ref: "gh:acme/widgets#12", src: "gh", urgency: "active", waiting: true, ageSec: 7200, actor: "grace", jump: { pane: "p1" }, url: "https://example.invalid/a1", canBreakdown: true },
            { id: "f1", kind: "alert", title: "Nightly sync failed", ref: "ops:sync", src: "ops", urgency: "critical", waiting: false, ageSec: 1800, actor: "cron", jump: null, url: null, canBreakdown: false },
            { id: "b1", kind: "dm", title: "Deploy window question", ref: "", src: "notif", urgency: "active", waiting: true, ageSec: 600, actor: "ada", jump: null, url: null, canBreakdown: false },
            { id: "b2", kind: "erp", title: "Ticket needs reply", ref: "HD-9", src: "erp", urgency: "time", waiting: false, ageSec: 90000, actor: "client", jump: null, url: null, canBreakdown: false },
            { id: "g1", kind: "blocker", title: "Agent stopped", ref: "", src: "herdr", urgency: "active", waiting: true, ageSec: 700, actor: "billing", jump: { pane: "p2" }, url: null, canBreakdown: false },
            { id: "t1", kind: "task", title: "Tidy backlog", ref: "HD-12", src: "gh", urgency: "passive", waiting: false, ageSec: 600, actor: "ada", jump: null, url: null, canBreakdown: true },
            { id: "m1", kind: "mail", title: "Advisory", ref: "", src: "mail", urgency: "passive", waiting: false, ageSec: 100, actor: "vendor", jump: null, url: null, canBreakdown: false },
            { id: "u1", kind: "untracked", title: "2h on alpha, no ticket", ref: null, src: "timetrack", urgency: "passive", waiting: false, ageSec: 400, actor: null, jump: null, url: null, canBreakdown: false },
            { id: "o1", kind: "dm", title: "Older note", ref: "", src: "notif", urgency: "passive", waiting: false, ageSec: 20000, actor: "sam", jump: null, url: null, canBreakdown: false }
        ]
    }

    function byId(list, id) {
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }

    function test_fromFeed_drops_tasks_and_mail() {
        var l = Q.fromFeed(feed(), now, since)
        compare(l.length, 7)
        verify(byId(l, "t1") === null)
        verify(byId(l, "m1") === null)
    }

    function test_fromFeed_maps_kind_src_tone() {
        var l = Q.fromFeed(feed(), now, since)
        var a = byId(l, "a1")
        compare(a.kind, "pr"); compare(a.src, "GitHub"); compare(a.tone, "wait"); compare(a.who, "grace")
        var f = byId(l, "f1")
        compare(f.kind, "alert"); compare(f.src, "Alert"); compare(f.tone, "fail")
        compare(byId(l, "b1").src, "Slack")
        compare(byId(l, "b2").src, "ERP")
        compare(byId(l, "g1").kind, "agent")
        compare(byId(l, "g1").src, "Agent")
        compare(byId(l, "u1").kind, "capture")
        compare(byId(l, "u1").who, "You")
    }

    function test_sections() {
        var l = Q.fromFeed(feed(), now, since)
        compare(byId(l, "a1").sec, "WAITING ON YOU")
        compare(byId(l, "f1").sec, "WAITING ON YOU")      // failed also needs you
        compare(byId(l, "b2").sec, "FROM YESTERDAY")      // 25 h old, not waiting
        compare(byId(l, "o1").sec, "WHILE YOU WERE AWAY") // arrived before this stretch began
        compare(byId(l, "u1").sec, "TODAY")
    }

    function test_sections_without_clock_use_today() {
        var l = Q.fromFeed(feed(), now, 0)
        compare(byId(l, "o1").sec, "TODAY")
    }

    function test_src_icon() {
        compare(Q.srcIcon("GitHub"), "git-pull-request")
        compare(Q.srcIcon("nope"), "funnel")
    }

    function test_age_text() {
        compare(Q.age(30), "now")
        compare(Q.age(720), "12m")
        compare(Q.age(7200), "2h")
        compare(Q.age(90000), "1d")
    }

    function test_clock() {
        var t = new Date(2026, 10, 20, 17, 4, 17).getTime() / 1000
        compare(Q.clock(t), "17:04")
        compare(Q.clock(new Date(2026, 10, 20, 9, 5, 0).getTime() / 1000), "09:05")
    }
    function test_hm() {
        compare(Q.hm(0), "0:00")
        compare(Q.hm(6120), "1:42")
        compare(Q.hm(-4), "0:00")
        compare(Q.hm(NaN), "0:00")
    }

    function test_group_urgency_fixed_order() {
        var l = Q.fromFeed(feed(), now, since)
        var g = Q.group(l, "Urgency")
        var names = g.map(function (s) { return s.name })
        compare(names.join("|"), "WAITING ON YOU|TODAY|WHILE YOU WERE AWAY|FROM YESTERDAY")
        compare(g[0].count, 4)
    }

    function test_sort_in_section_urgency_then_age() {
        var l = Q.fromFeed(feed(), now, since)
        var g = Q.group(l, "Urgency")
        // critical alert first, then active ones by longest wait
        compare(g[0].items[0].id, "f1")
        compare(g[0].items[1].id, "a1")
        compare(g[0].items[2].id, "g1")
        compare(g[0].items[3].id, "b1")
    }

    function test_group_source_and_person() {
        var l = Q.fromFeed(feed(), now, since)
        var s = Q.group(l, "Source")
        verify(s.some(function (x) { return x.name === "SLACK" && x.count === 2 }))
        var p = Q.group(l, "Person")
        verify(p.some(function (x) { return x.name === "ADA" && x.count === 1 }))
        verify(p.some(function (x) { return x.name === "YOU" }))
    }

    function test_select_tab_inbox_drops_agents() {
        var l = Q.fromFeed(feed(), now, since)
        var q = Q.select(l, { tab: "queue", src: "All", view: "", hidden: {} })
        var i = Q.select(l, { tab: "inbox", src: "All", view: "", hidden: {} })
        compare(q.length, 7)
        compare(i.length, 6)
        verify(byId(i, "g1") === null)
    }

    function test_select_source_filter() {
        var l = Q.fromFeed(feed(), now, since)
        var s = Q.select(l, { tab: "queue", src: "Slack", view: "", hidden: {} })
        compare(s.length, 2)
    }

    function test_select_hidden_and_snoozed_view() {
        var l = Q.fromFeed(feed(), now, since)
        var hid = { a1: "done", b1: "snoozed" }
        var q = Q.select(l, { tab: "queue", src: "All", view: "", hidden: hid })
        compare(q.length, 5)
        var sn = Q.select(l, { tab: "queue", src: "All", view: "Snoozed", hidden: hid })
        compare(sn.length, 1)
        compare(sn[0].id, "b1")
    }

    function test_select_overdue_view() {
        var l = Q.fromFeed(feed(), now, since)
        var o = Q.select(l, { tab: "queue", src: "All", view: "Overdue", hidden: {} })
        var ids = o.map(function (x) { return x.id }).sort().join(",")
        compare(ids, "b2,f1")
    }

    function test_counts() {
        var l = Q.fromFeed(feed(), now, since)
        var c = Q.counts(l, {})
        compare(c.queue, 7)
        compare(c.inbox, 6)
    }

    function test_neighbour_wraps_never() {
        var ids = [{ id: "x" }, { id: "y" }, { id: "z" }]
        compare(Q.neighbour(ids, "x", 1), "y")
        compare(Q.neighbour(ids, "z", 1), "z")
        compare(Q.neighbour(ids, "x", -1), "x")
        compare(Q.neighbour(ids, "", 1), "x")
        compare(Q.neighbour([], "x", 1), "")
    }

    function test_after_dismiss_pick_next() {
        var ids = [{ id: "x" }, { id: "y" }, { id: "z" }]
        compare(Q.afterRemoval(ids, "y"), "z")
        compare(Q.afterRemoval(ids, "z"), "y")
        compare(Q.afterRemoval([{ id: "x" }], "x"), "")
    }

    function test_actions_pr_and_remote_flags() {
        var a = Q.actionsFor("pr")
        compare(a[0].label, "Open review")
        verify(a[0].primary)
        verify(!a[0].remote)
        var agent = Q.actionsFor("agent")
        compare(agent[0].label, "Allow once")
        verify(agent[0].remote)             // answering an agent writes elsewhere
        verify(agent[2].label === "Open pane" && !agent[2].remote)
    }

    function test_every_kind_gets_common_tail() {
        var kinds = ["agent", "msg", "alert", "pr", "ticket", "mail", "capture"]
        for (var i = 0; i < kinds.length; i++) {
            var a = Q.actionsFor(kinds[i])
            var n = a.length
            compare(a[n - 2].label, "Break down & start")
            compare(a[n - 1].label, "Jump")
            // exactly one primary
            compare(a.filter(function (x) { return x.primary }).length, 1)
        }
    }

    function test_actions_keys_unique_per_kind() {
        var kinds = ["agent", "msg", "alert", "pr", "ticket", "mail", "capture"]
        for (var i = 0; i < kinds.length; i++) {
            var seen = {}
            Q.actionsFor(kinds[i]).forEach(function (x) { verify(!seen[x.key], kinds[i] + " dup " + x.key); seen[x.key] = 1 })
        }
    }

    function test_unknown_kind_has_only_tail() {
        var a = Q.actionsFor("nope")
        compare(a.length, 2)
    }

    function test_resolve_action_effects() {
        compare(Q.statusFor("Queue", "x"), "Queued. Hidden for this session.")
        compare(Q.statusFor("Dismiss", "x"), "Dismissed.")
        compare(Q.statusFor("Snooze", "Tonight"), "Snoozed: tonight. It stays listed under Snoozed.")
    }

    function test_time_rows_scale_to_longest() {
        var r = Q.timeRows({ byProject: [{ project: "a", sec: 9000 }, { project: "b", sec: 4500 }] }, "Project")
        compare(r.length, 2)
        compare(r[0].n, "a"); compare(r[0].v, "2:30"); compare(r[0].w, 100)
        compare(r[1].w, 50)
    }

    function test_time_rows_item_uses_title_or_ref() {
        var r = Q.timeRows({ byRef: [{ ref: "HD-1", title: "Fix it", sec: 600 }, { ref: "HD-2", title: "", sec: 300 }] }, "Item")
        compare(r[0].n, "HD-1 Fix it")
        compare(r[1].n, "HD-2")
    }

    function test_time_rows_missing_bucket() {
        compare(Q.timeRows(null, "App").length, 0)
        compare(Q.timeRows({}, "Agent").length, 0)
    }

    function test_agents_rows() {
        var items = Q.fromFeed(feed(), now, since)
        var rows = Q.agentRows(items, { name: "runner", status: "Working", pane: "p9" }, [{ agent: "Vega", sec: 3600 }])
        compare(rows[0].state, "Waiting on you")
        compare(rows[0].name, "billing")
        compare(rows[0].tone, "wait")
        var names = rows.map(function (r) { return r.name })
        verify(names.indexOf("runner") >= 0)
        verify(names.indexOf("Vega") >= 0)
        compare(rows[rows.length - 1].name, "Vega")
        compare(rows[rows.length - 1].state, "Ran today")
    }

    function test_sources_rows_hide_nothing_green() {
        var rows = Q.sourceRows({ gh: { state: "ok" }, erp: { state: "off" }, mail: { state: "unavailable" }, ops: { state: "stale" } })
        var gh = rows.filter(function (r) { return r.name === "GitHub" })[0]
        compare(gh.label, "live")
        compare(rows.filter(function (r) { return r.name === "ERP" })[0].label, "off")
        compare(rows.filter(function (r) { return r.name === "Mail" })[0].label, "unavailable")
        compare(rows.filter(function (r) { return r.name === "Alerts" })[0].label, "stale")
    }

    function test_heat_totals() {
        var h = Q.heatTotals([{ d: "2025-07-01", workedSec: 0 }, { d: "2025-07-02", workedSec: 3600 }, { d: "2025-07-03", workedSec: 7200 }])
        compare(h.totalSec, 10800)
        compare(h.daysWorked, 2)
        compare(h.avgSec, 5400)
        compare(h.best.d, "2025-07-03")
        compare(Q.heatTotals(null).best, null)
    }

    function test_time_rows_item_without_ref() {
        var r = Q.timeRows({ byRef: [{ ref: "", title: "No ticket: observability", sec: 60 }] }, "Item")
        compare(r[0].n, "No ticket: observability")
    }
}
