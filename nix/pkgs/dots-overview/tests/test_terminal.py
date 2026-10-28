"""activity.json carries terminal and browser attention: byRef, byProject, byAgent, and the
terminal app line read as its breakdown. All of it comes from timetrack's private.db, read-only."""
import sqlite3
import time
import unittest
import json
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

import helpers
import schema
from dots_overview import activity, config, local_tt

DDL = """
CREATE TABLE term_segment (start_unix INTEGER, end_unix INTEGER, task_uuid TEXT, ref TEXT,
  project TEXT, agent_name TEXT, verdict TEXT, activity TEXT, pane_id TEXT, cwd_secret TEXT,
  labelled_by TEXT);
CREATE TABLE web_visit (start_unix INTEGER, end_unix INTEGER, ticket TEXT, task_uuid TEXT);
"""


class TerminalAttention(helpers.Scratch):
    def setUp(self):
        super().setUp()
        self.tw = helpers.FakeTw(self)
        # pinned to noon of a workday: "now" from the real clock made these fail after midnight
        self.t0 = local_tt.workday_start(local_tt.workday(time.time()))
        self.now = self.t0 + 6 * 3600
        self.a = self.tw.seed(desc="Fix ingress", ref="HD-101", project="alpha")["uuid"]
        self.b = self.tw.seed(desc="Cluster upgrade", ref=None, project="beta")["uuid"]
        config.TT_DIR.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(config.TT_DIR / "private.db")
        self.db.executescript(DDL)
        self.stub("app_seconds", lambda *a, **k: [("com.mitchellh.ghostty", 7200), ("zen-beta", 600)])
        self.stub("project_intervals", lambda t0, now: [])
        self.stub("ref_seconds", lambda t0, t1: [])

    def stub(self, name, fn):
        self.addCleanup(setattr, local_tt, name, getattr(local_tt, name))
        setattr(local_tt, name, fn)

    def seg(self, a, b, **kw):
        row = dict(task_uuid=None, ref=None, project=None, agent_name=None, verdict="work",
                   activity="secret activity text", pane_id="w1:p1", cwd_secret="/home/x/private-repo",
                   labelled_by="llm")
        row.update(kw)
        self.db.execute("INSERT INTO term_segment VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                        (self.t0 + a, self.t0 + b) + tuple(row[k] for k in (
                            "task_uuid", "ref", "project", "agent_name", "verdict", "activity", "pane_id", "cwd_secret",
                            "labelled_by")))
        self.db.commit()

    def build(self):
        return activity.build([], self.tw.tasks, now=self.t0 + 7 * 3600, apps="all")["buckets"]["today"]

    def test_terminal_time_fills_ref_project_agent(self):
        self.seg(0, 1800, task_uuid=self.a, ref="HD-101", project="alpha", agent_name="Vega")
        self.seg(1800, 2400, task_uuid=self.b, agent_name="Vega")           # task only: ref and project via Taskwarrior
        self.seg(2400, 3000, project="gamma", verdict="delegated")
        t = self.build()
        self.assertEqual(t["byRef"], [{"ref": "HD-101", "sec": 1800, "title": "Fix ingress"}])
        self.assertEqual({p["project"]: p["sec"] for p in t["byProject"]}, {"alpha": 1800, "beta": 600, "gamma": 600})
        self.assertEqual(t["byAgent"], [{"agent": "Vega", "sec": 2400}])

    def test_browser_visits_add_to_the_same_ref(self):
        self.seg(0, 600, task_uuid=self.a, ref="HD-101", project="alpha")
        self.db.execute("INSERT INTO web_visit VALUES(?,?,?,?)", (self.t0 + 700, self.t0 + 1000, None, self.a))
        self.db.execute("INSERT INTO web_visit VALUES(?,?,?,?)", (self.t0 + 1100, self.t0 + 1200, "TASK-2026-00512", None))
        self.db.commit()
        refs = {r["ref"]: r["sec"] for r in self.build()["byRef"]}
        self.assertEqual(refs, {"HD-101": 900, "TASK-2026-00512": 100})

    def test_clock_time_is_not_added_on_top(self):
        self.stub("ref_seconds", lambda t0, t1: [("HD-101", 5000)])
        self.seg(0, 600, task_uuid=self.a, ref="HD-101")
        self.assertEqual(self.build()["byRef"][0]["sec"], 5000)             # max of the two, not 5600

    def test_terminal_app_line_reads_as_its_breakdown(self):
        self.seg(0, 3600, project="alpha", verdict="work")
        self.seg(3600, 4200, verdict="delegated")
        apps = {a["app"]: a for a in self.build()["byApp"]}
        self.assertEqual(apps["com.mitchellh.ghostty"]["detail"], "work 1h00m · delegated 10m")
        self.assertNotIn("detail", apps["zen-beta"])

    def test_a_default_verdict_is_called_unattributed(self):
        self.seg(0, 600, project="alpha")
        self.seg(600, 1800, verdict="unproductive", labelled_by="title")     # no evidence: a default
        self.seg(1800, 2000, verdict="unproductive", labelled_by="llm")      # the model said so
        detail = {a["app"]: a for a in self.build()["byApp"]}["com.mitchellh.ghostty"]["detail"]
        self.assertEqual(detail, "unattributed 20m \u00b7 work 10m \u00b7 unproductive 3m")

    def test_no_private_db_is_just_empty(self):
        (config.TT_DIR / "private.db").unlink()
        t = self.build()
        self.assertEqual((t["byRef"], t["byProject"], t["byAgent"]), ([], [], []))

    def test_labels_only_never_a_title_cwd_or_activity(self):
        self.seg(0, 600, task_uuid=self.a, ref="HD-101", project="alpha", agent_name="Vega")
        out = repr(self.build())
        for secret in ("secret activity text", "private-repo", "w1:p1"):
            self.assertNotIn(secret, out)

    def test_validates_against_the_contract(self):
        self.seg(0, 600, task_uuid=self.a, ref="HD-101", project="alpha", agent_name="Vega")
        doc = activity.build([], self.tw.tasks, now=self.t0 + 7 * 3600, apps="all")
        self.assertEqual(schema.errors(doc, schema.load("activity")), [])
        old = {"v": 1, "ts": 1, "buckets": {k: {"workedSec": 0, "tasksDone": 0, "byProject": [], "byApp": [], "byRef": []}
                                           for k in ("today", "week", "month", "quarter")}}
        self.assertTrue(schema.errors(old, schema.load("activity")))        # byAgent is required now


if __name__ == "__main__":
    unittest.main()


class AppSecondsAndProjects(unittest.TestCase):
    """The per-app line counts only time at the desk inside the window; timew tags are sorted."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self._state = local_tt.config.STATE_DIR
        local_tt.config.STATE_DIR = Path(self.tmp)
        self._aw = local_tt._aw

    def tearDown(self):
        local_tt.config.STATE_DIR = self._state
        local_tt._aw = self._aw

    def test_window_time_is_clipped_and_gated_by_presence(self):
        iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
        t0, t1 = 1_000_000, 1_000_000 + 8 * 3600
        win = [{"timestamp": iso(t0 - 3600), "duration": 10 * 3600, "data": {"app": "term", "title": "x"}}]
        afk = [{"timestamp": iso(t0 + 600), "duration": 1200, "data": {"status": "not-afk"}},
               {"timestamp": iso(t0 + 1800), "duration": 7 * 3600, "data": {"status": "afk"}}]

        def fake(path, timeout=3):
            if path == "/buckets/":
                return {"w": {"type": "currentwindow"}, "a": {"type": "afkstatus"}}
            return win if path.startswith("/buckets/w/") else afk
        local_tt._aw = fake
        self.assertEqual(local_tt.app_seconds(t0, t1, now=t1), [("term", 1200)])

    def test_project_is_the_tag_without_spaces(self):
        rows = [{"start": "20261028T100000Z", "end": "20261028T110000Z", "tags": ["Fix the thing", "dots"]},
                {"start": "20261028T110000Z", "end": "20261028T120000Z", "tags": ["solo"]}]
        p = subprocess.CompletedProcess([], 0, json.dumps(rows), "")
        with mock.patch.object(local_tt.subprocess, "run", return_value=p), \
                mock.patch.object(local_tt.Path, "is_dir", return_value=True):
            got = local_tt.project_intervals(0, 2_000_000_000)
        self.assertEqual([g[2] for g in got], ["dots", "unassigned"])


class Workday(helpers.Scratch):
    """A day is a work session, login -> logout, whatever the clock says (plan D1)."""

    def setUp(self):
        super().setUp()
        config.TT_DIR.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(config.TT_DIR / "work.db")
        db.execute("CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER,"
                   " attendance_day TEXT)")
        at = lambda d, h, m=0: int(datetime(2026, 10, d, h, m).timestamp())  # noqa: E731
        self.at = at
        # day 27: 19:27 -> 07:05 next morning; day 28: two overlapping sources, one still open
        db.executemany("INSERT INTO work_session (opened_unix, closed_unix, attendance_day) VALUES (?,?,?)",
                       [(at(27, 19, 27), at(28, 7, 5), "2026-10-27"), (at(28, 20, 24), None, "2026-10-28"),
                        (at(28, 20, 25), at(28, 23, 0), "2026-10-28")])
        db.commit()
        db.close()

    def test_past_midnight_is_still_the_sessions_day(self):
        self.assertEqual(str(local_tt.workday(self.at(28, 6, 30))), "2026-10-27")   # still in the 27th's session
        self.assertEqual(str(local_tt.workday(self.at(29, 0, 30))), "2026-10-28")   # after midnight, same session
        self.assertEqual(str(local_tt.workday(self.at(28, 12, 0))), "2026-10-27")   # logged out: the last session

    def test_bounds_are_login_to_logout_or_now(self):
        self.assertEqual(local_tt.day_bounds(datetime(2026, 10, 27).date()), (self.at(27, 19, 27), self.at(28, 7, 5)))
        now = self.at(29, 0, 30)
        self.assertEqual(local_tt.day_bounds(datetime(2026, 10, 28).date(), now), (self.at(28, 20, 24), now))
        self.assertEqual(local_tt.workday_start(datetime(2026, 10, 28).date()), self.at(28, 20, 24))

    def test_a_week_that_starts_on_a_day_off_begins_at_the_next_login(self):
        self.assertEqual(local_tt.workday_start(datetime(2026, 10, 26).date()), self.at(27, 19, 27))
