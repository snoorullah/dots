"""Agents that wait on the owner reach attention: blocked, or finished and saying "needs you"."""
import json
import unittest

import helpers
from dots_overview import attention, herdr


def agent(status="done", sub=None, **kw):
    a = {"pane": "w1:p1", "tab": "w1:t1", "workspace": "w1", "sess": "s1", "status": status,
         "cwd": "/x", "name": "Nova", "sub": sub, "ticket": None}
    a.update(kw)
    return a


class Waiting(unittest.TestCase):
    def test_blocked_waits(self):
        self.assertTrue(herdr.waiting("blocked"))
        self.assertTrue(herdr.waiting("blocked", "whatever"))

    def test_done_or_idle_with_needs_you_waits(self):
        for st in ("done", "idle"):
            self.assertTrue(herdr.waiting(st, "needs you · ~30% · Waiting for you"))
        self.assertTrue(herdr.waiting("done", "NEEDS YOU"))

    def test_other_states_do_not(self):
        self.assertFalse(herdr.waiting("done", "review · PR #1541"))
        self.assertFalse(herdr.waiting("done", None))
        self.assertFalse(herdr.waiting("working", "needs you"))


class FromHerdr(unittest.TestCase):
    def test_needs_you_item(self):
        a = agent(sub="needs you · ~30%", ticket="lane:TASK-2026-00552")
        items = attention.from_herdr([a], 100)
        self.assertEqual(len(items), 1)
        i = items[0]
        self.assertEqual((i["kind"], i["src"], i["waiting"]), ("blocker", "herdr", True))
        self.assertEqual(i["title"], "Nova needs you")
        self.assertEqual(i["ref"], "lane:TASK-2026-00552")
        self.assertEqual(i["jump"], {"pane": "w1:p1", "workspace": "w1", "sess": "s1"})
        self.assertEqual(i["id"], "blocker:w1:p1")

    def test_falls_back_to_the_session_name(self):
        i = attention.from_herdr([agent("blocked", name=None)], 100)[0]
        self.assertTrue(i["title"].endswith(" needs you"))
        self.assertIsNone(i["ref"])

    def test_not_waiting_is_skipped(self):
        self.assertEqual(attention.from_herdr([agent("done", "review · report"), agent("working", "needs you")], 1), [])


class TaskTicket(unittest.TestCase):
    def test_task_items_carry_the_human_ticket(self):
        t = {"uuid": "u" * 8, "tags": [], "start_ts": 5, "src": "erp", "srcstate": "task:open", "entry_ts": 1,
             "ref": "TASK-2026-00781", "desc": "TASK-2026-00781 Fix the thing"}
        i = attention.from_tasks([t], 100, tickets={"TASK-2026-00781": "HD 8580"})[0]
        self.assertEqual(i["ticket"], "HD 8580")
        i = attention.from_tasks([dict(t, ref="local:0a1a4f", desc="Plain")], 100, tickets={})[0]
        self.assertIsNone(i["ticket"])


class Snapshot(helpers.Scratch):
    def test_snapshot_carries_name_sub_and_ticket(self):
        doc = {"result": {"snapshot": {"agents": [{
            "pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1", "agent_status": "done", "cwd": "/x",
            "display_agent": "CI health​", "agent_session": {"value": "s1"},
            "tokens": {"hp_sub": "needs you · ~30%", "ticket": "local:0a1a4f"}}]}}}
        herdr.run = lambda *a, **k: json.dumps(doc)
        a = herdr.snapshot()[0]
        self.assertEqual((a["name"], a["sub"], a["ticket"]), ("CI health", "needs you · ~30%", "local:0a1a4f"))

    def test_snapshot_without_tokens(self):
        doc = {"result": {"snapshot": {"agents": [{"pane_id": "p", "agent_status": "idle"}]}}}
        herdr.run = lambda *a, **k: json.dumps(doc)
        a = herdr.snapshot()[0]
        self.assertEqual((a["name"], a["sub"], a["ticket"]), (None, None, None))


if __name__ == "__main__":
    unittest.main()
