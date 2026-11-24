"""worked_sec honours hand-corrected break totals (day_edit), as timetrack's own figure does."""
import sqlite3
import unittest
from datetime import datetime

import helpers
from dots_overview import config, local_tt


class WorkedHonoursEdits(helpers.Scratch):
    def setUp(self):
        super().setUp()
        config.TT_DIR.mkdir(parents=True, exist_ok=True)
        at = lambda h, m=0: int(datetime(2026, 11, 24, h, m).timestamp())  # noqa: E731
        self.at = at
        db = sqlite3.connect(config.TT_DIR / "work.db")
        db.executescript("""
          CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER,
                                     attendance_day TEXT);
          CREATE TABLE deduction (id INTEGER PRIMARY KEY, session_id INTEGER, attendance_day TEXT,
                                  start_unix INTEGER, end_unix INTEGER, category TEXT, minutes INTEGER);
          CREATE TABLE day_edit (day TEXT PRIMARY KEY, salah INTEGER, lunch INTEGER, dinner INTEGER,
                                 washroom INTEGER, misc INTEGER, call_personal INTEGER, unsure INTEGER);
          CREATE TABLE edited_total (day TEXT, m INTEGER);
          CREATE VIEW v_day_deduction AS SELECT day AS attendance_day, m AS deduction_minutes FROM edited_total;
        """)
        db.execute("INSERT INTO work_session VALUES (1, ?, ?, '2026-11-24')", (at(20), at(23)))
        db.execute("INSERT INTO deduction VALUES (1, 1, '2026-11-24', ?, ?, 'misc', 45)", (at(21), at(21, 45)))
        db.commit()
        self.db = db

    def tearDown(self):
        self.db.close()
        super().tearDown()

    def test_raw_breaks_without_an_edit(self):
        self.assertEqual(local_tt.worked_sec(self.at(0), self.at(23, 30), self.at(23, 30)) // 60, 180 - 45)

    def test_edited_total_replaces_the_raw_breaks(self):
        self.db.execute("INSERT INTO day_edit (day, misc, unsure) VALUES ('2026-11-24', 10, 0)")
        self.db.execute("INSERT INTO edited_total VALUES ('2026-11-24', 10)")
        self.db.commit()
        self.assertEqual(local_tt.worked_sec(self.at(0), self.at(23, 30), self.at(23, 30)) // 60, 180 - 10)


if __name__ == "__main__":
    unittest.main()
