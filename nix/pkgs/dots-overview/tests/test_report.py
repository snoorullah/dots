"""The daily brief: company items only, idempotent, 0600, no personal data."""
import sqlite3
import stat
import time
import unittest
from datetime import datetime

import helpers
from dots_overview import config, local_tt, report

# built from parts: the literal never appears in shipped source (only tests/lint.sh's denylist names it)
HANDLE = "web" + "sleak"


def make_db(path, day_epoch):
    path.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(path)
    c.executescript("""
      CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER);
      CREATE TABLE deduction (id INTEGER PRIMARY KEY, session_id INTEGER, start_unix INTEGER, end_unix INTEGER);
      CREATE TABLE v_run_interval (ticket TEXT, start_unix INTEGER, end_unix INTEGER);
    """)
    c.execute("INSERT INTO work_session VALUES (1, ?, ?)", (day_epoch + 9 * 3600, day_epoch + 17 * 3600))
    c.execute("INSERT INTO work_session VALUES (2, ?, ?)", (day_epoch + 10 * 3600, day_epoch + 12 * 3600))  # overlaps: not double counted
    c.execute("INSERT INTO deduction VALUES (1, 1, ?, ?)", (day_epoch + 13 * 3600, day_epoch + 14 * 3600))
    c.execute("INSERT INTO v_run_interval VALUES ('HD-123', ?, ?)", (day_epoch + 9 * 3600, day_epoch + 10 * 3600 + 40 * 60))
    c.execute("INSERT INTO v_run_interval VALUES ('gh:acme/r#886', ?, ?)", (day_epoch + 11 * 3600, day_epoch + 11 * 3600 + 600))
    c.commit()
    c.close()


class Brief(helpers.Scratch):
    def setUp(self):
        super().setUp()
        self.day = datetime.now().date()
        t0, _ = local_tt.day_bounds(self.day)
        make_db(config.TT_DIR / "work.db", t0)
        self.t0 = t0
        self.tw = helpers.FakeTw(self)
        self.cfg = config.Work({"WORK_GH_ORG": "acme", "WORK_PROJECTS": "work", "REDACT_WORDS": HANDLE, "REPORT_DIR": str(self.root / "daily")})
        end = t0 + 15 * 3600
        self.tw.seed(desc="Fix the intake form validation", ref="HD-123", src="erp", status="completed", end_ts=end)
        self.tw.seed(desc="Detection rules", ref="gh:acme/r#886", src="gh", status="completed", end_ts=end + 60, srcstate="review:reviewed")
        self.tw.seed(desc="Buy birthday present for ada@example.com", project="personal", status="completed", end_ts=end)
        self.tw.seed(desc="Personal repo chore", ref="gh:me/dots#3", src="gh", status="completed", end_ts=end)
        self.tw.seed(desc="SHA-pin Actions", ref="TASK-2026-00561", src="erp", tags=["mirror", "attn"])
        self.tw.seed(desc=f"Weekend hobby {HANDLE} thing", project="personal", start_ts=t0 + 100)
        self.tw.seed(desc="Old work item from last week", project="work", status="completed", end_ts=t0 - 86400)

    def build(self):
        # `now` late enough that the whole working day is in the past
        return report.build(self.day, self.cfg, now=self.t0 + 23 * 3600)

    def test_content_is_company_only(self):
        text = self.build()
        self.assertIn(f"# {self.day.isoformat()}", text)
        self.assertIn("2 items closed", text)
        self.assertIn("1 still open", text)
        self.assertIn("`HD-123` Fix the intake form validation — 1h 40m", text)
        self.assertIn("`gh:acme/r#886` Detection rules — 10m — review submitted", text)
        self.assertIn("`TASK-2026-00561` SHA-pin Actions", text)
        for leak in ("birthday", "Personal repo", "hobby", "Old work item", "@", HANDLE):
            self.assertNotIn(leak, text)

    def test_worked_time_unions_overlap_and_subtracts_deductions(self):
        # 09:00-17:00 (the 10-12 session is inside it) minus a 1 h break = 7 h
        self.assertIn("Worked 7h ·", self.build())

    def test_idle_and_app_activity_are_never_written(self):
        text = self.build().lower()
        for word in ("idle", "away", "afk", "firefox", "slack", "ghostty"):
            self.assertNotIn(word, text)

    def test_emails_and_banned_handle_are_scrubbed_from_titles(self):
        self.tw.seed(desc=f"Mail ops@example.com about {HANDLE}.dev", ref="HD-9", src="erp", status="completed", end_ts=self.t0 + 16 * 3600)
        text = self.build()
        self.assertNotIn("ops@example.com", text)
        self.assertNotIn(HANDLE, text.lower())
        self.assertIn("[email]", text)

    def test_email_floor_needs_no_config_and_words_are_opt_in(self):
        bare = config.Work({})
        self.assertEqual(report.scrub("ping a.b+c@ex-ample.co.uk now", bare), "ping [email] now")
        self.assertIn(HANDLE, report.scrub(f"about {HANDLE}.dev", bare))          # no word list: not touched
        self.assertEqual(report.scrub(f"about {HANDLE}.dev x@y.zz", self.cfg), "about [redacted] [email]")
        self.assertEqual(report.scrub("x@y.zz", config.Work({"REDACT_WORDS": ""})), "[email]")

    def test_write_is_0600_idempotent_and_nightly_is_a_noop(self):
        t = self.t0 + 23 * 3600
        self.assertEqual(report.write(self.day, self.cfg, "logout", now=t), "created")
        path = self.cfg.report_dir / f"{self.day.isoformat()}.md"
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.cfg.report_dir.stat().st_mode), 0o700)
        first = path.stat().st_mtime_ns
        self.assertEqual(report.write(self.day, self.cfg, None, now=t), "unchanged")
        self.assertEqual(path.stat().st_mtime_ns, first)
        self.assertEqual(report.write(self.day, self.cfg, "nightly", now=t), "skipped")
        # content changes -> rewritten
        self.tw.seed(desc="Another closed thing", ref="HD-77", src="erp", status="completed", end_ts=self.t0 + 16 * 3600)
        self.assertEqual(report.write(self.day, self.cfg, "logout", now=t), "updated")
        self.assertIn("HD-77", path.read_text())

    def test_nightly_creates_when_nothing_exists(self):
        self.assertEqual(report.write(self.day, self.cfg, "nightly", now=self.t0 + 23 * 3600), "created")

    def test_empty_day_is_still_a_valid_brief(self):
        self.tw.tasks.clear()
        text = report.build(self.day, self.cfg, now=self.t0 + 23 * 3600)
        self.assertIn("0 items closed", text)
        self.assertIn("Nothing.", text)

    def test_dur(self):
        self.assertEqual([report.dur(s) for s in (0, 59, 60, 3599, 3600, 3660, 22320)], ["", "", "1m", "59m", "1h", "1h 01m", "6h 12m"])


if __name__ == "__main__":
    unittest.main()
