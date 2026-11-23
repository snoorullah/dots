"""agent_metrics: tokens, cost estimate, ledger spans, incremental scan. Fixtures are neutral."""
import json
import sqlite3
import time
import unittest
from datetime import datetime, timezone

import helpers
from dots_overview import agent_metrics as am
from dots_overview import config

NOW = int(datetime(2026, 3, 10, 15, 0, 0).timestamp())
TODAY = "2026-03-10"


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def msg(ts, mid, model, i=1, o=2, cw=3, cr=4):
    return json.dumps({"type": "assistant", "timestamp": iso(ts), "message": {
        "id": mid, "model": model,
        "usage": {"input_tokens": i, "output_tokens": o, "cache_creation_input_tokens": cw,
                  "cache_read_input_tokens": cr}, "content": [{"type": "text", "text": "SECRET"}]}}) + "\n"


class Fx(helpers.Scratch):
    def setUp(self):
        super().setUp()
        self.proj = self.root / "projects"
        (self.proj / "p1" / "sessA" / "subagents").mkdir(parents=True)
        self.fa = self.proj / "p1" / "sessA.jsonl"
        self.fs = self.proj / "p1" / "sessA" / "subagents" / "agent-1.jsonl"
        self.dm = am.DayMap()


class TestPrice(unittest.TestCase):
    def test_known_and_unknown(self):
        # official list prices (USD/MTok): Sonnet 5.5 input $2, Opus 5.5 cache read $0.20
        self.assertEqual(am.cost_usd("claude-sonnet-5-5", 1_000_000, 0, 0, 0), 2.00)
        self.assertAlmostEqual(am.cost_usd("claude-opus-5-5", 0, 0, 0, 1_000_000), 0.20)
        self.assertAlmostEqual(am.cost_usd("claude-fable-5-2", 0, 1_000_000, 0, 0), 40.00)
        self.assertEqual(am.price_for("claude-opus-5-5[1m]")[0], 4.00)
        self.assertIsNone(am.cost_usd("mystery-model", 10, 10, 10, 10))

    def test_specific_before_generic(self):
        self.assertLess(am.price_for("claude-opus-5")[1], am.price_for("claude-opus-4-1")[1])
        self.assertEqual(am.price_for("claude-opus-5-5")[0], 4.00)   # not swallowed by claude-opus-5
        self.assertEqual(am.price_for("claude-opus-5")[0], 5.00)


class TestScan(Fx):
    def test_tokens_dedupe_and_no_content(self):
        t = NOW - 100
        self.fa.write_text(msg(t, "m1", "claude-sonnet-5-5") + msg(t, "m1", "claude-sonnet-5-5", o=9)
                           + msg(t, "m2", "<synthetic>", i=0, o=0, cw=0, cr=0))
        st = am.scan_file(self.fa, None, self.dm)
        slot = st["days"][TODAY]["claude-sonnet-5-5"]
        self.assertEqual(slot, [1, 9, 3, 4, 1])          # last write of m1 replaces the first
        self.assertNotIn("SECRET", json.dumps(st))

    def test_incremental_offset_and_boundary_replace(self):
        t = NOW - 100
        self.fa.write_text(msg(t, "m1", "claude-sonnet-5-5"))
        st = am.scan_file(self.fa, None, self.dm)
        with open(self.fa, "a") as f:
            f.write(msg(t, "m1", "claude-sonnet-5-5", o=7) + msg(t, "m2", "claude-sonnet-5-5"))
            f.write('{"type":"assistant","partial')       # unfinished line is left for next time
        st2 = am.scan_file(self.fa, st, self.dm)
        self.assertEqual(st2["days"][TODAY]["claude-sonnet-5-5"], [2, 9, 6, 8, 2])
        st3 = am.scan_file(self.fa, st2, self.dm)
        self.assertEqual(st3["days"], st2["days"])

    def test_truncated_file_restarts(self):
        t = NOW - 100
        self.fa.write_text(msg(t, "m1", "claude-sonnet-5-5") * 1 + msg(t, "m2", "claude-sonnet-5-5"))
        st = am.scan_file(self.fa, None, self.dm)
        self.fa.write_text(msg(t, "m9", "claude-sonnet-5-5"))
        st = am.scan_file(self.fa, st, self.dm)
        self.assertEqual(st["days"][TODAY]["claude-sonnet-5-5"][4], 1)

    def test_session_of(self):
        self.assertEqual(am._session_of(self.fa, self.proj), ("sessA", False))
        self.assertEqual(am._session_of(self.fs, self.proj), ("sessA", True))

    def test_daymap_uses_work_session_day(self):
        a = int(datetime(2026, 3, 9, 22, 0).timestamp())
        dm = am.DayMap([(a, a + 6 * 3600, "2026-03-09")])
        self.assertEqual(dm(a + 4 * 3600), "2026-03-09")      # past midnight, still that session's day
        self.assertEqual(dm(a + 20 * 3600), "2026-03-10")


class TestLedger(unittest.TestCase):
    def rows(self):
        T = NOW - 3600
        mk = lambda a, ts, s="sessA", **k: dict(action=a, ts=ts, sess=s, agent="Alpha", **k)
        return [mk("session", T - 5, ticket="TASK-1"), mk("prompt", T), mk("stop", T + 600),
                mk("prompt", T + 900), mk("stop", T + 1200)]

    def test_spans(self):
        names, tickets, per = am.ledger_facts(self.rows(), am.DayMap(), NOW)
        self.assertEqual(names["sessA"], "Alpha")
        self.assertEqual(tickets["sessA"], "TASK-1")
        x = per[(TODAY, "sessA")]
        self.assertEqual((x["prompts"], x["active"], x["wait"]), (2, 900, 300))

    def test_unanswered_prompt_runs_to_now_and_waiting_is_capped(self):
        T = NOW - 600
        rows = [dict(action="prompt", ts=T, sess="s", agent="A")]
        self.assertEqual(am.ledger_facts(rows, am.DayMap(), NOW)[2][(TODAY, "s")]["active"], 600)
        rows = [dict(action="prompt", ts=NOW - 20000, sess="s", agent="A"), dict(action="stop", ts=NOW - 19000, sess="s"),
                dict(action="prompt", ts=NOW - 100, sess="s")]
        self.assertEqual(am.ledger_facts(rows, am.DayMap(), NOW)[2][(TODAY, "s")]["wait"], am.WAIT_CAP_SEC)


class TestBuildRun(Fx):
    def write_state(self):
        sd = config.STATE_DIR
        sd.mkdir(parents=True, exist_ok=True)
        T = NOW - 3600
        led = [dict(action="prompt", ts=T, sess="sessA", agent="Alpha", ticket="TASK-1"),
               dict(action="stop", ts=T + 600, sess="sessA", agent="Alpha", ticket="TASK-1")]
        (sd / "sessions.jsonl").write_text("".join(json.dumps(r) + "\n" for r in led))

    def test_run_end_to_end(self):
        self.write_state()
        t = NOW - 1800
        self.fa.write_text(msg(t, "m1", "claude-sonnet-5-5", 1_000_000, 0, 0, 0)
                           + msg(t, "m2", "mystery", 5, 5, 5, 5))
        self.fs.write_text(msg(t, "s1", "claude-sonnet-5-5", 1_000_000, 0, 0, 0))
        doc = am.run(now=NOW, projects_dir=self.proj, with_live=False)
        today = doc["periods"]["today"]
        self.assertEqual(today["runs"], 1)
        self.assertEqual(today["prompts"], 1)
        self.assertEqual(today["activeMin"], 10.0)
        self.assertEqual(today["tokens"]["in"], 2_000_005)
        self.assertEqual(today["unpricedTokens"], 20)
        self.assertAlmostEqual(today["costUsd"], 4.0, 3)           # 2M Sonnet 5.5 input tokens at $2/MTok, mystery excluded
        self.assertEqual(today["byAgent"][0]["key"], "Alpha")
        self.assertEqual(today["byTicket"][0]["key"], "TASK-1")
        self.assertAlmostEqual(today["subagentShare"], 0.5, 2)
        unk = [m for m in today["byModel"] if m["key"] == "mystery"][0]
        self.assertIsNone(unk["costUsd"])
        self.assertEqual(len(doc["days"]), 30)
        self.assertTrue(doc["costIsEstimate"])
        on_disk = json.loads((config.STATE_DIR / "agent-metrics.json").read_text())
        self.assertEqual(on_disk["today"], TODAY)
        self.assertNotIn("SECRET", json.dumps(on_disk))

    def test_second_run_reads_nothing_new_and_deltas(self):
        self.write_state()
        self.fa.write_text(msg(NOW - 1800, "m1", "claude-sonnet-5-5"))
        am.run(now=NOW, projects_dir=self.proj, with_live=False)
        calls = []
        orig = am.scan_file
        am.scan_file = lambda *a, **k: calls.append(a) or orig(*a, **k)
        try:
            doc = am.run(now=NOW, projects_dir=self.proj, with_live=False)
        finally:
            am.scan_file = orig
        self.assertEqual(calls, [])
        # yesterday had nothing: delta == today's total
        self.assertEqual(doc["periods"]["today"]["delta"]["tokens"], 10)

    def test_missing_everything_is_empty_not_a_crash(self):
        doc = am.run(now=NOW, projects_dir=self.root / "nope", with_live=False)
        self.assertEqual(doc["periods"]["today"]["tokens"]["total"], 0)
        self.assertIsNone(doc["periods"]["today"]["costUsd"])


if __name__ == "__main__":
    unittest.main()
