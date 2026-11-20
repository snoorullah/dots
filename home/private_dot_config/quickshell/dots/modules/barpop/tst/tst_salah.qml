import QtQuick
import QtTest
import "../js/Salah.js" as Salah

TestCase {
    name: "Salah"
    property string conf: "# auto-generated 2026-11-03 sample\n" +
        "Fajr 05:32    # adhan 05:12 · adhan+20m · ends 06:31\n" +
        "Dhuhr 12:43    # adhan 12:28 · adhan+15m · ends 15:42\n" +
        "Asr 15:52    # adhan 15:42 · adhan+10m · ends 18:21\n" +
        "Maghrib 18:26    # adhan 18:21 · adhan+5m · ends 19:48\n" +
        "Isha 20:03    # adhan 19:48 · adhan+15m · ends 05:13\n"

    function at(y, mo, d, h, mi) { return new Date(y, mo - 1, d, h, mi, 0) }

    function test_parse() {
        var p = Salah.parseConf(conf)
        compare(p.date, "2026-11-03")
        compare(p.rows.length, 5)
        compare(p.rows[0].name, "Fajr")
        compare(p.rows[0].adhan, 312)
        compare(p.rows[0].iqamah, 332)
        compare(p.rows[0].ends, 391)
        compare(p.rows[4].ends, 313 + 1440)     // Isha ends at the next Fajr
    }

    function test_parse_without_comment() {
        var p = Salah.parseConf("Fajr 05:32\nDhuhr 13:30\n")
        compare(p.rows.length, 2)
        compare(p.rows[1].adhan, 13 * 60 + 30)  // no comment: adhan = the listed time
        compare(p.rows[1].ends, p.rows[1].adhan + 90)
    }

    function test_parse_junk() {
        compare(Salah.parseConf("").rows.length, 0)
        compare(Salah.parseConf("nonsense\n# x\nFajr 99:99\n").rows.length, 0)
        compare(Salah.parseConf(null).rows.length, 0)
    }

    function test_dur() {
        compare(Salah.dur(0), "0m")
        compare(Salah.dur(45), "45m")
        compare(Salah.dur(60), "1h 00m")
        compare(Salah.dur(164), "2h 44m")
    }

    function test_normal() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 14, 37))   // Tue
        compare(m.ok, true)
        compare(m.next, 2)
        compare(m.cur, -1)
        compare(m.hero.label, "NEXT")
        compare(m.hero.name, "Asr 15:42")
        compare(m.hero.cd, "in 1h 05m")
        compare(m.hero.soon, false)
        compare(m.rows[0].past, true)
        compare(m.rows[1].past, true)
        compare(m.rows[2].focus, true)
        compare(m.rows[2].past, false)
        compare(m.rows[0].iq, "+20")
        compare(m.rows[3].iq, "+5")
        compare(m.sunrise, "06:31")
        compare(m.stale, false)
    }

    function test_soon() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 15, 31))
        compare(m.hero.soon, true)
        compare(m.hero.cd, "11m")
    }

    function test_window_open() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 15, 58))
        compare(m.cur, 2)
        compare(m.hero.label, "NOW")
        compare(m.hero.name, "Now: Asr")
        compare(m.hero.cd, "ends in 9m")
        verify(m.hero.pct > 0.6 && m.hero.pct < 0.7)
        compare(m.rows[2].focus, true)
        compare(m.rows[1].past, true)
    }

    function test_friday_jumuah() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 6, 10, 35))   // Fri
        compare(m.jumuah, true)
        compare(m.rows[1].name, "Jumuah")
        compare(m.hero.name, "Jumuah 12:28")
        var t = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 10, 35))
        compare(t.rows[1].name, "Dhuhr")
    }

    function test_after_isha_is_tomorrow() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 22, 0))
        compare(m.next, 0)
        compare(m.cur, -1)
        compare(m.hero.label, "TOMORROW")
        compare(m.hero.name, "Fajr 05:12")
        compare(m.hero.cd, "in 7h 12m")
    }

    function test_before_fajr_next_is_fajr() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 3, 4, 30))
        compare(m.next, 0)
        compare(m.hero.label, "NEXT")
        compare(m.hero.cd, "in 42m")
    }

    function test_stale_file() {
        var m = Salah.build(Salah.parseConf(conf), at(2026, 11, 9, 14, 37))
        compare(m.stale, true)
        compare(m.hero.cd, "cached")
        compare(m.hero.soon, false)
    }

    function test_empty_file() {
        var m = Salah.build(Salah.parseConf(""), at(2026, 11, 3, 14, 37))
        compare(m.ok, false)
        compare(m.rows.length, 0)
    }
}
