"""Metrics edge cases: no invented zeros, unfinished day left out of trends, honest coverage."""
import unittest
from datetime import timedelta

from dots_overview import metrics, metrics_aw
from test_metrics import Screen, World


class Pure(unittest.TestCase):
    def test_zero_series_is_flat(self):
        self.assertEqual(metrics.direction(0.0, [0, 0, 0]), "flat")
        self.assertEqual(metrics.direction(0.0, [0.0, 0.0]), "flat")

    def test_real_decline_still_down(self):
        self.assertEqual(metrics.direction(-1.0, [10, 9, 8]), "down")


class Fixes(World):
    aw = Screen.aw

    def test_missing_view_row_omits_worked_and_does_not_invent_zero(self):
        rows = [(d, k, t, None, None, f, l, None) for d, k, t, n, s, f, l, _ in self.series(10)]
        self.work(rows)
        doc = self.build()
        wd = [d for d in doc["days"] if d["kind"] == "working"]
        self.assertTrue(wd)
        self.assertTrue(all("workedMin" not in d for d in wd))
        p = doc["periods"].get("week", {})
        self.assertNotIn("attainmentPct", p)
        self.assertNotIn("daysWorked", p)
        self.assertNotIn("targetMet", doc.get("improve", {}).get("streaks", {}))

    def test_span_fallback_still_used(self):
        rows = [(d, k, t, None, s, f, l, None) for d, k, t, n, s, f, l, _ in self.series(10)]
        self.work(rows)
        d = [x for x in self.build()["days"] if x["kind"] == "working"][-1]
        self.assertGreater(d["workedMin"], 0)

    def test_unfinished_today_is_left_out_of_trend_and_best_worst(self):
        self.work(self.series(30, worked=lambda i: 400 if i < 29 else 50))     # today is a dip so far
        i = self.build()["improve"]
        self.assertEqual(i["trend7"]["workedMin"], 0.0)
        self.assertEqual(i["trend7"]["dir"]["workedMin"], "flat")
        self.assertEqual(i["worstDay"]["workedMin"], 400)
        self.assertNotEqual(i["worstDay"]["day"], self.today.isoformat())

    def test_attainment_of_a_running_period_skips_today(self):
        self.work(self.series(10, worked=lambda i: 480 if i < 9 else 60))
        p = self.build()["periods"]
        self.assertEqual(p["week"]["attainmentPct"]["value"], 100.0)           # Mon+Tue done, Wed excluded
        self.assertEqual(p["today"]["attainmentPct"]["value"], 12.5)           # today: progress so far

    def test_screen_kpi_carries_coverage_and_drops_delta_when_uneven(self):
        self.work(self.series(40))
        self.aw()
        old = metrics_aw.BUDGET_DAYS
        metrics_aw.BUDGET_DAYS = 3
        self.addCleanup(setattr, metrics_aw, "BUDGET_DAYS", old)
        m = self.build()["periods"]["month"]["screenSec"]
        self.assertLess(m["days"], m["of"])
        self.assertNotIn("delta", m)
        self.assertNotIn("prev", m)


if __name__ == "__main__":
    unittest.main()
