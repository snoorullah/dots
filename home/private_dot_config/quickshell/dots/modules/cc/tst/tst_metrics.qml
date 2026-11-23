import QtQuick
import QtTest
import "../js/Metrics.js" as M
import "../js/Keys.js" as K

// js/Metrics.js: the Time sub-tab view-model. Made-up numbers only. The doc below is 17 days
// ending Thursday 2025-10-30: two weeks of Monday to Friday work with a weekend, a holiday and
// one day left out of the file.
TestCase {
    name: "Metrics"

    function day(d, worked, extra) {
        var o = { day: d, kind: "working", targetMin: 480, workedMin: worked, spanMin: worked + 40, deductionMin: 40, focusMin: Math.round(worked * 0.6),
                  deepWorkMin: Math.round(worked * 0.3), tasksDone: 2, loginTs: 1761814500, logoutTs: 1761844740 }
        for (var k in extra) o[k] = extra[k]
        return o
    }
    function off(d, kind) { return { day: d, kind: kind, targetMin: 0, workedMin: 0, deductionMin: 0, focusMin: 0 } }
    function mk() {
        var days = [
            off("2025-10-14", "weekend"),   // not Monday: the first week is partial on purpose
            day("2025-10-15", 400), day("2025-10-16", 420), day("2025-10-17", 450), off("2025-10-18", "weekend"), off("2025-10-19", "weekend"),
            day("2025-10-20", 480), day("2025-10-21", 470), day("2025-10-22", 500), day("2025-10-23", 300), off("2025-10-24", "holiday"),
            off("2025-10-25", "weekend"), off("2025-10-26", "weekend"),
            day("2025-10-27", 510), day("2025-10-28", 490), day("2025-10-29", 480), day("2025-10-30", 450, { breaks: { walk: 15, lunch: 25 } })
        ]
        var kp = function (v, p) { return { value: v, prev: p, delta: v - p } }
        return {
            v: 1, ts: 1761845000, tz: "UTC", today: "2025-10-30", days: days,
            periods: { week: { workedMin: kp(1930, 1700), breakMin: kp(160, 100), contextSwitches: kp(80, 90), attainmentPct: kp(100, 90), daysWorked: kp(4, 4),
                               topProjects: [{ project: "alpha", min: 600 }, { project: "beta", min: 300 }] },
                       today: { workedMin: kp(450, 480) } },
            improve: { trend7: { workedMin: 12.5, focusMin: 0, deepWorkRatioPct: -0.4, dir: { workedMin: "up", focusMin: "flat", deepWorkRatioPct: "down" } },
                       trend30: { workedMin: 3, dir: { workedMin: "up" } },
                       streaks: { targetMet: 3, onTimeLogin: 0, best: { targetMet: 7, onTimeLogin: 5 } },
                       punctuality: { targetLoginMin: 540, avgLateMin: 6.5, onTimeDays: 8, days: 12 },
                       deepWorkRatioPct: { d7: 31.2, d30: 28 }, interruptionsPerHour: { d7: 1.4 }, bestDay: { day: "2025-10-27", workedMin: 510 }, worstDay: { day: "2025-10-23", workedMin: 300 } },
            zones: { current: { zone: "Alpha", state: "running" },
                     byDay: { "2025-10-29": [{ zone: "Alpha", min: 200 }, { zone: "Beta", min: 100 }], "2025-10-30": [{ zone: "Alpha", min: 150 }, { zone: "Gamma", min: 90 }],
                              "2025-10-20": [{ zone: "Beta", min: 60 }] },
                     byWeek: [{ week: "2025-10-20", zones: [{ zone: "Alpha", min: 400 }] }, { week: "2025-10-27", zones: [{ zone: "Beta", min: 90 }, { zone: "Alpha", min: 350 }] }],
                     projects: [{ project: "p1", min: 100, agentMin: 25 }, { project: "p2", min: 300, agentMin: 30 }] },
            screen: { todayActiveSec: 18000, todayIdleSec: 6000, weekActiveSec: 90000, lateNightSec: 4000, longestStretchMin: 130,
                      bySession: [{ openTs: 1761814500, closeTs: null, activeSec: 7200 }] },
            health: { checkpoints: [{ day: "2025-10-29", slot: "dose", score: 5, outcome: "answered" }, { day: "2025-10-30", slot: "dose", score: 6, outcome: "answered" },
                                    { day: "2025-10-30", slot: "h1", outcome: "pending" }], scoreAvg7: 5.5, doses: [{ day: "2025-10-30", ts: 1761814800 }], doseToFirstCheckpointMin: 60 },
            reminders: { due: [{ id: "a", desc: "Past one", due: 1761840000, overdue: true }, { id: "b", desc: "Soon one", due: 1761850000, overdue: false }],
                         scheduled: [{ id: "c", desc: "Later one", scheduled: 1762000000 }], salahNext: { prayer: "Asr", iqamahTs: 1761848000 } },
            sources: { zones: { state: "ok", reason: "" }, screen: { state: "missing", reason: "ActivityWatch unreachable on localhost" } }
        }
    }

    // ---- file --------------------------------------------------------------------------
    function test_parse_states() {
        compare(M.parse("", 10).state, "missing")
        compare(M.parse(null, 10).state, "missing")
        compare(M.parse("{nope", 10).state, "invalid")
        compare(M.parse("[1]", 10).state, "invalid")
        var hi = M.parse('{"v":2}', 10)
        compare(hi.state, "version"); compare(hi.doc, null)
        var ok = M.parse(JSON.stringify(mk()), 1761845300)
        compare(ok.state, "ok"); compare(ok.ageSec, 300)
        compare(M.parse('{"v":1,"ts":500}', 100).ageSec, 0)      // a clock that ran ahead is not negative
        verify(M.isStale({ state: "ok", ageSec: 601 })); verify(!M.isStale({ state: "ok", ageSec: 60 }))
    }

    function test_empty_text_names_the_source() {
        verify(M.emptyText({ state: "missing" }, "days").indexOf("metrics.json") >= 0)
        verify(M.emptyText({ state: "invalid" }, "days").indexOf("not valid JSON") >= 0)
        verify(M.emptyText({ state: "version", v: 3 }, "days").indexOf("version 3") >= 0)
        var p = M.parse(JSON.stringify(mk()), 0)
        var t = M.emptyText(p, "screen")
        verify(t.indexOf("ActivityWatch on localhost:5600") >= 0, t)
        verify(t.indexOf("ActivityWatch unreachable on localhost.") >= 0, "the daemon's own reason is appended: " + t)
        verify(M.emptyText(p, "health").indexOf("private.db") >= 0)
        verify(M.emptyText(p, "reminders").indexOf("Taskwarrior") >= 0)
        verify(M.emptyText(p, "days").indexOf("work.db") >= 0)
    }

    function test_present_rejects_empty_days() {
        verify(M.present(mk(), "days")); verify(!M.present({ days: [] }, "days")); verify(!M.present({}, "zones"))
    }

    // ---- formats ---------------------------------------------------------------------------
    function test_formats() {
        compare(M.hm(0), "0:00"); compare(M.hm(125), "2:05"); compare(M.hm(undefined), "-"); compare(M.hm(NaN), "-")
        compare(M.signedHm(90), "+1:30"); compare(M.signedHm(-5), "−0:05"); compare(M.signedHm(0), "0:00")
        compare(M.hmSec(3660), "1:01"); compare(M.pct(91.6), "92%"); compare(M.clockMin(545), "09:05"); compare(M.clockMin(1500), "01:00")
        compare(M.fmtDelta("pct", 3.25), "+3.3 pts"); compare(M.fmtDelta("count", -4), "−4"); compare(M.fmt("count", 3.6), "4")
        compare(M.dirOf(3), "up"); compare(M.dirOf(-1), "down"); compare(M.dirOf(0), "flat"); compare(M.dirOf(undefined), "flat")
        compare(M.toneOf(5, 1), "good"); compare(M.toneOf(5, -1), "bad"); compare(M.toneOf(5, 0), "neutral"); compare(M.toneOf(0, 1), "neutral")
        compare(M.ago(30), "just now"); compare(M.ago(600), "10 min ago"); compare(M.ago(7300), "2 h ago")
    }

    function test_dates() {
        compare(M.dow("2025-10-27"), 0); compare(M.dow("2025-10-30"), 3); compare(M.dow("2025-11-02"), 6)
        compare(M.weekStart("2025-10-30"), "2025-10-27"); compare(M.addDays("2025-10-30", 3), "2025-11-02"); compare(M.addDays("2025-03-01", -1), "2025-02-28")
        compare(M.dayLabel("2025-10-30"), "Thu 30 Oct"); compare(M.monthLabel("2025-09"), "Sep 2025")
    }

    // ---- Week -------------------------------------------------------------------------------
    function test_week_rows_and_totals() {
        var w = M.weekModel(mk(), 0)
        compare(w.start, "2025-10-27"); compare(w.rows.length, 7)
        compare(w.rows[0].label, "Mon"); verify(w.rows[3].isToday); verify(w.rows[4].future && !w.rows[4].has)
        compare(w.totalMin, 510 + 490 + 480 + 450)
        // four days done, Friday still to come at the usual target
        compare(w.targetMin, 5 * 480)
        compare(w.leftMin, 5 * 480 - 1930)
        verify(w.rows[0].met); verify(!w.rows[3].met)
        // the same four days last week: 480 + 470 + 500 + 300
        compare(w.prevMin, 1750); compare(w.deltaMin, 180)
        verify(w.deltaPct > 10 && w.deltaPct < 11)
        compare(w.targetLineMin, 480); verify(w.maxMin >= 540 && w.maxMin % 60 === 0)
    }

    function test_week_stacks_by_zone_and_never_exceeds_the_day() {
        var w = M.weekModel(mk(), 0)
        var wed = w.rows[2]
        compare(wed.segs.length, 2)
        var sum = wed.restMin
        for (var i = 0; i < wed.segs.length; i++) sum += wed.segs[i].min
        fuzzyCompare(sum, wed.workedMin, 0.01)
        compare(w.legend[0].zone, "Alpha"); compare(w.legend[0].slot, 0)
        // zone minutes above the day's worked time are scaled down, not drawn past the bar
        var d = mk(); d.days[d.days.length - 1].workedMin = 100
        var t = M.weekModel(d, 0).rows[3], s = t.restMin
        for (var j = 0; j < t.segs.length; j++) s += t.segs[j].min
        fuzzyCompare(s, 100, 0.01)
    }

    function test_week_offset_and_history() {
        var w = M.weekModel(mk(), -1)
        compare(w.start, "2025-10-20"); verify(!w.isCurrent)
        compare(w.totalMin, 480 + 470 + 500 + 300)
        compare(w.rows[4].kind, "holiday")
        compare(M.weeksAvailable(mk()), 3)
        verify(!M.weekModel({ days: [], today: "2025-10-30" }, 0).anyData)
    }

    // ---- Days -------------------------------------------------------------------------------
    function test_day_rows_newest_first_with_spark() {
        var r = M.dayRows(mk())
        compare(r.length, 17); compare(r[0].day, "2025-10-30"); verify(r[0].isToday); compare(r[16].day, "2025-10-14")
        compare(r[0].spark.length, 14); compare(r[0].spark[13], 450)
        verify(r[0].ratio < 1); verify(r[3].ratio >= 1)
        compare(r[0].working, true); compare(r[4].kind, "weekend") ; compare(r[4].working, false)
        compare(M.kindText("leave_paid"), "paid leave")
    }

    function test_day_detail_groups_and_missing_values() {
        var d = M.dayDetail(mk(), "2025-10-30")
        compare(d.title, "Thu 30 Oct")
        var caps = d.groups.map(function (g) { return g.cap })
        verify(caps.indexOf("SESSION") >= 0 && caps.indexOf("BREAKS") >= 0 && caps.indexOf("FOCUS ZONES") >= 0)
        var br = d.groups[caps.indexOf("BREAKS")].rows
        compare(br[0].k, "lunch"); compare(br[0].v, "0:25")
        // screen time was not in this day: the row says so instead of showing 0
        var habits = d.groups[caps.indexOf("HABITS")].rows
        compare(habits[1].v, "no data"); verify(habits[1].dim)
        compare(M.dayDetail(mk(), "1999-01-01"), null)
    }

    // ---- Heatmap and months -----------------------------------------------------------------------
    function test_heat_grid() {
        var g = M.heatGrid(mk())
        compare(g.cols, 3); compare(g.cells.length, 21); compare(g.days, 17)
        compare(g.cells[0].day, "2025-10-13"); verify(g.cells[0].empty)
        compare(g.cells[7 * 2 + 3].day, "2025-10-30"); compare(g.cells[7 * 2 + 3].level, 3)   // 450 of 480
        compare(g.cells[7 * 1 + 3].level, 2)   // 300 of 480 is 62%
        compare(M.level({ workedMin: 0, targetMin: 480 }), 0); compare(M.level({ workedMin: 100, targetMin: 480 }), 1)
        compare(M.level({ workedMin: 400, targetMin: 480 }), 3); compare(M.level({ workedMin: 480, targetMin: 480 }), 4)
        verify(g.months.length >= 1); compare(g.months[0].label, "Oct")
        var s = { sub: "heatmap", col: 2, row: 3, weekOff: 0 }
        compare(M.cursorDay(mk(), s), "2025-10-30")
        var c = M.initCursor(mk(), "heatmap", 0)
        compare(c.col, 2); compare(c.row, 3)
        compare(M.initCursor(mk(), "week", 0).col, 3)
    }

    function test_month_rows() {
        var m = M.monthRows(mk(), 5)
        compare(m.length, 1); compare(m[0].label, "Oct 2025"); compare(m[0].daysWorked, 11)
        compare(m[0].workedMin, 400 + 420 + 450 + 480 + 470 + 500 + 300 + 510 + 490 + 480 + 450)
        verify(m[0].attainmentPct > 0 && m[0].partial)
    }

    function test_week_rows_against_the_week_before() {
        var w = M.weekRows(mk(), 8)
        compare(w.length, 3); compare(w[0].week, "2025-10-27"); verify(w[0].partial)
        compare(w[1].week, "2025-10-20"); compare(w[1].workedMin, 1750); compare(w[1].deltaMin, 1750 - 1270)
    }

    // ---- KPI cards ---------------------------------------------------------------------------------
    function test_kpi_cards() {
        var c = M.kpiCards(mk(), "week")
        compare(c.length, M.KPI.length)
        var by = {}
        c.forEach(function (k) { by[k.key] = k })
        compare(by.workedMin.value, "32:10"); compare(by.workedMin.prev, "28:20"); compare(by.workedMin.delta, "+3:50"); compare(by.workedMin.dir, "up"); compare(by.workedMin.tone, "good")
        compare(by.contextSwitches.delta, "−10"); compare(by.contextSwitches.dir, "down"); compare(by.contextSwitches.tone, "good")   // fewer switches is better
        compare(by.breakMin.tone, "neutral")
        // a KPI the file does not carry says so
        verify(!by.screenSec.has); compare(by.screenSec.value, "")
        verify(by.workedMin.spark.length >= 10)
        compare(M.kpiCards(mk(), "quarter").filter(function (k) { return k.has }).length, 0)
        compare(M.cardAt(c, { row: 0, col: 1 }).key, "attainmentPct")
    }

    function test_spark_is_working_days_only() {
        var s = M.spark(mk(), "workedMin", 30)
        compare(s.length, 11)
        verify(s.every(function (v) { return v > 0 }))
        compare(M.spark(mk(), "screenSec", 30).length, 0)
    }

    // ---- improvement ----------------------------------------------------------------------------------
    function test_improve() {
        var im = M.improve(mk())
        compare(im.trends[0].cells[0].dir, "up"); compare(im.trends[0].cells[0].slope, "+0:13 a day"); compare(im.trends[0].cells[0].tone, "good")
        compare(im.trends[1].cells[0].dir, "flat"); compare(im.trends[2].cells[0].dir, "down"); compare(im.trends[2].cells[0].tone, "bad")
        verify(!im.trends[1].cells[1].has, "no 30 day focus slope in the file")
        compare(im.streaks.length, 2); compare(im.streaks[0].cur, 3); compare(im.streaks[0].best, 7)
        compare(im.punctuality.target, "09:00"); compare(im.punctuality.late, "7 min"); compare(im.punctuality.onTime, "8 of 12 days")
        compare(im.ratios[0].w7, "31%"); compare(im.ratios[0].w30, "28%"); compare(im.ratios[1].w7, "1.4"); compare(im.ratios[1].w30, "-")
        compare(im.bestDay.value, "8:30"); compare(im.worstDay.label, "Thu 23 Oct")
        compare(M.improve({}), null)
        compare(M.win({ d7: 1, d30: 2 }, 30), 2); compare(M.win(5, 7), 5); compare(M.win(undefined, 7), undefined)
    }

    // ---- zones -----------------------------------------------------------------------------------------
    function test_zone_ranks_by_window() {
        var r = M.zoneRanks(mk(), "week")
        compare(r.rows[0].zone, "Alpha"); compare(r.rows[0].min, 350); compare(r.totalMin, 540)
        compare(r.rows[0].slot, 0); verify(r.rows[0].share > 64 && r.rows[0].share < 65)
        var m = M.zoneRanks(mk(), "month")      // the 20th is inside 30 days, outside 7
        compare(m.totalMin, 600); compare(m.rows.length, 3)
        compare(M.zoneRanks({ today: "2025-10-30" }, "week").rows.length, 0)
    }

    function test_zone_weeks_keep_slot_colours() {
        var r = M.zoneRanks(mk(), "month"), w = M.zoneWeeks(mk(), r)
        compare(w.weeks.length, 2); compare(w.weeks[1].total, 440)
        compare(w.weeks[1].segs[0].zone, "Alpha")           // slot order, same as the ranking
        verify(w.maxMin >= 440 && w.maxMin % 60 === 0)
        var d = M.zoneDays(mk(), r, 14)
        compare(d.days.length, 14); compare(d.days[13].total, 240); compare(d.days[13].day, "2025-10-30")
        var p = M.projectRows(mk())
        compare(p[0].project, "p2"); compare(Math.round(p[1].agentPct), 25)
    }

    // ---- screen, health, reminders --------------------------------------------------------------------------
    function test_screen_and_health() {
        var s = M.screenModel(mk())
        compare(s.today, "5:00"); compare(s.idle, "1:40"); compare(s.longest, "2:10"); verify(s.lateHigh)
        compare(s.sessions[0].end, "open"); compare(s.sessions[0].active, "2:00")
        compare(M.screenModel({}), null)
        var h = M.healthModel(mk(), "2025-10-30")
        compare(h.rows.length, 2); compare(h.rows[1].cells.length, 5); compare(h.rows[1].cells[1].outcome, "pending"); verify(!h.rows[1].cells[4].has)
        compare(h.avg7, "5.5"); compare(h.doseToFirst, "60 min"); compare(M.healthModel({}, ""), null)
    }

    function test_reminders() {
        var r = M.reminderRows(mk(), {}, 1761845000)
        compare(r.rows.length, 3); compare(r.dueCount, 2)
        verify(r.rows[0].overdue); verify(r.rows[0].rel.indexOf("ago") > 0); verify(!r.rows[1].overdue); compare(r.rows[2].kind, "scheduled")
        compare(r.salah.prayer, "Asr")
        var h = M.reminderRows(mk(), { "due:a": true }, 1761845000)
        compare(h.rows.length, 2); compare(h.rows[0].desc, "Soon one")
        compare(M.reminderRows({}, {}, 1), null)
        compare(M.tsOf("2025-10-30T10:00:00Z"), 1761818400); compare(M.tsOf(1761818400000), 1761818400)
        compare(M.rel(1000 + 300, 1000), "in 5 min"); compare(M.rel(1000, 1000 + 7200), "2 h 00 m ago")
    }

    // ---- report -----------------------------------------------------------------------------------------------
    function test_report_text() {
        var t = M.reportText(mk(), "week")
        verify(t.indexOf("# Time report: this week (27 Oct to 30 Oct)") === 0, t)
        verify(t.indexOf("Worked 32:10") >= 0 && t.indexOf("+3:50 against last week") >= 0, t)
        verify(t.indexOf("Top projects: alpha 10:00, beta 5:00") >= 0, t)
        verify(t.indexOf("Over 30 days: worked time up") >= 0, t)
        verify(t.indexOf("Streaks: target met 3 (best 7)") >= 0, t)
        // lines whose numbers are missing are left out, never zero
        verify(t.indexOf("Output:") < 0 && t.indexOf("Agents ran") < 0 && t.indexOf("PRs") < 0, t)
        // every sentence starts with a capital
        M.reportLines(mk(), "week").slice(1).forEach(function (l) { verify(/^- [A-Z0-9]/.test(l), l) })
        // nothing about screen time or health, ever
        verify(!/screen|health|dose/i.test(t), t)
        verify(M.reportText({ today: "2025-10-30", periods: {} }, "month").indexOf("No numbers for this period yet.") > 0)
        compare(M.reportName(mk(), "month"), "time-month-2025-10-30.md")
        compare(M.periodRange(mk(), "quarter").start, "2025-10-01"); compare(M.periodRange(mk(), "week").start, "2025-10-27")
    }

    // ---- keyboard --------------------------------------------------------------------------------------------------
    function nav(st, a, arg, d) { return M.nav(st, a, arg, d || { rows: 10, cols: 7 }) }
    function st(o) { var s = M.initState("days"); s.zone = "list"; for (var k in o) s[k] = o[k]; return s }

    function test_nav_moves_and_clamps() {
        var s = st({})
        compare(nav(s, "move", 1).st.row, 1); compare(nav(s, "move", -1).st.row, 0)
        compare(nav(st({ row: 9 }), "move", 1).st.row, 9); compare(nav(s, "bottom").st.row, 9); compare(nav(st({ row: 9 }), "top").st.row, 0)
        compare(nav(s, "page", 1).st.row, 9); compare(nav(st({ col: 6 }), "col", 1).st.col, 6); compare(nav(s, "col", -1).st.col, 0)
        compare(s.row, 0, "the input state is not changed")
    }

    function test_nav_sub_tab_resets_the_cursor() {
        var r = nav(st({ row: 5, col: 3, detail: true, zone: "detail", scroll: 80 }), "subtab", "zones")
        compare(r.st.sub, "zones"); compare(r.st.row, 0); compare(r.st.col, 0); verify(!r.st.detail); compare(r.st.zone, "list")
    }

    function test_nav_days_enter_toggles_detail() {
        var r = nav(st({ row: 2 }), "primary")
        verify(r.st.detail); compare(r.st.zone, "detail"); compare(r.effect, "")
        var back = nav(r.st, "pane", "list")
        verify(!back.st.detail); compare(back.st.zone, "list"); compare(back.st.scroll, 0)
        compare(nav(r.st, "scroll", 1).st.scroll, 80); compare(nav(r.st, "scroll", -1).st.scroll, 0)
        compare(nav(r.st, "move", 1).st.row, 2, "j does nothing inside the detail pane")
    }

    function test_nav_week_and_period() {
        var w = st({ sub: "week" })
        compare(nav(w, "period", -1, { rows: 4, cols: 7, weeks: 3 }).st.weekOff, -1)
        compare(nav(w, "period", 1, { rows: 4, cols: 7, weeks: 3 }).st.weekOff, 0, "no week after this one")
        compare(nav(st({ sub: "week", weekOff: -2 }), "period", -1, { rows: 4, cols: 7, weeks: 3 }).st.weekOff, -2, "no week before the first day on file")
        compare(nav(w, "primary").effect, "openDay")
        compare(nav(st({ sub: "heatmap" }), "primary").effect, "openDay")
        var p = st({ sub: "progress", period: 1 })
        compare(nav(p, "period", 1).st.period, 2); compare(nav(st({ sub: "progress", period: 3 }), "period", 1).st.period, 0); compare(nav(st({ sub: "report", period: 0 }), "period", -1).st.period, 3)
        compare(nav(st({ sub: "zones", period: 1 }), "period", 1).st.period, 2); compare(nav(st({ sub: "zones", period: 2 }), "period", -1).st.period, 1)
    }

    function test_nav_effects() {
        compare(nav(st({ sub: "report" }), "primary").effect, "export")
        compare(nav(st({ sub: "report" }), "act.copy").effect, "copy")
        compare(nav(st({ sub: "reminders" }), "act.snooze").effect, "snooze")
        compare(nav(st({ sub: "reminders" }), "act.done").effect, "done")
        compare(nav(st({ sub: "reminders" }), "primary").effect, "")
    }

    function test_nav_progress_keeps_the_cursor_on_a_card() {
        var d = M.dims(mk(), st({ sub: "progress" }), {})
        compare(d.cards, M.KPI.length); compare(d.cols, 4)
        // 19 cards: the last row has three, so the fourth column does not exist there
        var r = nav(st({ sub: "progress", row: 4, col: 0 }), "col", 1, d)
        compare(r.st.col, 1)
        var far = nav(st({ sub: "progress", row: 3, col: 3 }), "move", 1, d)
        compare(far.st.row, 4); compare(far.st.col, 2, "the cursor stays on a real card")
    }

    function test_open_day_lands_on_the_days_list() {
        var s = M.openDay(st({ sub: "heatmap", row: 3, col: 2 }), mk(), "2025-10-30")
        compare(s.sub, "days"); compare(s.row, 0); verify(s.detail); compare(s.zone, "detail")
        var older = M.openDay(st({ sub: "week" }), mk(), "2025-10-20")
        compare(older.row, 10)
        compare(M.openDay(st({}), mk(), "1999-01-01").detail, false)
    }

    function test_dims() {
        var doc = mk()
        compare(M.dims(doc, { sub: "days" }, {}).rows, 17)
        compare(M.dims(doc, { sub: "heatmap" }, {}).cols, 3); compare(M.dims(doc, { sub: "heatmap" }, {}).rows, 7)
        compare(M.dims(doc, { sub: "week" }, { legend: 3, weeks: 3 }).rows, 4); compare(M.dims(doc, { sub: "week" }, { legend: 3, weeks: 3 }).weeks, 3)
        compare(M.dims(doc, { sub: "zones" }, { zones: 5 }).rows, 5); compare(M.dims(doc, { sub: "reminders" }, { reminders: 0 }).rows, 1)
    }

    // every footer hint key must be a key the keymap really handles on that page and zone
    function test_hints_are_real_keys() {
        var tok = { "Enter": "Enter", "Esc": "Esc", "Tab": "Tab", "Up Down": "Down", "?": "?" }
        M.SUBS.forEach(function (s) {
            ["tabs", "list", "detail"].forEach(function (zone) {
                M.hints(s[0], zone).forEach(function (h) {
                    var keys = h[0] === "[ ]" ? ["[", "]"] : (h[0] === "1-5" ? ["1", "5"] : (tok[h[0]] ? [tok[h[0]]] : h[0].split(" ")))
                    keys.forEach(function (k) {
                        var ev = { key: 0, text: k, shift: false, ctrl: false, alt: false }
                        if (k === "Enter") ev = { key: 0x01000004, text: "", shift: false, ctrl: false, alt: false }
                        else if (k === "Esc") ev = { key: 0x01000000, text: "", shift: false, ctrl: false, alt: false }
                        else if (k === "Tab") ev = { key: 0x01000001, text: "", shift: false, ctrl: false, alt: false }
                        else if (k === "Down") ev = { key: 0x01000015, text: "", shift: false, ctrl: false, alt: false }
                        var r = K.resolve(ev, { page: "time", sub: s[0], zone: zone, mode: "", kind: "", pending: "", filterActive: false })
                        verify(r.action !== "" || r.pending !== "", s[0] + "/" + zone + ": hint key '" + k + "' does nothing")
                    })
                })
            })
        })
    }

    function test_hints_say_five_keys() {
        M.SUBS.forEach(function (s) { ["tabs", "list", "detail"].forEach(function (z) { compare(M.hints(s[0], z).length, 5, s[0] + "/" + z) }) })
    }

    function test_sub_names_match_keys_js() {
        compare(M.SUBS.map(function (s) { return s[0] }).join(","), K.SUBTABS.join(","))
        compare(M.subId("Focus zones"), "zones"); compare(M.subName("screen"), "Screen and health"); compare(M.subId("nope"), "today")
        compare(M.PERIODS.join(","), K.PERIODS.join(","))
    }
}
