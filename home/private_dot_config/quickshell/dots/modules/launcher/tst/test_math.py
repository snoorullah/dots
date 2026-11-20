import datetime as dt
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "js"))
os.environ["PATH"] = "/nonexistent"        # no qalc: the built-in evaluator must carry these cases
import launcher_math as m  # noqa: E402

NOW = dt.datetime(2026, 11, 20, 9, 0)


def ev(t):
    return m.evaluate(t, NOW)


class Arithmetic(unittest.TestCase):
    def test_board_example(self):
        self.assertEqual(ev("1024 * 8"), "8192")

    def test_precedence_and_parens(self):
        self.assertEqual(ev("2 + 3 * 4"), "14")
        self.assertEqual(ev("(2 + 3) * 4"), "20")

    def test_power_and_caret(self):
        self.assertEqual(ev("2^10"), "1024")
        self.assertEqual(ev("2**0.5"), "1.414213562")

    def test_functions_and_constants(self):
        self.assertEqual(ev("sqrt(16) + 1"), "5")
        self.assertEqual(ev("pi * 2"), "6.283185307")

    def test_percent_of(self):
        self.assertEqual(ev("15% of 80"), "12")

    def test_suffixes_and_separators(self):
        self.assertEqual(ev("1,000 * 3"), "3000")
        self.assertEqual(ev("2k * 3"), "6000")

    def test_division(self):
        self.assertEqual(ev("10 / 4"), "2.5")
        self.assertEqual(ev("10 // 4"), "2")

    def test_refuses_what_is_not_math(self):
        for bad in ("", "hello", "5", "1 +", "__import__('os')", "open('x')", "a.b", "1 if 1 else 2"):
            self.assertIsNone(ev(bad), bad)

    def test_huge_power_is_refused_not_computed(self):
        self.assertIsNone(ev("9**9**9"))
        self.assertIsNone(ev("2**100000"))

    def test_division_by_zero(self):
        self.assertIsNone(ev("1/0"))


class Units(unittest.TestCase):
    def test_binary_data(self):
        self.assertEqual(ev("3 GiB in MiB"), "3072 MiB")

    def test_decimal_vs_binary(self):
        self.assertEqual(ev("1 GB in MB"), "1000 MB")
        self.assertEqual(ev("1 GiB in MB"), "1073.741824 MB")

    def test_time(self):
        self.assertEqual(ev("1.5 h in min"), "90 min")
        self.assertEqual(ev("3 days in hours"), "72 hours")

    def test_length(self):
        self.assertEqual(ev("12 km in mi"), "7.456454307 mi")

    def test_temperature(self):
        self.assertEqual(ev("100 C in F"), "212 °F")
        self.assertEqual(ev("0 K in C"), "-273.15 °C")

    def test_mismatched_categories(self):
        self.assertIsNone(ev("3 GiB in km"))


class Clock(unittest.TestCase):
    def test_board_example(self):
        self.assertEqual(ev("18:40 + 7h 40m"), "02:20 (+1 day)")

    def test_same_day(self):
        self.assertEqual(ev("09:00 + 90m"), "10:30")

    def test_back_across_midnight(self):
        self.assertEqual(ev("00:30 - 1h"), "23:30 (-1 day)")

    def test_gap(self):
        self.assertEqual(ev("18:40 - 17:10"), "1h 30m")

    def test_bad_clock(self):
        self.assertIsNone(ev("25:00 + 1h"))


class Calendar(unittest.TestCase):
    def test_plus_weeks(self):
        self.assertEqual(ev("today + 2w"), "2026-12-04 (Fri)")

    def test_iso_minus_days(self):
        self.assertEqual(ev("2026-11-20 - 20d"), "2026-10-31 (Sat)")

    def test_gap_in_days(self):
        self.assertEqual(ev("2026-12-25 - today"), "35 days")
        self.assertEqual(ev("today - 2026-11-19"), "1 day")


class Output(unittest.TestCase):
    def test_row_shape(self):
        o = m.build("1024 * 8", NOW)
        self.assertEqual(len(o["rows"]), 1)
        r = o["rows"][0]
        self.assertEqual((r["title"], r["sub"], r["icon"]), ("8192", "1024 * 8", "calculator"))
        self.assertEqual(r["actions"], [{"label": "Copy result", "primary": True}])
        self.assertEqual(r["preview"]["head"], "8192")

    def test_no_result_is_empty_rows_with_a_hint(self):
        o = m.build("hello world", NOW)
        self.assertEqual(o["rows"], [])
        self.assertTrue(o["hint"])


if __name__ == "__main__":
    unittest.main()
