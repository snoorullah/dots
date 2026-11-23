"""away_history: gaps from deduction + away_label, read-only, neutral fixtures."""
import json
import sqlite3
import unittest
from datetime import datetime

import helpers
from dots_overview import away_history as ah
from dots_overview import config

NOW = int(datetime(2026, 3, 10, 15, 0, 0).timestamp())
H = 3600


class TestAway(helpers.Scratch):
    def setUp(self):
        super().setUp()
        config.TT_DIR.mkdir(parents=True)
        w = sqlite3.connect(config.TT_DIR / "work.db")
        w.executescript("""CREATE TABLE deduction (id INTEGER PRIMARY KEY, attendance_day TEXT, start_unix INTEGER,
                            end_unix INTEGER, category TEXT, confirmed INTEGER);
                           CREATE TABLE clock_event (id INTEGER PRIMARY KEY, kind TEXT, ts_unix INTEGER);""")
        p = sqlite3.connect(config.TT_DIR / "private.db")
        p.execute("CREATE TABLE away_label (start_unix INTEGER PRIMARY KEY, end_unix INTEGER, day TEXT, key TEXT,"
                  " label TEXT, source TEXT)")
        self.w, self.p = w, p
        self.addCleanup(w.close)
        self.addCleanup(p.close)

    def test_label_joined_to_deduction_category(self):
        s = NOW - 2 * H
        self.p.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (s, s + 1800, "2026-03-10", "meal", "Meal", "declared"))
        self.w.execute("INSERT INTO deduction VALUES (1,'2026-03-10',?,?,?,1)", (s, s + 1800, "lunch"))
        for c in (self.w, self.p):
            c.commit()
        d = ah.run(now=NOW)
        self.assertEqual(d["count"], 1)
        g = d["gaps"][0]
        self.assertEqual((g["category"], g["answered"], g["minutes"]), ("lunch", True, 30.0))
        self.assertEqual(d["byCategory"]["lunch"]["count"], 1)

    def test_auto_label_is_unanswered_and_old_and_tiny_gaps_dropped(self):
        s = NOW - H
        self.p.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (s, s + 600, "2026-03-10", "auto", "Short break", "auto"))
        self.p.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (NOW - 9 * 86400, NOW - 9 * 86400 + 600, "x", "walk", "Walk", "asked"))
        self.p.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (s + 5000, s + 5030, "2026-03-10", "walk", "Walk", "asked"))
        self.p.commit()
        d = ah.run(now=NOW)
        self.assertEqual([(g["answered"], g["category"]) for g in d["gaps"]], [(False, "auto")])
        self.assertEqual(d["unanswered"], 1)

    def test_bare_deduction_and_away_events_included(self):
        s = NOW - 3 * H
        self.w.execute("INSERT INTO deduction VALUES (1,'2026-03-10',?,?,'washroom',0)", (s, s + 300))
        self.w.execute("INSERT INTO clock_event VALUES (1,'away_start',?)", (s + H,))
        self.w.execute("INSERT INTO clock_event VALUES (2,'away_stop',?)", (s + H + 900,))
        self.w.commit()
        d = ah.run(now=NOW)
        self.assertEqual([(g["category"], g["answered"]) for g in d["gaps"]], [("washroom", False), ("away", False)])

    def test_missing_dbs_give_empty_and_files_written(self):
        for f in config.TT_DIR.iterdir():
            f.unlink()
        d = ah.run(now=NOW)
        self.assertEqual(d["count"], 0)
        self.assertTrue((config.STATE_DIR / "away.json").exists())

    def test_never_writes_to_source(self):
        before = (config.TT_DIR / "work.db").stat().st_mtime_ns
        ah.run(now=NOW)
        self.assertEqual(before, (config.TT_DIR / "work.db").stat().st_mtime_ns)


if __name__ == "__main__":
    unittest.main()
