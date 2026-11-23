"""Human/agent split derived from clock_event run_start/run_stop (made-up ids only)."""
import sqlite3
import unittest
from datetime import timedelta

import schema
import test_metrics as tm
from dots_overview import metrics

TODAY, EP = tm.TODAY, tm.ep
DAY = TODAY.isoformat()


class Split(tm.World):
    def events(self, evs, sessions=None, extra_ddl=""):
        """evs: [(session, day, h, m, kind, actor, ticket)]; sessions: {id: (day, closed (h,m) or None)}."""
        c = sqlite3.connect(self.tt / "work.db")
        c.executescript("""
          CREATE TABLE clock_event (id INTEGER PRIMARY KEY, ts TEXT, ts_unix INTEGER, attendance_day TEXT, session_id INTEGER,
                                    kind TEXT, ticket TEXT, actor TEXT, actor_ref TEXT, provenance TEXT DEFAULT 'live');
        """ + extra_ddl)
        c.execute("DELETE FROM work_session")
        for sid, (day, closed) in (sessions or {}).items():
            c.execute("INSERT INTO work_session VALUES (?,?,?,?)",
                      (sid, EP(day, 0), EP(day, *closed) if closed else None, day))
        for sid, day, h, m, kind, actor, ticket in evs:
            c.execute("INSERT INTO clock_event (ts, ts_unix, attendance_day, session_id, kind, ticket, actor) VALUES (?,?,?,?,?,?,?)",
                      ("x", EP(day, h, m), day, sid, kind, ticket, actor))
        c.commit()
        c.close()

    def runs(self, sid, a, b, actor, ticket=None, day=DAY):
        return [(sid, day, *a, "run_start", actor, ticket), (sid, day, *b, "run_stop", actor, None)]

    def setUp(self):
        super().setUp()
        self.work(self.series(5))

    def split(self, evs, sessions=None):
        self.events(evs, sessions or {1: (DAY, (14, 0))})
        doc = self.build()
        return doc, self.day(doc)


class SplitMaths(Split):
    def test_human_runs_are_a_union(self):
        evs = self.runs(1, (9, 0), (10, 0), "human") + self.runs(1, (9, 30), (10, 30), "human")
        _, d = self.split(evs)
        self.assertEqual(d["humanMin"], 90)

    def test_agent_only_excludes_human_overlap(self):
        evs = self.runs(1, (9, 0), (10, 0), "human") + self.runs(1, (9, 30), (11, 0), "agent")
        _, d = self.split(evs)
        self.assertEqual((d["humanMin"], d["agentOnlyMin"], d["agentOnlyRawMin"]), (60, 60, 60))

    def test_agent_inside_human_is_zero_agent_only(self):
        evs = self.runs(1, (9, 0), (11, 0), "human") + self.runs(1, (9, 30), (10, 0), "agent")
        _, d = self.split(evs)
        self.assertEqual((d["humanMin"], d["agentOnlyMin"]), (120, 0))

    def test_agent_only_capped_at_120_with_raw_kept(self):
        evs = self.runs(1, (9, 0), (12, 30), "agent")
        _, d = self.split(evs)
        self.assertEqual((d["agentOnlyMin"], d["agentOnlyRawMin"]), (120, 210))

    def test_concurrent_agents_with_anonymous_stops_pair_fifo(self):
        evs = [(1, DAY, 9, 0, "run_start", "agent", "a"), (1, DAY, 9, 10, "run_start", "agent", "b"),
               (1, DAY, 9, 30, "run_stop", "agent", None), (1, DAY, 10, 0, "run_stop", "agent", None)]
        _, d = self.split(evs)
        self.assertEqual(d["agentOnlyRawMin"], 60)          # union 9:00-10:00

    def test_system_stop_closes_everything_open(self):
        evs = [(1, DAY, 9, 0, "run_start", "human", None), (1, DAY, 9, 0, "run_start", "agent", "a"),
               (1, DAY, 10, 0, "run_stop", "system", None)]
        _, d = self.split(evs)
        self.assertEqual((d["humanMin"], d["agentOnlyMin"]), (60, 0))

    def test_stray_stop_is_ignored(self):
        evs = [(1, DAY, 9, 0, "run_stop", "human", None)] + self.runs(1, (10, 0), (10, 30), "human")
        _, d = self.split(evs)
        self.assertEqual(d["humanMin"], 30)


class Unclosed(Split):
    def test_closed_at_session_close(self):
        evs = [(1, DAY, 9, 0, "run_start", "human", None)]
        _, d = self.split(evs, {1: (DAY, (11, 0))})
        self.assertEqual(d["humanMin"], 120)

    def test_open_session_today_closes_at_now(self):
        evs = [(1, DAY, 12, 0, "run_start", "human", None)]
        _, d = self.split(evs, {1: (DAY, None)})
        self.assertEqual(d["humanMin"], (tm.NOW_H - 12) * 60)

    def test_unclosed_and_older_than_a_day_is_dropped(self):
        old = (TODAY - timedelta(days=3)).isoformat()
        evs = [(1, old, 9, 0, "run_start", "human", None)] + self.runs(2, (9, 0), (10, 0), "human")
        doc, _ = self.split(evs, {1: (old, None), 2: (DAY, (14, 0))})
        self.assertEqual(self.day(doc, old).get("humanMin"), 0)       # covered day, nothing counted
        self.assertEqual(self.day(doc)["humanMin"], 60)

    def test_run_never_extends_past_now(self):
        evs = [(1, DAY, 9, 0, "run_start", "agent", None)]
        _, d = self.split(evs, {1: (DAY, (23, 0))})
        self.assertEqual(d["agentOnlyRawMin"], (tm.NOW_H - 9) * 60)


class Sources(Split):
    def test_no_clock_event_rows_keeps_the_gap(self):
        self.events([], {})
        doc = self.build()
        self.assertNotIn("humanMin", self.day(doc))
        self.assertIn("no human/agent split", doc["sources"]["days"]["reason"])
        self.assertEqual(doc["sources"]["days"]["state"], "partial")

    def test_missing_clock_event_table_is_not_fatal(self):
        doc = self.build()
        self.assertNotIn("agentOnlyMin", self.day(doc))

    def test_with_data_sources_are_ok_and_periods_filled(self):
        evs = self.runs(1, (9, 0), (10, 0), "human") + self.runs(1, (9, 30), (11, 0), "agent")
        doc, _ = self.split(evs)
        for s in ("days", "periods", "improve"):
            self.assertNotIn("human/agent", doc["sources"][s]["reason"])
        self.assertEqual(doc["periods"]["today"]["humanMin"]["value"], 60)
        self.assertEqual(doc["periods"]["today"]["agentOnlyMin"]["value"], 60)
        self.assertEqual(doc["periods"]["today"]["agentOnlyRawMin"]["value"], 60)
        self.assertEqual(doc["periods"]["week"]["humanMin"]["value"], 60)
        self.assertEqual(schema.errors(doc, schema.load("metrics")), [])

    def test_days_before_first_run_have_no_split(self):
        _, d = self.split(self.runs(1, (9, 0), (10, 0), "human"))
        self.assertNotIn("humanMin", self.day(self.build(), "2026-03-17"))

    def test_ticket_minutes_used_when_clock_event_absent_and_beaten_when_present(self):
        c = sqlite3.connect(self.tt / "work.db")
        c.execute("INSERT INTO ticket_minutes VALUES ('T-1', ?, 90, 60, 30)", (DAY,))
        c.commit()
        c.close()
        self.assertEqual(self.day(self.build())["humanMin"], 60)
        self.events(self.runs(1, (9, 0), (10, 0), "human") + self.runs(1, (9, 30), (11, 0), "agent"))
        self.assertEqual(self.day(self.build())["humanMin"], 60)
        self.assertEqual(self.day(self.build())["agentOnlyMin"], 60)

    def test_per_ticket_split(self):
        evs = (self.runs(1, (9, 0), (10, 0), "human", "T-1") + self.runs(1, (10, 0), (10, 30), "human", "T-2") +
               self.runs(1, (11, 0), (11, 45), "agent", "T-2") + self.runs(1, (9, 30), (9, 45), "agent", "T-1"))
        doc, d = self.split(evs)
        t = {x["ticket"]: x for x in d["tickets"]}
        self.assertEqual((t["T-1"]["humanMin"], t["T-1"]["agentOnlyMin"]), (60, 0))
        self.assertEqual((t["T-2"]["humanMin"], t["T-2"]["agentOnlyMin"]), (30, 45))
        top = {x["ticket"]: x for x in doc["periods"]["today"]["topTickets"]}
        self.assertEqual(top["T-2"]["humanMin"], 30)

    def test_readonly_never_writes(self):
        self.split(self.runs(1, (9, 0), (10, 0), "human"))
        c = sqlite3.connect(self.tt / "work.db")
        self.assertEqual(c.execute("SELECT count(*) FROM clock_event").fetchone()[0], 2)


if __name__ == "__main__":
    unittest.main()
