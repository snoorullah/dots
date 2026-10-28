import QtQuick
import QtTest
import "../js/Fmt.js" as Fmt

TestCase {
    name: "Fmt"

    function test_mmss() {
        compare(Fmt.mmss(0), "00:00")
        compare(Fmt.mmss(59), "00:59")
        compare(Fmt.mmss(1500), "25:00")
        compare(Fmt.mmss(3599), "59:59")
        compare(Fmt.mmss(3600), "60:00")      // no hour roll: the timer is at most 25 min
        compare(Fmt.mmss(-5), "00:00")
        compare(Fmt.mmss(NaN), "00:00")
        compare(Fmt.mmss(61.9), "01:01")
    }

    function test_hm() {
        compare(Fmt.hm(0), "0m")
        compare(Fmt.hm(59), "0m")
        compare(Fmt.hm(2700), "45m")
        compare(Fmt.hm(3600), "1h 00m")
        compare(Fmt.hm(7500), "2h 05m")
        compare(Fmt.hm(undefined), "0m")
    }

    function test_pct() {
        compare(Fmt.pct(1, 3), 33)
        compare(Fmt.pct(2, 3), 67)
        compare(Fmt.pct(5, 0), 0)
        compare(Fmt.pct(0, 10), 0)
    }

    function test_age() {
        compare(Fmt.age(10), "now")
        compare(Fmt.age(60), "1m")
        compare(Fmt.age(3599), "59m")
        compare(Fmt.age(7200), "2h")
        compare(Fmt.age(200000), "2d")
    }

    function test_dayLabel() {
        compare(Fmt.dayLabel("2026-10-27"), "Tue 27 Oct")
        compare(Fmt.dayLabel("2026-03-29"), "Sun 29 Mar")   // a DST changeover in Europe
        compare(Fmt.dayLabel("garbage"), "garbage")
    }

    function test_badge_and_clip() {
        compare(Fmt.badge(0), "")
        compare(Fmt.badge(7), "7")
        compare(Fmt.badge(120), "99+")
        compare(Fmt.clip("  a   b  ", 10), "a b")
        compare(Fmt.clip("abcdefghij", 5), "abcd…")
        compare(Fmt.clip(null, 5), "")
    }
}
