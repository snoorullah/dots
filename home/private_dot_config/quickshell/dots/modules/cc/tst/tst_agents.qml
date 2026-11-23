import QtQuick
import QtTest
import "../js/AgentMetrics.js" as A
import "../js/Metrics.js" as M
import "../js/Keys.js" as K

// js/AgentMetrics.js: Time > Agents and the Agents page cards. Made-up numbers only.
TestCase {
    name: "AgentMetrics"

    function tk(total) { return { in: 10, out: 1000, cacheWrite: 5000, cacheRead: total - 6010, total: total, msgs: 12 } }
    function days() {
        var out = []
        for (var i = 0; i < 40; i++) {
            var d = new Date(Date.UTC(2025, 9, 1 + i))
            var day = d.getUTCFullYear() + "-" + (d.getUTCMonth() < 9 ? "0" : "") + (d.getUTCMonth() + 1) + "-" + (d.getUTCDate() < 10 ? "0" : "") + d.getUTCDate()
            out.push({ day: day, runs: i % 3, prompts: i, activeMin: 10 * (i % 4), waitingMin: 5, tokens: tk(100000 * (i + 1)), costUsd: i % 5 === 4 ? null : 1.5 * (i + 1), subagentShare: 0.3 })
        }
        return out
    }
    function mk() {
        var pw = { first: "2025-10-24", last: "2025-10-30", runs: 8, prompts: 60, activeMin: 125, waitingMin: 300, tokens: tk(2380443872), costUsd: 1144.0333, subagentShare: 0.558, unpricedTokens: 0,
                   prev: { first: "2025-10-17", last: "2025-10-23", runs: 10, prompts: 50, activeMin: 100, waitingMin: 360, tokens: tk(2000000000), costUsd: 1939.1 },
                   delta: { runs: -2, prompts: 10, activeMin: 25, waitingMin: -60, tokens: 380443872, costUsd: -795.07 },
                   byAgent: [{ key: "Atlas", runs: 3, activeMin: 61, tokens: tk(861322223), costUsd: 268.3, models: ["claude-opus-5"] }, { key: "Vega", runs: 1, activeMin: 5, tokens: tk(1000), costUsd: null }],
                   byTicket: [{ key: "TASK-2026-00111", runs: 2, activeMin: 9, tokens: tk(5000), costUsd: 1 }, { key: "local:ab12", runs: 1, activeMin: 1, tokens: tk(500), costUsd: 0.1 },
                              { key: "HD 4398", runs: 1, activeMin: 1, tokens: tk(500), costUsd: 0.1 }, { key: "gh:acme/repo#7", runs: 1, activeMin: 1, tokens: tk(500), costUsd: 0.1 }],
                   byModel: [{ key: "claude-opus-5", tokens: tk(1005646837), costUsd: 307.36, priced: true }, { key: "claude-mystery", tokens: tk(10), costUsd: null, priced: false }] }
        return { v: 1, ts: 1761845000, today: "2025-10-30", costIsEstimate: true, days: days(), periods: { today: { first: "2025-10-30", last: "2025-10-30", runs: 2, prompts: 9, activeMin: 59, waitingMin: 0, tokens: tk(5000000), costUsd: 3.2, subagentShare: 0.1 }, week: pw, month: pw },
                 live: { agents: 5, byStatus: { working: 2, idle: 2, blocked: 1 }, needsYou: 1 } }
    }

    function test_parse() {
        compare(A.parse("").state, "missing"); compare(A.parse(null).state, "missing")
        compare(A.parse("{").state, "invalid"); compare(A.parse("[]").state, "invalid")
        compare(A.parse('{"v":2}').state, "version")
        compare(A.parse(JSON.stringify(mk())).state, "ok")
        verify(A.emptyText(A.parse("")).indexOf("agent-metrics.json") >= 0)
    }

    function test_number_text() {
        compare(A.tokens(NaN), "-"); compare(A.tokens(null), "-"); compare(A.tokens(undefined), "-")
        compare(A.tokens(950), "950"); compare(A.tokens(611400), "611.4K"); compare(A.tokens(196771173), "196.8M"); compare(A.tokens(2380443872), "2.38B")
        compare(A.money(null), "n/a"); compare(A.money(3.2), "$3.20"); compare(A.money(1144.0333), "$1,144"); compare(A.money(83.01), "$83")
        compare(A.cost(83.01, false), "est. $83"); compare(A.cost(83.01, true), "est. $83+"); compare(A.cost(null, false), "n/a")
        compare(A.dur(0.4), "0m"); compare(A.dur(39), "39m"); compare(A.dur(98.8), "1h 39m"); compare(A.dur(undefined), "-")
        compare(A.pct(0.3658), "37%"); compare(A.pct(undefined), "-")
    }

    function test_cards_week() {
        var c = A.kpiCards(mk(), "week")
        compare(c.map(function (x) { return x.key }).join(","), "runs,prompts,active,waiting,tokens,cost")
        compare(c[0].value, "8"); compare(c[0].delta, "−2"); compare(c[0].dir, "down"); compare(c[0].prev, "10")
        compare(c[2].value, "2h 05m"); compare(c[2].delta, "+25m"); compare(c[2].dir, "up")
        compare(c[3].tone, "good")           // less waiting on you is better
        compare(c[4].value, "2.38B"); compare(c[4].delta, "+380.4M"); compare(c[4].spark.length, 30)
        compare(c[5].value, "est. $1,144"); compare(c[5].note, "list price estimate")
        for (var i = 0; i < c.length; i++) verify(c[i].has, c[i].key)
    }

    function test_waiting_up_is_bad() {
        var d = mk(); d.periods.week.delta.waitingMin = 40
        compare(A.kpiCards(d, "week")[3].tone, "bad")
    }

    function test_null_cost_and_missing_prev_and_delta() {
        var d = mk()
        d.periods.week.costUsd = null; d.periods.week.unpricedTokens = 7
        delete d.periods.week.prev; delete d.periods.week.delta
        var c = A.kpiCards(d, "week")
        compare(c[5].has, false); compare(c[5].delta, ""); compare(c[5].spark.length, 30)   // days still have costs
        compare(c[0].delta, ""); compare(c[0].prev, ""); compare(c[0].dir, "flat"); compare(c[4].delta, "")
        verify(c[4].has)
        // the delta is rebuilt from prev when only delta was dropped
        d = mk(); delete d.periods.week.delta
        compare(A.kpiCards(d, "week")[0].delta, "−2")
        // an omitted period is no cards at all
        compare(A.kpiCards(d, "quarter").length, 0)
    }

    function test_floor_marks_cost() {
        var d = mk(); d.periods.week.unpricedTokens = 10
        compare(A.kpiCards(d, "week")[5].value, "est. $1,144+")
        compare(A.model(d, "week", {}).unpriced, 10)
    }

    function test_kind_bar() {
        var b = A.kindBar(mk(), "week")
        compare(b.segs.map(function (s) { return s.key }).join(","), "in,out,cacheWrite,cacheRead")
        var sum = 0
        b.segs.forEach(function (s) { sum += s.frac })
        verify(Math.abs(sum - 1) < 1e-9)
        verify(b.segs[3].frac > 0.99); compare(b.segs[3].pct, "100%"); compare(b.segs[0].pct, "")
        compare(A.kindBar({ periods: { week: { tokens: { in: 0, out: 0, cacheWrite: 0, cacheRead: 0, total: 0 } } } }, "week").segs.length, 0)
        compare(A.kindBar(null, "week").segs.length, 0)
    }

    function test_ticket_labels_use_the_shared_rule() {
        compare(A.ticketLabel("HD 4398", {}), "HD 4398")
        compare(A.ticketLabel("gh:acme/repo#7", {}), "repo#7")
        compare(A.ticketLabel("TASK-2026-00111", { "TASK-2026-00111": "HD 4401: Rotate the keys" }), "HD 4401 Rotate the keys")
        compare(A.ticketLabel("lane:TASK-2026-00111", { "TASK-2026-00111": "HD 4401: Rotate the keys" }), "HD 4401 Rotate the keys")
        compare(A.ticketLabel("TASK-2026-00999", {}), "Task"); compare(A.ticketLabel("local:ab12", {}), "Local task")
        compare(A.ticketLabel("", {}), "No ticket"); compare(A.ticketLabel(null, null), "No ticket")
        verify(!/TASK-|local:|lane:/.test(A.ticketLabel("TASK-2026-00111", {})))
    }

    function test_tables_and_nav_rows() {
        var m = A.model(mk(), "week", { "TASK-2026-00111": "HD 4401: Rotate the keys" })
        compare(m.nav.agents.length, 2); compare(m.nav.tickets.length, 4); compare(m.nav.models.length, 2)
        compare(m.nav.all.length, 8); compare(m.nav.tickets0, 2); compare(m.nav.models0, 6)
        compare(m.nav.agents[0].label, "Atlas"); compare(m.nav.agents[0].tokText, "861.3M"); compare(m.nav.agents[0].costText, "est. $268"); compare(m.nav.agents[0].activeText, "1h 01m")
        compare(m.nav.agents[1].costText, "n/a")
        compare(m.nav.tickets[0].label, "HD 4401 Rotate the keys")
        compare(m.nav.models[0].label, "opus-5"); compare(m.nav.models[1].costText, "no price")
        verify(m.nav.agents[0].share > 0.3 && m.nav.agents[0].share < 0.4)
        compare(m.nav.all[0].kind, "agent"); compare(m.nav.all[2].kind, "ticket"); compare(m.nav.all[6].kind, "model")
        // missing lists are empty, not errors
        var d = mk(); delete d.periods.week.byTicket; delete d.periods.week.byModel
        compare(A.model(d, "week", {}).nav.all.length, 2)
    }

    function test_daily_series() {
        var s = A.daily(mk(), 30)
        compare(s.days.length, 30); compare(s.tokens.length, 30); compare(s.cost.length, 30)
        compare(s.days[29], "2025-11-09"); verify(s.hasCost); verify(s.peakTok > 0)
        compare(s.cost[0] >= 0, true)
        var e = A.daily({ days: [{ day: "2025-10-30", tokens: tk(10), costUsd: null }] }, 30)
        compare(e.hasCost, false); compare(e.tokens[0], 10); compare(e.cost[0], 0)
        compare(A.daily(null, 30).days.length, 0)
    }

    function test_subagent_and_live() {
        compare(A.model(mk(), "week", {}).sub.text, "56%")
        var d = mk(); delete d.periods.week.subagentShare
        compare(A.model(d, "week", {}).sub.has, false)
        var l = A.live(mk())
        compare(l.has, true); compare(l.working, 2); compare(l.needs, 1); compare(l.idle, 2); compare(l.agents, 5)
        d = mk(); delete d.live
        compare(A.live(d).has, false); compare(A.live(null).has, false)
        d.live = { byStatus: {}, needsYou: 0, agents: 0 }
        compare(A.live(d).has, true); compare(A.live(d).working, 0)
    }

    function test_today_card() {
        var t = A.todayCard(mk())
        compare(t.has, true); compare(t.runs, "2"); compare(t.tokens, "5.0M"); compare(t.cost, "est. $3.20"); compare(t.active, "59m")
        var n = A.todayCard(null)
        compare(n.has, false); compare(n.tokens, "-"); compare(n.cost, "n/a")
        var d = mk(); d.periods.today.costUsd = null
        compare(A.todayCard(d).cost, "n/a"); compare(A.todayCard(d).tokens, "5.0M")
    }

    function test_away() {
        var gaps = [{ startTs: 1761800000, endTs: 1761801000, minutes: 16.7, day: "2025-10-30", category: "misc", label: "misc", answered: false, source: "deduction" },
                    { startTs: 1761900000, endTs: 1761901000, minutes: 61, day: "2025-10-31", category: "lunch", label: "Lunch", answered: true, source: "asked" },
                    { startTs: 1761700000, minutes: 3, answered: false, label: "" }, { bad: true }]
        var a = A.away(JSON.stringify({ v: 1, gaps: gaps }))
        compare(a.state, "ok"); compare(a.count, 3); compare(a.unanswered, 2)
        compare(a.rows[0].label, "Lunch"); compare(a.rows[0].answered, true); compare(a.rows[0].minText, "1h 01m")
        compare(a.rows[1].label, "Away"); compare(a.rows[1].answered, false); compare(a.rows[1].minText, "17m")
        verify(/^[A-Z][a-z]{2} \d{1,2} [A-Z][a-z]{2} \d\d:\d\d$/.test(a.rows[0].when), a.rows[0].when)
        compare(a.rows[0].minutes > a.rows[1].minutes, true)
        compare(A.away("").state, "missing"); compare(A.away("").has, false)
        compare(A.away('{"v":1,"gaps":[]}').has, false); compare(A.away('{"v":1,"gaps":[]}').state, "ok")
        compare(A.away('{"v":1}').state, "invalid")
    }

    function test_step_keys() {
        var s = { row: 0, period: 1 }
        compare(A.step(s, "move", 1, 8).row, 1); compare(A.step(s, "move", -1, 8).row, 0)
        compare(A.step({ row: 7, period: 1 }, "move", 1, 8).row, 7)
        compare(A.step(s, "bottom", 0, 8).row, 7); compare(A.step({ row: 5, period: 1 }, "top", 0, 8).row, 0)
        compare(A.step({ row: 3, period: 1 }, "page", 1, 8).row, 7)
        compare(A.step({ row: 3, period: 1 }, "period", 1, 8).period, 2); compare(A.step({ row: 3, period: 2 }, "period", 1, 8).period, 0)
        compare(A.step({ row: 3, period: 0 }, "period", -1, 8).period, 2); compare(A.step({ row: 3, period: 1 }, "period", 1, 8).row, 0)
        compare(A.step(s, "move", 1, 0).row, 0)
    }

    // ---- the keys in Metrics.js and Keys.js -----------------------------------------------------------
    function nav(sub, action, arg, rows) {
        return M.nav({ sub: sub, zone: "list", row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 }, action, arg, M.dims(null, { sub: sub }, { agents: rows }))
    }
    function test_nav_agents() {
        compare(M.subId("Agents"), "agents"); compare(M.subName("agents"), "Agents")
        compare(nav("agents", "primary", 0, 6).effect, "jump"); compare(nav("agents", "act.open", 0, 6).effect, "jump")
        compare(nav("agents", "move", 1, 6).st.row, 1); compare(nav("agents", "bottom", 0, 6).st.row, 5)
        compare(nav("agents", "move", 9, 6).st.row, 5)
        compare(nav("agents", "period", 1, 6).st.period, 2); compare(nav("agents", "period", -1, 6).st.period, 0)
        compare(M.dims(null, { sub: "agents" }, { agents: 0 }).rows, 1)
        compare(M.hints("agents", "list").length, 5)
    }
    function test_keys_agents() {
        var r = K.resolve({ key: 0, text: "o", shift: false, ctrl: false, alt: false }, { page: "time", sub: "agents", zone: "list", mode: "", kind: "", pending: "", filterActive: false })
        compare(r.action, "act.open")
        verify(K.helpRows({ page: "time", sub: "agents", zone: "list", mode: "" }).some(function (h) { return h.keys === "o" }))
        verify(K.helpRows({ page: "agents", sub: "today", zone: "list", mode: "" }).some(function (h) { return h.keys === "t" }))
        compare(K.nextSub("reminders", 1), "agents"); compare(K.nextSub("agents", 1), "today")
    }

    // ---- screen time coverage and tolerant days -----------------------------------------------------------
    function test_screen_cover() {
        var d = { periods: { week: { screenSec: { value: 100, days: 4, of: 5 } }, today: { screenSec: { value: 10, days: 1, of: 1 } }, month: { screenSec: { value: 5 } } } }
        compare(M.screenCover(d, "week"), "4 of 5 days"); compare(M.screenCover(d, "today"), "1 of 1 day"); compare(M.screenCover(d, "month"), "")
        compare(M.screenCover(null, "week"), "")
        var c = M.kpiCards(d, "week").filter(function (x) { return x.key === "screenSec" })[0]
        compare(c.note, "4 of 5 days"); compare(c.has, true)
        compare(M.kpiCards(d, "month").filter(function (x) { return x.key === "screenSec" })[0].note, "")
        compare(M.screenModel({ screen: { todayActiveSec: 60 }, periods: d.periods }).weekCover, "4 of 5 days")
    }

    function test_days_without_worked_min_do_not_break_the_view_model() {
        var doc = { v: 1, ts: 1761845000, today: "2025-10-30", days: [{ day: "2025-10-28", kind: "working" }, { day: "2025-10-29", kind: "working", targetMin: 480 }, { day: "2025-10-30", kind: "working", loginTs: 1761814500 }],
                    periods: { week: { workedMin: { value: 10 }, focusMin: { value: 5, prev: 3 }, deepWorkMin: 4 } } }
        var w = M.weekModel(doc, 0)
        compare(w.rows.length, 7); verify(isFinite(w.totalMin) || w.totalMin === undefined)
        var texts = []
        M.dayRows(doc).forEach(function (r) { texts.push(M.hm(r.workedMin), M.hm(r.focusMin)) })
        M.heatGrid(doc).cells.forEach(function (c) { verify(c.level >= 0 && c.level <= 4) })
        M.monthRows(doc, 5); M.weekRows(doc, 5); M.improve(doc); M.dayDetail(doc, "2025-10-30"); M.reportLines(doc, "week")
        M.kpiCards(doc, "week").forEach(function (c) { texts.push(c.value, c.delta, c.prev) })
        verify(texts.join("|").indexOf("NaN") < 0 && texts.join("|").indexOf("undefined") < 0, texts.join("|"))
        compare(M.kpiCards(doc, "week")[2].has, true); compare(M.kpiCards(doc, "week")[2].delta, "+0:02")
        compare(M.kpiCards(doc, "week")[0].delta, "")
    }
}
