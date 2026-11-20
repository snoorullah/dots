import QtQuick
import QtTest
import "../js/Cal.js" as Cal
import "../../barpop/js/Salah.js" as Salah

TestCase {
    name: "Cal"
    property string conf: "# auto-generated 2026-11-03 sample\n" +
        "Fajr 05:32    # adhan 05:12 · adhan+20m · ends 06:31\n" +
        "Dhuhr 12:43    # adhan 12:28 · adhan+15m · ends 15:42\n" +
        "Asr 15:52    # adhan 15:42 · adhan+10m · ends 18:21\n" +
        "Maghrib 18:26    # adhan 18:21 · adhan+5m · ends 19:48\n" +
        "Isha 20:03    # adhan 19:48 · adhan+15m · ends 05:13\n"
    property var sal: Salah.parseConf(conf)

    function ev(id, start, end, o) {
        var d = { id: id, date: "2026-11-03", start: start, end: end, title: "Event " + id, link: false, worked: false, held: false }
        for (var k in o) d[k] = o[k]
        return d
    }
    function doc(events, ts) { return { v: 1, ts: ts, events: events } }
    function at(h, m) { return new Date(2026, 10, 3, h, m, 0) }
    function tsAt(h, m) { return at(h, m).getTime() / 1000 }

    function test_header() {
        var m = Cal.build(doc([], tsAt(9, 0)), sal, at(9, 18), {})
        compare(m.time, "09:18")
        compare(m.dateLine, "Tue 3 Nov")
        compare(m.today, true)
    }

    function test_rows_sorted_with_now_and_prayer() {
        var d = doc([ev("a", "09:00", "09:40", { worked: true }), ev("b", "09:30", "10:00", { link: true }),
                     ev("c", "13:00", "14:00")], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 18), {})
        var kinds = m.rows.map(function (r) { return r.k }).join(",")
        compare(kinds, "ev,now,ev,free,pr,ev,free,pr,pr,pr")
        compare(m.rows[0].past, false)           // a is still running (09:00 to 09:40)
        compare(m.rows[0].active, true)
        compare(m.rows[2].next, true)
        compare(m.rows[3].title, "2h 28m free")  // 10:00 to 12:28 (Dhuhr)
        compare(m.rows[6].title, "1h 42m free")  // 14:00 to 15:42 (Asr)
    }

    function test_past_event() {
        var d = doc([ev("a", "08:00", "08:40")], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 18), {})
        compare(m.rows[0].past, true)
        compare(m.rows[0].dur, "40m")
    }

    function test_strip_next_meeting() {
        var d = doc([ev("b", "11:00", "11:30", { link: true })], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 18), {})
        compare(m.strip.label, "NEXT · MEETING")
        compare(m.strip.title, "Event b in 1h 42m")
        compare(m.strip.tone, "info")
        compare(m.strip.btn, "Join")
    }

    function test_strip_soon_is_amber() {
        var d = doc([ev("b", "09:24", "09:54", { link: true })], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 18), {})
        compare(m.strip.tone, "amber")
        compare(m.strip.label, "NEXT · SOON")
        compare(m.strip.title, "Event b in 6m")
    }

    function test_strip_in_meeting() {
        var d = doc([ev("b", "09:00", "10:00", { link: true, worked: true })], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 42), {})
        compare(m.strip.tone, "meeting")
        compare(m.strip.label, "NOW · IN MEETING")
        compare(m.strip.title, "In meeting, 18m left")
    }

    function test_strip_prayer_beats_meeting() {
        var d = doc([ev("b", "15:30", "16:00", { link: true })], tsAt(15, 0))
        var m = Cal.build(d, sal, at(15, 47), {})      // Asr window is open
        compare(m.strip.tone, "prayer")
        compare(m.strip.label, "NEXT · SALAH")
        compare(m.strip.title, "Asr window open")
        var dim = m.rows.filter(function (r) { return r.k === "ev" })[0]
        compare(dim.dim, true)
    }

    function test_strip_next_prayer_when_no_events() {
        var m = Cal.build(doc([], tsAt(14, 40)), sal, at(14, 48), {})
        compare(m.strip.label, "NEXT · SALAH")
        compare(m.strip.title, "Asr in 54m")
        compare(m.rows.filter(function (r) { return r.k === "empty" }).length, 1)
    }

    function test_stale_doc() {
        var d = doc([ev("b", "15:30", "16:00")], tsAt(14, 2))
        var m = Cal.build(d, sal, at(14, 48), {})
        compare(m.stale, true)
        compare(m.today, false)
        compare(m.foot.t, "stale 14:02")
        compare(m.banner.kind, "unknown")
        compare(m.rows.filter(function (r) { return r.k === "ev" })[0].unk, true)
    }

    function test_no_doc() {
        var m = Cal.build(null, sal, at(14, 48), {})
        compare(m.foot.t, "no calendar source")
        compare(m.stale, false)
        compare(m.banner, null)
    }

    function test_unverified_prayers() {
        var late = Cal.build(doc([], tsAt(9, 0)), Salah.parseConf(conf.replace("2026-11-03", "2026-10-29")), at(9, 18), {})
        compare(late.banner.kind, "unknown")
        verify(late.banner.text.indexOf("Prayer times unverified") === 0)
        compare(late.rows.filter(function (r) { return r.k === "pr" })[0].unv, true)
    }

    function test_week_strip() {
        var d = doc([ev("a", "09:00", "10:00"), ev("b", "11:00", "12:00"), ev("c", "13:00", "14:00"), ev("d", "15:00", "16:00"),
                     ev("e", "10:00", "11:00", { date: "2026-11-05" })], tsAt(9, 0))
        var m = Cal.build(d, sal, at(9, 18), {})
        compare(m.week.length, 7)
        compare(m.week[0].dow, "MON")
        compare(m.week[0].n, 2)
        compare(m.week[1].n, 3)
        compare(m.week[1].today, true)
        compare(m.week[1].dots, 3)            // capped at three
        compare(m.week[3].dots, 1)
    }

    function test_month_grid() {
        var m = Cal.build(null, sal, at(9, 18), {})
        compare(m.month.length, 42)
        compare(m.monthLabel, "November 2026")
        compare(m.month[5].n, 31)              // Nov 1 2026 is a Sunday, so Mon..Sat are Oct 26..31
        compare(m.month[5].inMonth, false)
        compare(m.month[6].n, 1)
        compare(m.month[6].inMonth, true)
        var today = m.month.filter(function (c) { return c.today })
        compare(today.length, 1)
        compare(today[0].n, 3)
    }

    function test_open_event_details() {
        var d = doc([ev("b", "11:00", "11:30", { link: true, worked: true })], tsAt(9, 10))
        var m = Cal.build(d, sal, at(9, 18), { openId: "b" })
        var r = m.rows.filter(function (x) { return x.k === "ev" })[0]
        compare(r.open, true)
        compare(r.d1, "11:00 to 11:30 · join link ready")
    }

    function test_bad_doc() {
        compare(Cal.build({ v: 2, events: [ev("a", "09:00", "10:00")] }, sal, at(9, 18), {}).rows.filter(function (r) { return r.k === "ev" }).length, 0)
        compare(Cal.build(doc([{ id: "z", date: "2026-11-03", start: "bad", end: "bad", title: "x" }], 1), sal, at(9, 18), {}).rows.filter(function (r) { return r.k === "ev" }).length, 0)
    }
}
