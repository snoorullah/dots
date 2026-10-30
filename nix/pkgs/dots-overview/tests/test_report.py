"""The daily brief: company items only, idempotent, 0600, no personal data."""
import json
import sqlite3
import stat
import time
import unittest
from datetime import datetime

import helpers
from dots_overview import config, local_tt, report, sources_gh

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

def make_private(path, day):
    c = sqlite3.connect(path)
    c.executescript("""
      CREATE TABLE term_day (day TEXT, task_uuid TEXT DEFAULT '', ref TEXT DEFAULT '', project TEXT DEFAULT '',
                             agent_name TEXT DEFAULT '', verdict TEXT, seconds INTEGER);
      CREATE TABLE web_ticket_day (day TEXT, ticket TEXT, seconds INTEGER);
    """)
    d = day.isoformat()
    rows = [(d, "", "HD-123", "work", "", "work", 3900),               # you, on a ticket
            (d, "", "HD-123", "work", "claude", "delegated", 1200),    # an agent, same ticket
            (d, "", "", "work", "", "work", 7800),                     # work project, no ticket
            (d, "", "", "personal", "", "work", 5000),                 # personal: never listed
            (d, "", "HD-123", "work", "", "unproductive", 3000),       # not an outcome
            (d, "", "gh:me/dots#3", "", "", "work", 4000),             # personal repo
            (d, "", "HD-5", "work", "", "work", 30)]                   # under a minute: noise
    c.executemany("INSERT INTO term_day VALUES (?,?,?,?,?,?,?)", rows)
    c.executemany("INSERT INTO web_ticket_day VALUES (?,?,?)", [(d, "HD-123", 900), (d, "gh:me/dots#3", 600)])
    c.commit()
    c.close()


PRS = {"opened": [{"number": 7, "title": "Add retries", "repository": {"nameWithOwner": "acme/r"}, "author": {"login": "me"}},
                  {"number": 2, "title": "Personal thing", "repository": {"nameWithOwner": "me/dots"}, "author": {"login": "me"}}],
       "merged": [{"number": 6, "title": "Fix lint ada@example.com", "repository": {"nameWithOwner": "acme/r"}, "author": {"login": "me"}}],
       "reviewed": [{"number": 9, "title": "Their change", "repository": {"nameWithOwner": "acme/r"}, "author": {"login": "bob"}},
                    {"number": 7, "title": "Add retries", "repository": {"nameWithOwner": "acme/r"}, "author": {"login": "me"}}]}


def gh_stub(log):
    def run(args, timeout=30):
        log.append(list(args))
        if args[:2] == ["api", "rate_limit"]:
            return "30"
        if args[:2] == ["api", "user"]:
            return "me"
        flags = " ".join(args)
        kind = "merged" if "--merged-at" in flags else "reviewed" if "--reviewed-by" in flags else "opened"
        return json.dumps(PRS[kind])
    return run


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

    def test_terminal_and_browser_attention_split_you_agent_browser(self):
        make_private(config.TT_DIR / "private.db", self.day)
        text = self.build()
        self.assertIn("| `HD-123` | Fix the intake form validation | 1h 05m | 20m | 15m |", text)
        self.assertIn("| No ticket: work |  | 2h 10m | - | - |", text)
        for leak in ("personal", "gh:me/dots#3", "HD-5`", "50m |"):       # personal, noise, unproductive 3000s
            self.assertNotIn(leak, text)

    def test_unattributed_time_is_labelled_not_dropped(self):
        make_private(config.TT_DIR / "private.db", self.day)
        self.assertRegex(self.build(), r"No ticket: work \|[^\n]*2h 10m")

    def test_no_private_db_means_no_attention_table(self):
        text = self.build()
        self.assertNotIn("Terminal and browser attention", text)
        self.assertIn("## Time by item", text)               # the clock table is still there

    def test_header_carries_the_timesheet_number(self):
        c = sqlite3.connect(config.TT_DIR / "work.db")
        c.execute("CREATE TABLE v_day_worked (attendance_day TEXT, net_minutes INTEGER)")
        c.execute("INSERT INTO v_day_worked VALUES (?, 372)", (self.day.isoformat(),))
        c.commit()
        c.close()
        self.assertIn("Worked 7h (timesheet 6h 12m) · 2 items closed", self.build())

    def test_prs_opened_merged_reviewed_company_only_read_only(self):
        log = []
        sources_gh.run = gh_stub(log)
        text = self.build()
        sec = text.split("## PRs")[1]
        self.assertIn("Opened:\n1. `gh:acme/r#7` Add retries", sec)
        self.assertIn("Merged:\n1. `gh:acme/r#6` Fix lint [email]", sec)
        self.assertIn("Reviewed:\n1. `gh:acme/r#9` Their change", sec)
        self.assertNotIn("me/dots", sec)                      # personal repo
        self.assertNotIn("#7` Add retries", sec.split("Reviewed:")[1])   # my own PR is not a review
        self.assertEqual(sorted(a[0] for a in log), ["api", "api", "search", "search", "search"])
        self.assertIn(f"--created={self.day.isoformat()}", " ".join(log[2]))
        self.assertFalse([a for a in log if any(x in ("-X", "--method", "comment", "review", "close") for x in a)])

    def test_offline_gh_says_unavailable_and_the_rest_renders(self):
        text = self.build()                                   # helpers: gh raises GhError
        self.assertIn("## PRs\nunavailable", text)
        self.assertIn("2 items closed", text)
        self.assertIn("`HD-123` Fix the intake form validation — 1h 40m", text)

    def test_unavailable_never_overwrites_an_earlier_pr_section(self):
        t = self.t0 + 23 * 3600
        sources_gh.run = gh_stub([])
        self.assertEqual(report.write(self.day, self.cfg, "logout", now=t), "created")
        sources_gh.run = lambda *a, **k: (_ for _ in ()).throw(sources_gh.GhError("offline"))
        self.assertEqual(report.write(self.day, self.cfg, None, now=t), "unchanged")
        self.assertIn("gh:acme/r#7", (self.cfg.report_dir / f"{self.day.isoformat()}.md").read_text())

    def test_pr_section_is_scrubbed_and_idempotent(self):
        sources_gh.run = gh_stub([])
        t = self.t0 + 23 * 3600
        report.write(self.day, self.cfg, "logout", now=t)
        self.assertEqual(report.write(self.day, self.cfg, None, now=t), "unchanged")
        self.assertNotIn("ada@", (self.cfg.report_dir / f"{self.day.isoformat()}.md").read_text())

    def test_dur(self):
        self.assertEqual([report.dur(s) for s in (0, 59, 60, 3599, 3600, 3660, 22320)], ["", "", "1m", "59m", "1h", "1h 01m", "6h 12m"])


if __name__ == "__main__":
    unittest.main()
