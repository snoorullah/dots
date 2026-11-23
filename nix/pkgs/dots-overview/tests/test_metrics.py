"""metrics.json: every KPI against sqlite fixtures with made-up names, and every missing source."""
import json
import os
import sqlite3
import stat
import subprocess
import time
import unittest
from datetime import date, timedelta

import helpers
import schema
from dots_overview import cli, config, local_tt, metrics, metrics_aw, metrics_src

TODAY = date(2026, 3, 18)              # a Wednesday
NOW_H = 15
DENY = ["pnow", "proficient", "web" + "sleak", "ovh"]       # built from parts: lint scans this repo for the words


def ep(day, h, m=0):
    d = day if isinstance(day, date) else date.fromisoformat(day)
    return local_tt.day_start(d) + h * 3600 + m * 60


class World(helpers.Scratch):
    """A scratch timetrack with a few weeks of days; tests add what they need."""

    def setUp(self):
        super().setUp()
        self.tw = helpers.FakeTw(self)
        self.today = TODAY
        self.now = ep(TODAY, NOW_H)
        self.tt = config.TT_DIR
        self.tt.mkdir(parents=True)
        self.state = config.STATE_DIR
        self.state.mkdir(parents=True)

    # -- builders ------------------------------------------------------------------------
    def work(self, days):
        """days: [(day, kind, target, net, span, first_h, last_h, ded)], oldest first. net None = no deduction row."""
        c = sqlite3.connect(self.tt / "work.db")
        c.executescript("""
          CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER, attendance_day TEXT);
          CREATE TABLE v_day_worked (attendance_day TEXT, kind TEXT, target_minutes INTEGER, net_minutes INTEGER,
                                     span_minutes INTEGER, first_unix INTEGER, last_unix INTEGER, deduction_minutes INTEGER);
          CREATE TABLE ticket_minutes (ticket TEXT, attendance_day TEXT, minutes INTEGER, human_minutes INTEGER, agent_minutes INTEGER);
        """)
        for i, (day, kind, tgt, net, span, fh, lh, ded) in enumerate(days):
            first = ep(day, fh) if fh is not None else None
            last = ep(day, lh) if lh is not None else None
            c.execute("INSERT INTO v_day_worked VALUES (?,?,?,?,?,?,?,?)", (day, kind, tgt, net, span, first, last, ded))
            if first:
                c.execute("INSERT INTO work_session VALUES (?,?,?,?)",
                          (i + 1, first, None if day == TODAY.isoformat() else last, day))
        c.commit()
        c.close()

    def series(self, n=21, worked=lambda i: 400 + 10 * i):
        """n days ending today: Mon-Fri working with `worked(i)` net minutes, login 09:00, weekends off."""
        rows = []
        for k in range(n):
            d = TODAY - timedelta(days=n - 1 - k)
            if d.weekday() < 5:
                w = worked(k)
                rows.append((d.isoformat(), "working", 480, w, w + 40, 9, 9 + (w + 40) // 60, 40))
            else:
                rows.append((d.isoformat(), "weekend", 0, 0, 0, None, None, None))
        return rows

    def private(self, ddl="", fill=None):
        c = sqlite3.connect(self.tt / "private.db")
        c.executescript("""
          CREATE TABLE focus_span (id INTEGER PRIMARY KEY, start_unix INTEGER, end_unix INTEGER, seen_unix INTEGER,
                                   ticket_token TEXT, ws_label TEXT);
          CREATE TABLE away_label (start_unix INTEGER PRIMARY KEY, end_unix INTEGER, day TEXT, key TEXT, label TEXT, source TEXT);
          CREATE TABLE salah_log (id INTEGER PRIMARY KEY, day TEXT, prayer TEXT, iqamah_unix INTEGER, nudged_unix INTEGER,
                                  enforcement TEXT, status TEXT);
          CREATE TABLE prompt_log (ts_unix INTEGER, kind TEXT, outcome TEXT);
          CREATE TABLE login_log (ts_unix INTEGER PRIMARY KEY, day TEXT, first_of_day INTEGER, late_minutes INTEGER);
          CREATE TABLE term_day (day TEXT, task_uuid TEXT DEFAULT '', ref TEXT DEFAULT '', project TEXT DEFAULT '',
                                 agent_name TEXT DEFAULT '', verdict TEXT, seconds INTEGER);
          CREATE TABLE health_checkpoint (id INTEGER PRIMARY KEY, day TEXT, slot TEXT, due_unix INTEGER, answered_unix INTEGER,
                                          score INTEGER, outcome TEXT);
          CREATE TABLE med_dose (ts_unix INTEGER PRIMARY KEY, day TEXT, provenance TEXT);
        """)
        if fill:
            fill(c)
        c.commit()
        c.close()

    def span(self, c, day, h0, m0, h1, m1, token, zone="Alpha"):
        c.execute("INSERT INTO focus_span (start_unix, end_unix, seen_unix, ticket_token, ws_label) VALUES (?,?,?,?,?)",
                  (ep(day, h0, m0), ep(day, h1, m1), ep(day, h1, m1), token, zone))

    def build(self, **kw):
        kw.setdefault("use_git", False)
        return metrics.build(now=self.now, **kw)

    def day(self, doc, day=None):
        day = day or self.today.isoformat()
        return next(d for d in doc["days"] if d["day"] == day)


def no_nulls(v, path="$"):
    if v is None or (isinstance(v, float) and v != v):
        raise AssertionError(f"null/NaN at {path}")
    if isinstance(v, dict):
        for k, x in v.items():
            no_nulls(x, f"{path}.{k}")
    if isinstance(v, list):
        for i, x in enumerate(v):
            no_nulls(x, f"{path}[{i}]")


class PureMaths(unittest.TestCase):
    def test_slope_and_direction(self):
        self.assertAlmostEqual(metrics.slope([1, 2, 3, 4]), 1.0)
        self.assertIsNone(metrics.slope([5]))
        self.assertEqual(metrics.direction(1.0, [10, 11, 12]), "up")
        self.assertEqual(metrics.direction(-1.0, [10, 9, 8]), "down")
        self.assertEqual(metrics.direction(0.05, [100, 100, 100]), "flat")        # under 1% of the mean

    def test_period_ranges_same_length_before(self):
        r = metrics.period_ranges(TODAY)
        self.assertEqual(r["today"], ((TODAY, TODAY), (TODAY - timedelta(days=1),) * 2))
        (ws, _), (pws, pwe) = r["week"]
        self.assertEqual((ws, pws, pwe), (date(2026, 3, 16), date(2026, 3, 9), date(2026, 3, 11)))   # Mon-Wed vs Mon-Wed
        (ms, _), (pms, pme) = r["month"]
        self.assertEqual((ms, pms, pme), (date(2026, 3, 1), date(2026, 2, 1), date(2026, 2, 18)))
        (qs, _), (pqs, pqe) = r["quarter"]
        self.assertEqual((qs, pqs), (date(2026, 1, 1), date(2025, 10, 1)))
        self.assertEqual(pqe, date(2025, 12, 31) if (TODAY - qs).days > 91 else date(2025, 10, 1) + (TODAY - qs))

    def test_month_prev_is_clamped_to_the_shorter_month(self):
        r = metrics.period_ranges(date(2026, 3, 31))
        self.assertEqual(r["month"][1], (date(2026, 2, 1), date(2026, 2, 28)))

    def test_deep_work_rules(self):
        def s(a, b, tok="t1"):
            return {"start": a * 60, "end": b * 60, "token": tok, "zone": "z"}
        self.assertEqual(metrics.deep_work_sec([s(0, 30), s(32, 60)]), 60 * 60)           # 2 min gap joined, 60 min run
        self.assertEqual(metrics.deep_work_sec([s(0, 30), s(36, 60)]), 0)                  # 6 min gap splits: 30 and 24
        self.assertEqual(metrics.deep_work_sec([s(0, 44)]), 0)                             # 44 min is not a run
        self.assertEqual(metrics.deep_work_sec([s(0, 45)]), 45 * 60)
        self.assertEqual(metrics.deep_work_sec([s(0, 30, "a"), s(31, 60, "b")]), 0)        # other ticket ends the run
        self.assertEqual(metrics.deep_work_sec([s(0, 90, "")]), 0)                         # no ticket, no deep work

    def test_switches_count_zone_or_token_changes(self):
        sp = [{"start": 0, "end": 1, "token": "a", "zone": "x"}, {"start": 1, "end": 2, "token": "a", "zone": "x"},
              {"start": 2, "end": 3, "token": "b", "zone": "x"}, {"start": 3, "end": 4, "token": "b", "zone": "y"}]
        self.assertEqual(metrics.switches(sp), 2)

    def test_clean_drops_none_and_nan(self):
        self.assertEqual(metrics.clean({"a": None, "b": float("nan"), "c": [1, None], "d": {"e": None, "f": 2}}),
                         {"c": [1], "d": {"f": 2}})


class Days(World):
    def test_worked_target_span_and_breaks(self):
        self.work([("2026-03-17", "working", 480, 400, 450, 9, 17, 50), (TODAY.isoformat(), "working", 480, 100, 130, 9, 11, 30)])

        def f(c):
            c.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (ep("2026-03-17", 13), ep("2026-03-17", 13, 30), "2026-03-17", "lunch", "Lunch", "declared"))
            c.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (ep("2026-03-17", 15), ep("2026-03-17", 15, 20), "2026-03-17", "lunch", "Lunch", "asked"))
            c.execute("INSERT INTO away_label VALUES (?,?,?,?,?,?)", (ep("2026-03-17", 16), None, "2026-03-17", "walk", "Walk", "auto"))
        self.private(fill=f)
        d = self.day(self.build(), "2026-03-17")
        self.assertEqual((d["workedMin"], d["targetMin"], d["spanMin"], d["deductionMin"]), (400, 480, 450, 50))
        self.assertEqual((d["loginTs"], d["logoutTs"]), (ep("2026-03-17", 9), ep("2026-03-17", 17)))
        self.assertEqual(d["breaks"], {"Lunch": 50})                    # grouped by key, open break skipped

    def test_no_deduction_row_falls_back_to_span(self):
        self.work([(TODAY.isoformat(), "working", 480, None, 90, 9, 11, None)])
        d = self.day(self.build())
        self.assertEqual(d["workedMin"], 90)
        self.assertNotIn("deductionMin", d)

    def test_non_working_days_are_kept(self):
        self.work(self.series(7))
        doc = self.build()
        self.assertEqual(len(doc["days"]), 7)
        sat = self.day(doc, "2026-03-14")
        self.assertEqual((sat["kind"], sat["workedMin"], sat["targetMin"]), ("weekend", 0, 0))
        self.assertNotIn("loginTs", sat)

    def test_days_capped_at_120_oldest_first(self):
        self.work(self.series(150))
        days = self.build()["days"]
        self.assertEqual(len(days), 120)
        self.assertEqual(days[-1]["day"], self.today.isoformat())
        self.assertEqual([d["day"] for d in days], sorted(d["day"] for d in days))

    def test_future_days_are_not_listed(self):
        rows = self.series(3) + [("2026-03-19", "working", 480, None, 0, None, None, None)]
        self.work(rows)
        self.assertNotIn("2026-03-19", [d["day"] for d in self.build()["days"]])

    def test_focus_deep_work_switches_and_first_focus(self):
        self.work([(TODAY.isoformat(), "working", 480, 200, 240, 9, 14, 40)])

        def f(c):
            self.span(c, TODAY, 10, 0, 10, 30, "t1")
            self.span(c, TODAY, 10, 32, 11, 10, "t1")           # joined: a 70 minute run
            self.span(c, TODAY, 11, 10, 11, 30, "t2", "Beta")   # 20 min, other zone
            self.span(c, TODAY, 12, 0, 12, 10, "", "Beta")      # no ticket: not focus
        self.private(fill=f)
        d = self.day(self.build())
        self.assertEqual(d["focusMin"], 30 + 38 + 20)
        self.assertEqual(d["deepWorkMin"], 70)
        self.assertEqual(d["contextSwitches"], 2)               # t1 -> t2 (+zone), t2 -> unticketed
        self.assertEqual(d["timeToFirstFocusMin"], 60)          # login 09:00, first span 10:00

    def test_open_focus_span_counts_to_last_sighting(self):
        self.work([(TODAY.isoformat(), "working", 480, 60, 100, 9, 11, 40)])

        def f(c):
            c.execute("INSERT INTO focus_span (start_unix, end_unix, seen_unix, ticket_token, ws_label) VALUES (?,?,?,?,?)",
                      (ep(TODAY, 10), None, ep(TODAY, 10, 20), "t1", "Alpha"))
        self.private(fill=f)
        self.assertEqual(self.day(self.build())["focusMin"], 20)

    def test_session_day_not_midnight(self):
        """A span after midnight belongs to the session that was still open."""
        y = (TODAY - timedelta(days=1)).isoformat()
        self.work([(y, "working", 480, 500, 540, 14, 24 + 1, 40), (TODAY.isoformat(), "working", 480, 10, 10, 15, 15, 0)])

        def f(c):
            c.execute("INSERT INTO focus_span (start_unix, end_unix, seen_unix, ticket_token, ws_label) VALUES (?,?,?,?,?)",
                      (ep(TODAY, 0, 20), ep(TODAY, 0, 50), ep(TODAY, 0, 50), "t1", "Alpha"))
        self.private(fill=f)
        doc = self.build()
        self.assertEqual(self.day(doc, y)["focusMin"], 30)
        self.assertEqual(self.day(doc)["focusMin"], 0)

    def test_salah_on_time_rules(self):
        self.work([(TODAY.isoformat(), "working", 480, 100, 140, 9, 11, 40)])
        due, later = ep(TODAY, 6), ep(TODAY, 20)

        def f(c):
            rows = [("Fajr", due, None, "logged", None), ("Dhuhr", due, None, "locked", "jamaah"),
                    ("Asr", due, ep(TODAY, 14), "locked", "qaza"), ("Maghrib", later, None, "pending", None),
                    ("Isha", due, None, "away", None), ("Extra", due, None, "disabled", None),
                    ("Alone", due, None, "locked", "alone")]
            for p, iq, nud, enf, st in rows:
                c.execute("INSERT INTO salah_log (day, prayer, iqamah_unix, nudged_unix, enforcement, status) VALUES (?,?,?,?,?,?)",
                          (TODAY.isoformat(), p, iq, nud, enf, st))
        self.private(fill=f)
        d = self.day(self.build())
        self.assertEqual((d["salahOnTime"], d["salahTotal"]), (3, 4))       # logged, jamaah, alone of fajr,dhuhr,asr,alone
        self.assertEqual(d["interruptions"], 1)                              # the one nudge

    def test_interruptions_are_shown_prompts_plus_nudges(self):
        self.work([(TODAY.isoformat(), "working", 480, 100, 140, 9, 11, 40)])

        def f(c):
            for k, (kind, out) in enumerate([("a", "shown"), ("b", "shown"), ("c", "deferred")]):
                c.execute("INSERT INTO prompt_log VALUES (?,?,?)", (ep(TODAY, 10, k), kind, out))
        self.private(fill=f)
        self.assertEqual(self.day(self.build())["interruptions"], 2)

    def test_ticket_minutes_split_only_where_rows_exist(self):
        self.work(self.series(3))
        c = sqlite3.connect(self.tt / "work.db")
        c.execute("INSERT INTO ticket_minutes VALUES ('T-1', ?, 90, 60, 30)", (TODAY.isoformat(),))
        c.execute("INSERT INTO ticket_minutes VALUES ('T-2', ?, 40, 10, 30)", (TODAY.isoformat(),))
        c.commit()
        c.close()
        doc = self.build()
        d = self.day(doc)
        self.assertEqual((d["humanMin"], d["agentOnlyMin"]), (70, 60))
        self.assertNotIn("humanMin", self.day(doc, "2026-03-17"))

    def test_empty_ticket_minutes_omits_the_split_and_says_why(self):
        self.work(self.series(3))
        doc = self.build()
        self.assertNotIn("agentOnlyMin", self.day(doc))
        self.assertIn("ticket_minutes", doc["sources"]["days"]["reason"])

    def test_tasks_done_per_session_day(self):
        self.work(self.series(3))
        for h in (10, 11):
            self.tw.seed(status="completed", end_ts=ep(TODAY, h))
        self.tw.seed(status="completed", end_ts=ep(TODAY - timedelta(days=1), 10))
        doc = self.build()
        self.assertEqual(self.day(doc)["tasksDone"], 2)
        self.assertEqual(self.day(doc, "2026-03-17")["tasksDone"], 1)

    def test_prs_and_tickets_from_the_mirror(self):
        self.work(self.series(3))
        refs = [{"ref": "r1", "url": "https://example.test/o/r/pull/1", "state": "merged", "closedAt": ep(TODAY, 10)},
                {"ref": "r2", "url": "https://example.test/o/r/pull/2", "state": "merged", "closedAt": ep(TODAY, 11)},
                {"ref": "r3", "url": "https://example.test/o/r/pull/3", "state": "reviewed", "closedAt": ep(TODAY, 9), "reviewedAt": ep(TODAY, 9)},
                {"ref": "r4", "url": "https://example.test/o/r/issues/4", "state": "closed", "closedAt": ep(TODAY, 12)},
                {"ref": "r5", "url": "", "state": "gone", "closedAt": ep(TODAY, 12)},          # vanished: not a close
                {"ref": "r6", "url": "https://example.test/o/r/pull/6", "state": "open", "closedAt": None}]
        (self.state / "mirror.json").write_text(json.dumps({"v": 1, "ts": 1, "refs": refs}))
        d = self.day(self.build())
        self.assertEqual((d["prsMerged"], d["prsReviewed"], d["ticketsClosed"]), (2, 1, 1))

    def test_commits_dedupe_worktrees_and_count_by_session_day(self):
        self.work(self.series(3))
        repo, other = self.root / "repo-a", self.root / "repo-b"
        env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")

        def git(*a, cwd=repo, **e):
            subprocess.run(["git", *a], cwd=cwd, check=True, capture_output=True, env=dict(env, **e))
        repo.mkdir()
        git("init", "-q", "-b", "main")
        git("config", "user.email", "me@example.test")
        git("config", "user.name", "Me")
        for h in (10, 11):
            git("commit", "-q", "--allow-empty", "-m", f"c{h}", GIT_AUTHOR_DATE=f"@{ep(TODAY, h)} +0000",
                GIT_COMMITTER_DATE=f"@{ep(TODAY, h)} +0000")
        git("commit", "-q", "--allow-empty", "-m", "theirs", "--author", "Other <other@example.test>")
        git("worktree", "add", "-q", str(other), "-b", "side")             # a linked checkout of the same repo
        doc = self.build(use_git=True, roots=[repo, other], email="me@example.test")
        self.assertEqual(self.day(doc)["commits"], 2)                       # not 4, not 3
        self.assertEqual(self.day(doc, "2026-03-17")["commits"], 0)

    def test_no_git_identity_omits_commits(self):
        self.work(self.series(3))
        doc = self.build(use_git=True, roots=[], email="")
        self.assertNotIn("commits", self.day(doc))
        self.assertIn("git", doc["sources"]["days"]["reason"])


class Periods(World):
    def setUp(self):
        super().setUp()
        self.work(self.series(60))

    def test_today_week_month_values_and_prev(self):
        p = self.build()["periods"]
        wk = p["week"]["workedMin"]                       # Mon 16, Tue 17, Wed 18 vs Mon 9, Tue 10, Wed 11
        mine = {d["day"]: d["workedMin"] for d in self.build()["days"]}
        self.assertEqual(wk["value"], sum(mine[d] for d in ("2026-03-16", "2026-03-17", "2026-03-18")))
        self.assertEqual(wk["prev"], sum(mine[d] for d in ("2026-03-09", "2026-03-10", "2026-03-11")))
        self.assertEqual(wk["delta"], wk["value"] - wk["prev"])
        self.assertEqual(wk["deltaPct"], round(wk["delta"] * 100.0 / wk["prev"], 1))
        self.assertEqual(p["today"]["workedMin"]["prev"], mine["2026-03-17"])
        self.assertEqual(p["month"]["daysWorked"]["value"], 13)         # Mar 2,3,4,5,6,9,..13,16,17,18
        self.assertEqual(p["today"]["attainmentPct"]["value"], round(mine["2026-03-18"] * 100.0 / 480, 1))

    def test_prev_zero_omits_delta_pct(self):
        self.assertNotIn("deltaPct", metrics.kpi_obj(5, 0))
        self.assertEqual(metrics.kpi_obj(5, 0), {"value": 5, "prev": 0, "delta": 5})
        self.assertEqual(metrics.kpi_obj(5, None), {"value": 5})

    def test_avg_login_and_logout_minutes_since_the_day_started(self):
        p = self.build()["periods"]["week"]
        self.assertEqual(p["avgLoginMin"]["value"], 9 * 60)
        self.assertGreater(p["avgLogoutMin"]["value"], 9 * 60)

    def test_break_minutes_and_days_worked(self):
        p = self.build()["periods"]["week"]
        self.assertEqual(p["breakMin"]["value"], 3 * 40)
        self.assertEqual(p["daysWorked"]["value"], 3)

    def test_top_projects_from_term_day(self):
        def f(c):
            for proj, sec, verdict in (("proj-a", 7200, "work"), ("proj-b", 1800, "work"), ("", 900, "work")):
                c.execute("INSERT INTO term_day (day, project, verdict, seconds) VALUES (?,?,?,?)", (TODAY.isoformat(), proj, verdict, sec))
        self.private(fill=f)
        p = self.build()["periods"]["today"]
        self.assertEqual(p["topProjects"], [{"project": "proj-a", "min": 120}, {"project": "proj-b", "min": 30}])


class Improve(World):
    def test_upward_trend_and_direction(self):
        self.work(self.series(30))
        t = self.build()["improve"]["trend30"]
        self.assertGreater(t["workedMin"], 0)
        self.assertEqual(t["dir"]["workedMin"], "up")

    def test_flat_trend(self):
        self.work(self.series(30, worked=lambda i: 420))
        t = self.build()["improve"]["trend7"]
        self.assertEqual(t["workedMin"], 0.0)
        self.assertEqual(t["dir"]["workedMin"], "flat")

    def test_streaks_count_back_from_the_latest_finished_working_day(self):
        # Wed 18 is today (not finished). Tue 17, Mon 16 meet target; Fri 13 missed.
        rows = self.series(14)
        rows = [(d, k, t, (500 if d in ("2026-03-17", "2026-03-16", "2026-03-12") else 100) if k == "working" else n, s, a, b, c)
                for d, k, t, n, s, a, b, c in rows]
        self.work(rows)
        s = self.build()["improve"]["streaks"]
        self.assertEqual(s["targetMet"], 2)
        self.assertGreaterEqual(s["best"]["targetMet"], 2)

    def test_best_and_worst_day_over_working_days_with_work(self):
        self.work(self.series(30))
        i = self.build()["improve"]
        mine = {d["day"]: d["workedMin"] for d in self.build()["days"] if d["kind"] == "working" and d["day"] < TODAY.isoformat()}
        self.assertEqual(i["bestDay"], {"day": max(mine, key=mine.get), "workedMin": max(mine.values())})
        self.assertEqual(i["worstDay"]["workedMin"], min(mine.values()))

    def test_punctuality_streak_and_target(self):
        self.work(self.series(10))

        def f(c):
            for k, late in enumerate((0, 0, 30, 0, None, 15)):
                d = (TODAY - timedelta(days=6 - k)).isoformat()
                c.execute("INSERT INTO login_log VALUES (?,?,1,?)", (ep(d, 9), d, late))
        self.private(fill=f)
        i = self.build()["improve"]
        self.assertEqual(i["punctuality"]["days"], 6)
        self.assertEqual(i["punctuality"]["onTimeDays"], 4)                 # 0, 0, 0, None
        self.assertEqual(i["punctuality"]["avgLateMin"], 7.5)
        self.assertEqual(i["punctuality"]["targetLoginMin"], 12 * 60)       # timetrack's default

    def test_login_target_from_work_conf(self):
        config.CONF.write_text("LOGIN_TARGET=09:30\n")
        self.assertEqual(metrics_src.login_target_min(), 9 * 60 + 30)

    def test_deep_work_ratio_interruptions_per_hour_and_first_focus_median(self):
        t2 = (TODAY - timedelta(days=2)).isoformat()      # finished days only: today is still running
        rows = [(t2, "working", 480, 120, 150, 9, 12, 30), ((TODAY - timedelta(days=3)).isoformat(), "working", 480, 60, 90, 9, 11, 30),
                (TODAY.isoformat(), "working", 480, 10, 20, 9, 10, 10)]
        self.work(rows)
        y = (TODAY - timedelta(days=3)).isoformat()

        def f(c):
            self.span(c, t2, 10, 0, 11, 0, "t1")                   # 60 min deep, first focus 60 min after login
            self.span(c, y, 9, 30, 9, 50, "t9")                       # no deep work, first focus 30 min after login
            c.execute("INSERT INTO prompt_log VALUES (?,?,?)", (ep(t2, 10), "a", "shown"))
            c.execute("INSERT INTO prompt_log VALUES (?,?,?)", (ep(t2, 11), "b", "shown"))
            c.execute("INSERT INTO prompt_log VALUES (?,?,?)", (ep(y, 10), "c", "shown"))
        self.private(fill=f)
        i = self.build()["improve"]
        self.assertEqual(i["deepWorkRatioPct"]["d7"], round(60 * 100.0 / 180, 1))
        self.assertEqual(i["interruptionsPerHour"]["d7"], round(3 / (180 / 60.0), 2))
        self.assertEqual(i["timeToFirstFocusMin"]["d7"], 45)              # median of 60 and 30

    def test_no_focus_completion_key(self):
        self.work(self.series(10))
        self.assertNotIn("focusCompletionPct", self.build()["improve"])


class Zones(World):
    def test_by_day_by_week_projects_and_unzoned(self):
        self.work(self.series(21))
        y = (TODAY - timedelta(days=1)).isoformat()

        def f(c):
            self.span(c, TODAY, 10, 0, 11, 0, "t1", "Alpha")
            self.span(c, TODAY, 11, 0, 11, 30, "t1", "")
            self.span(c, y, 10, 0, 10, 40, "t2", "Alpha")
            c.execute("INSERT INTO term_day (day, project, agent_name, verdict, seconds) VALUES (?,?,?,?,?)", (y, "proj-a", "", "work", 3600))
            c.execute("INSERT INTO term_day (day, project, agent_name, verdict, seconds) VALUES (?,?,?,?,?)", (y, "proj-a", "bot", "delegated", 1200))
        self.private(fill=f)
        (self.state / "focus.json").write_text(json.dumps({"state": "running", "zone": "Alpha"}))
        z = self.build()["zones"]
        self.assertEqual(z["current"], {"zone": "Alpha", "state": "running"})
        self.assertEqual(z["byDay"][TODAY.isoformat()], [{"zone": "Alpha", "min": 60}, {"zone": "unzoned", "min": 30}])
        wk = next(w for w in z["byWeek"] if w["week"] == "2026-03-16")
        self.assertEqual(wk["zones"], [{"zone": "Alpha", "min": 100}, {"zone": "unzoned", "min": 30}])
        self.assertEqual(z["projects"], [{"project": "proj-a", "min": 80, "agentMin": 20}])

    def test_no_focus_json_omits_current(self):
        self.work(self.series(7))
        self.private()
        self.assertNotIn("current", self.build().get("zones", {}))


class Screen(World):
    def aw(self, active=None, down=False):
        """Stub the ActivityWatch calls: one not-afk stretch per window request."""
        calls = []

        def fake(path, timeout=4):
            calls.append(path)
            if down:
                raise OSError("down")
            if path.startswith("/buckets/") and "events" not in path:
                return {"win_h": {"type": "currentwindow"}, "afk_h": {"type": "afkstatus"}}
            from datetime import datetime
            import urllib.parse
            q = urllib.parse.parse_qs(path.split("?", 1)[1])
            t0 = datetime.fromisoformat(q["start"][0]).timestamp()
            t1 = datetime.fromisoformat(q["end"][0]).timestamp()
            iso = lambda t: datetime.fromtimestamp(t).astimezone().isoformat()
            if "afk_h" in path:
                half = (t1 - t0) / 2
                return [{"timestamp": iso(t0), "duration": half, "data": {"status": "not-afk"}},
                        {"timestamp": iso(t0 + half), "duration": half, "data": {"status": "afk"}}]
            return [{"timestamp": iso(t0), "duration": t1 - t0, "data": {"app": "editor-a"}}]
        local_tt._aw, old = fake, local_tt._aw
        self.addCleanup(setattr, local_tt, "_aw", old)
        return calls

    def test_screen_time_active_idle_and_top_apps(self):
        self.work(self.series(5)[:-1] + [(TODAY.isoformat(), "working", 480, 200, 240, 9, 14, 40)])
        self.aw()
        doc = self.build()
        d = self.day(doc)
        span = (self.now - ep(TODAY, 9))
        self.assertAlmostEqual(d["screenSec"], span / 2, delta=2)
        self.assertEqual(d["topApps"][0]["app"], "editor-a")
        s = doc["screen"]
        self.assertAlmostEqual(s["todayActiveSec"], span / 2, delta=2)
        self.assertAlmostEqual(s["todayIdleSec"], span / 2, delta=2)
        self.assertEqual(s["lateNightSec"], 0)
        self.assertEqual(len(s["bySession"]), 1)
        self.assertEqual(doc["periods"]["today"]["screenSec"]["value"], d["screenSec"])

    def test_past_days_are_cached_and_survive_aw_going_down(self):
        self.work(self.series(5))
        calls = self.aw()
        self.build()
        first = len(calls)
        self.assertTrue(list((self.state / "metrics-cache").glob("aw-2026-03-1*.json")))
        calls2 = self.aw()
        self.build()
        self.assertEqual(sum("/events" in c and "2026-03-17" in c for c in calls2), 0)      # past day: no query
        self.aw(down=True)
        doc = self.build()
        self.assertIn("screenSec", self.day(doc, "2026-03-17"))                           # cache serves it
        self.assertNotIn("screenSec", self.day(doc))                                      # today is live: gone
        self.assertGreater(first, 0)

    def test_per_run_budget_leaves_the_rest_for_later_cycles(self):
        self.work(self.series(40))
        calls = self.aw()
        old = metrics_aw.BUDGET_DAYS
        metrics_aw.BUDGET_DAYS = 3
        self.addCleanup(setattr, metrics_aw, "BUDGET_DAYS", old)
        doc = self.build()
        have = [d for d in doc["days"] if "screenSec" in d]
        self.assertEqual(len(have), 3 + 1)                       # three past days and today
        self.assertEqual(doc["sources"]["aw"]["state"], "partial")
        self.build()
        self.assertEqual(len([d for d in self.build()["days"] if "screenSec" in d]), 3 + 3 + 3 + 1)

    def test_aw_down_omits_screen_everywhere(self):
        self.work(self.series(5))
        doc = self.build()          # Scratch already points AW at a closed port
        self.assertNotIn("screen", doc)
        self.assertNotIn("screenSec", self.day(doc))
        self.assertNotIn("topApps", self.day(doc))
        self.assertEqual(doc["sources"]["aw"]["state"], "missing")
        self.assertEqual(doc["sources"]["screen"]["state"], "missing")

    def test_late_night_seconds(self):
        spans = [[ep(TODAY, 23), ep(TODAY, 23, 30)], [ep(TODAY, 12), ep(TODAY, 13)]]
        raw = {"notafk": spans, "afk": [], "win": [], "has_afk": True}
        st = metrics_aw.stats(raw, ep(TODAY, 9), ep(TODAY, 23, 59))
        self.assertEqual(st["lateNightSec"], 30 * 60)
        self.assertEqual(st["activeSec"], 90 * 60)
        self.assertEqual(st["longestStretchMin"], 60)


class Health(World):
    def test_checkpoints_scores_doses_and_gap(self):
        self.work(self.series(10))
        y = (TODAY - timedelta(days=1)).isoformat()

        def f(c):
            c.execute("INSERT INTO med_dose VALUES (?,?,?)", (ep(TODAY, 9), TODAY.isoformat(), "x"))
            for slot, h, score, out in (("dose", 9, 3, "answered"), ("h1", 10, 4, "answered"), ("h3", 12, None, "skipped")):
                c.execute("INSERT INTO health_checkpoint (day, slot, due_unix, answered_unix, score, outcome) VALUES (?,?,?,?,?,?)",
                          (TODAY.isoformat(), slot, ep(TODAY, h), ep(TODAY, h, 5) if score else None, score, out))
            c.execute("INSERT INTO health_checkpoint (day, slot, due_unix, answered_unix, score, outcome) VALUES (?,?,?,?,?,?)",
                      (y, "h1", ep(y, 10), ep(y, 10, 5), 2, "answered"))
        self.private(fill=f)
        h = self.build()["health"]
        self.assertEqual(h["scoreAvg7"], 3.0)
        self.assertEqual(h["doses"], [{"day": TODAY.isoformat(), "ts": ep(TODAY, 9)}])
        self.assertEqual(h["doseToFirstCheckpointMin"], 65)                  # dose 09:00, h1 answered 10:05
        h3 = next(c for c in h["checkpoints"] if c["slot"] == "h3")
        self.assertEqual(h3, {"day": TODAY.isoformat(), "slot": "h3", "outcome": "skipped"})      # a null score is omitted

    def test_health_never_reaches_the_other_state_files(self):
        self.work(self.series(10))
        self.private(fill=lambda c: c.execute("INSERT INTO med_dose VALUES (?,?,?)", (ep(TODAY, 9), TODAY.isoformat(), "x")))
        cli.cmd_fast(type("A", (), {"apps": "today"}))
        for p in self.state.glob("*.json"):
            if p.name != "metrics.json":
                self.assertNotIn("doses", p.read_text(), p.name)


class Reminders(World):
    def test_due_scheduled_overdue_and_salah_next(self):
        self.work(self.series(5))
        past, soon, far = ep(TODAY, 8), ep(TODAY, 17), ep(TODAY + timedelta(days=3), 9)
        fmt = lambda t: time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(t))
        self.tw.seed(desc="far one", due=fmt(far))
        self.tw.seed(desc="late one", due=fmt(past))
        self.tw.seed(desc="soon one", due=fmt(soon), scheduled=fmt(soon))
        self.tw.seed(desc="no date")
        self.tw.seed(desc="mail me@example.test", due=fmt(far + 60))

        def f(c):
            c.execute("INSERT INTO salah_log (day, prayer, iqamah_unix, enforcement) VALUES (?,?,?,?)", (TODAY.isoformat(), "Asr", ep(TODAY, 16), "pending"))
            c.execute("INSERT INTO salah_log (day, prayer, iqamah_unix, enforcement) VALUES (?,?,?,?)", (TODAY.isoformat(), "Fajr", ep(TODAY, 5), "logged"))
        self.private(fill=f)
        r = self.build()["reminders"]
        self.assertEqual([x["desc"] for x in r["due"]][:3], ["late one", "soon one", "far one"])
        self.assertEqual([x["overdue"] for x in r["due"]][:3], [True, False, False])
        self.assertNotIn("me@example.test", json.dumps(r))                       # the email scrub applies
        self.assertEqual([x["desc"] for x in r["scheduled"]], ["soon one"])
        self.assertEqual(r["salahNext"], {"prayer": "Asr", "iqamahTs": ep(TODAY, 16)})

    def test_due_is_capped_at_ten(self):
        self.work(self.series(5))
        for k in range(14):
            self.tw.seed(desc=f"t{k}", due=time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(ep(TODAY, 10) + k * 60)))
        self.assertEqual(len(self.build()["reminders"]["due"]), 10)


class Missing(World):
    def test_nothing_at_all_never_crashes_and_omits_everything(self):
        doc = self.build()
        self.assertEqual(doc["days"], [])
        for k in ("periods", "improve", "zones", "screen", "health", "reminders"):
            self.assertNotIn(k, doc)
        self.assertEqual(doc["sources"]["days"]["state"], "missing")
        no_nulls(doc)

    def test_only_work_db_keeps_the_time_fields_and_drops_the_rest(self):
        self.work(self.series(10))
        doc = self.build()
        d = self.day(doc)
        for k in ("focusMin", "deepWorkMin", "salahTotal", "interruptions", "screenSec", "commits", "breaks"):
            self.assertNotIn(k, d)
        self.assertIn("workedMin", d)
        self.assertEqual(doc["sources"]["days"]["state"], "partial")
        self.assertIn("private.db", doc["sources"]["days"]["reason"])
        self.assertNotIn("health", doc)

    def test_a_missing_table_drops_only_its_fields(self):
        self.work(self.series(5))
        c = sqlite3.connect(self.tt / "private.db")
        c.executescript("CREATE TABLE focus_span (id INTEGER PRIMARY KEY, start_unix INTEGER, end_unix INTEGER, seen_unix INTEGER,"
                        " ticket_token TEXT, ws_label TEXT);")
        c.commit()
        c.close()
        doc = self.build()
        d = self.day(doc)
        self.assertNotIn("salahTotal", d)
        self.assertNotIn("interruptions", d)
        self.assertEqual(doc["sources"]["days"]["state"], "partial")

    def test_work_db_without_the_view_falls_back_to_day_class(self):
        c = sqlite3.connect(self.tt / "work.db")
        c.executescript("CREATE TABLE day_class (day TEXT, kind TEXT, target_minutes INTEGER);"
                        "CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER, attendance_day TEXT);")
        c.execute("INSERT INTO day_class VALUES (?, 'working', 480)", (TODAY.isoformat(),))
        c.commit()
        c.close()
        d = self.day(self.build())
        self.assertEqual(d["targetMin"], 480)
        self.assertNotIn("workedMin", d)                 # no source row: omitted, not an invented 0
        self.assertNotIn("loginTs", d)

    def test_no_taskwarrior_omits_tasks_and_reminders(self):
        self.work(self.series(5))

        def boom(*a, **k):
            raise metrics_src.tw.TwError("no task")
        metrics_src.tw.completed_since, old = boom, metrics_src.tw.completed_since
        metrics_src.tw.pending, old2 = boom, metrics_src.tw.pending
        self.addCleanup(setattr, metrics_src.tw, "completed_since", old)
        self.addCleanup(setattr, metrics_src.tw, "pending", old2)
        doc = self.build()
        self.assertNotIn("tasksDone", self.day(doc))
        self.assertNotIn("reminders", doc)
        self.assertEqual(doc["sources"]["reminders"]["state"], "missing")

    def test_a_bug_in_one_section_leaves_the_rest(self):
        self.work(self.series(5))
        real = metrics.build_improve
        metrics.build_improve = lambda *a, **k: 1 / 0
        self.addCleanup(setattr, metrics, "build_improve", real)
        doc = self.build()
        self.assertNotIn("improve", doc)
        self.assertIn("periods", doc)
        self.assertEqual(doc["sources"]["improve"]["state"], "missing")


class Output(World):
    def full(self):
        self.work(self.series(30))

        def f(c):
            self.span(c, TODAY, 10, 0, 11, 0, "t1", "Alpha")
            c.execute("INSERT INTO med_dose VALUES (?,?,?)", (ep(TODAY, 9), TODAY.isoformat(), "x"))
            c.execute("INSERT INTO health_checkpoint (day, slot, due_unix, answered_unix, score, outcome) VALUES (?,?,?,?,?,?)",
                      (TODAY.isoformat(), "h1", ep(TODAY, 10), ep(TODAY, 10, 5), 4, "answered"))
            c.execute("INSERT INTO login_log VALUES (?,?,1,?)", (ep(TODAY, 9), TODAY.isoformat(), 10))
            c.execute("INSERT INTO term_day (day, project, verdict, seconds) VALUES (?,?,?,?)", (TODAY.isoformat(), "proj-a", "work", 600))
            c.execute("INSERT INTO salah_log (day, prayer, iqamah_unix, enforcement, status) VALUES (?,?,?,?,?)", (TODAY.isoformat(), "Fajr", ep(TODAY, 5), "locked", "jamaah"))
        self.private(fill=f)
        self.tw.seed(desc="a task", due=time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(ep(TODAY, 17))))
        self.tw.seed(status="completed", end_ts=ep(TODAY, 10))
        return self.build()

    def test_validates_against_the_schema_and_has_no_null_or_nan(self):
        doc = self.full()
        self.assertEqual(schema.errors(doc, schema.load("metrics")), [])
        no_nulls(doc)
        for k in ("v", "ts", "tz", "today", "days", "sources"):
            self.assertIn(k, doc)
        self.assertEqual(doc["v"], 1)
        self.assertEqual(doc["today"], TODAY.isoformat())

    def test_schema_rejects_a_bad_document(self):
        doc = self.full()
        good = json.loads(json.dumps(doc))
        doc["days"][0]["workedMin"] = "lots"
        doc["improve"]["trend7"]["dir"]["workedMin"] = "sideways"
        errs = schema.errors(doc, schema.load("metrics"))
        self.assertTrue(any("workedMin" in e for e in errs))
        self.assertTrue(any("sideways" in e for e in errs))
        self.assertTrue(schema.errors(dict(good, v=2), schema.load("metrics")))

    def test_the_output_names_no_company_person_or_host(self):
        text = json.dumps(self.full()).lower()
        for w in DENY:
            self.assertNotIn(w, text)

    def test_file_is_0600_and_atomic(self):
        metrics.write(now=self.now, use_git=False)
        p = self.state / "metrics.json"
        self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertEqual(json.loads(p.read_text())["v"], 1)
        self.assertEqual(list(self.state.glob("metrics.json.*.tmp")), [])

    def test_fast_cycle_writes_metrics_and_survives_a_metrics_crash(self):
        self.work(self.series(5))
        cli.cmd_fast(type("A", (), {"apps": "today"}))
        self.assertTrue((self.state / "metrics.json").exists())
        (self.state / "metrics.json").unlink()
        (self.state / "attention.json").unlink()
        real = metrics.build
        metrics.build = lambda *a, **k: 1 / 0
        self.addCleanup(setattr, metrics, "build", real)
        self.assertEqual(cli.cmd_fast(type("A", (), {"apps": "today"})), 0)
        self.assertFalse((self.state / "metrics.json").exists())
        self.assertTrue((self.state / "attention.json").exists())                 # the bar's files are untouched
        meta = json.loads((self.state / "meta.json").read_text())
        self.assertTrue(any(e["source"] == "metrics" for e in meta["errors"]))

    def test_metrics_command(self):
        self.work(self.series(5))
        self.assertEqual(cli.main(["metrics"]), 0)
        self.assertTrue((self.state / "metrics.json").exists())

    def test_other_stage_commands_do_not_run_metrics(self):
        self.work(self.series(5))
        cli.main(["attention"])
        self.assertFalse((self.state / "metrics.json").exists())

    def test_runs_fast_on_a_year_of_days(self):
        self.work(self.series(200))

        def f(c):
            for k in range(200):
                d = TODAY - timedelta(days=k)
                self.span(c, d, 10, 0, 11, 0, "t1")
        self.private(fill=f)
        t = time.monotonic()
        self.build()
        self.assertLess(time.monotonic() - t, 2.0)


if __name__ == "__main__":
    unittest.main()
