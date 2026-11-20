"""now.json task.ticket: the human ticket for the bar ("HD 8580", "repo#212"), never an internal id."""
import json
import unittest

import helpers
from dots_overview import nowstate


class TicketFor(unittest.TestCase):
    def t(self, ref=None, desc="", **kw):
        return dict({"ref": ref, "desc": desc}, **kw)

    def test_hd_refs(self):
        self.assertEqual(nowstate.ticket_for(self.t("8635")), "HD 8635")
        self.assertEqual(nowstate.ticket_for(self.t("HD-8635")), "HD 8635")
        self.assertEqual(nowstate.ticket_for(self.t("HD 8635")), "HD 8635")

    def test_github_ref_is_repo_and_number_without_the_owner(self):
        self.assertEqual(nowstate.ticket_for(self.t("gh:acme/infra#212")), "infra#212")
        self.assertEqual(nowstate.ticket_for(self.t("gh:acme/infra#212", "a PR")), "infra#212")

    def test_hd_in_the_title(self):
        d = "TASK-2026-00846 Sophos source of Entra sign-ins (HD 8143)"
        self.assertEqual(nowstate.ticket_for(self.t("local:c99479", d)), "HD 8143")
        self.assertEqual(nowstate.ticket_for(self.t("local:abc123", "HD 8279: Cancel subscription")), "HD 8279")

    def test_erp_task_pairs_through_the_map(self):
        pairs = {"TASK-2026-00896": "HD 8580"}
        self.assertEqual(nowstate.ticket_for(self.t("TASK-2026-00896", "CI sizing"), pairs), "HD 8580")
        # a local task whose title names the TASK id
        self.assertEqual(nowstate.ticket_for(self.t("local:1", "TASK-2026-00896 CI sizing"), pairs), "HD 8580")

    def test_nothing_known_is_none_never_an_internal_id(self):
        self.assertIsNone(nowstate.ticket_for(self.t("TASK-2026-00906", "part b"), {}))
        self.assertIsNone(nowstate.ticket_for(self.t("local:6f2d51", "Fix it"), {}))
        self.assertIsNone(nowstate.ticket_for(self.t(None, "")))
        self.assertIsNone(nowstate.ticket_for(None))

    def test_explicit_hd_in_desc_beats_the_map(self):
        pairs = {"TASK-2026-00001": "HD 1111"}
        self.assertEqual(nowstate.ticket_for(self.t("TASK-2026-00001", "x (HD 2222)"), pairs), "HD 2222")


class TicketMap(helpers.Scratch):
    def test_reads_in_progress_and_sections(self):
        p = self.root / "snap.json"
        p.write_text(json.dumps({
            "inProgress": [{"id": "TASK-2026-00896", "also": ["HD 8580"]},
                           {"id": "TASK-2026-00583", "also": ["HD 07164", "HD 9"]}, {"id": "HD 1", "also": []}],
            "sections": [{"items": [{"id": "HD 8330", "title": "Harden Dockerfiles (TASK-2026-00879)"}]}]}))
        m = nowstate.load_ticket_map(p)
        self.assertEqual(m["TASK-2026-00896"], "HD 8580")
        self.assertEqual(m["TASK-2026-00583"], "HD 7164")
        self.assertEqual(m["TASK-2026-00879"], "HD 8330")

    def test_missing_or_bad_file_is_an_empty_map(self):
        self.assertEqual(nowstate.load_ticket_map(self.root / "nope.json"), {})
        bad = self.root / "bad.json"
        bad.write_text("{not json")
        self.assertEqual(nowstate.load_ticket_map(bad), {})
        bad.write_text("[1, 2]")
        self.assertEqual(nowstate.load_ticket_map(bad), {})


class BuildCarriesTicket(helpers.Scratch):
    def test_task_block_has_ticket(self):
        tasks = [{"uuid": "u1", "id": 1, "desc": "TASK-2026-00005 do it", "ref": "TASK-2026-00005", "start_ts": 5,
                  "tags": []}]
        doc = nowstate.build(tasks, [], {"state": "in"}, now=100, tickets={"TASK-2026-00005": "HD 77"})
        self.assertEqual(doc["task"]["ticket"], "HD 77")
        doc = nowstate.build(tasks, [], {"state": "in"}, now=100, tickets={})
        self.assertIsNone(doc["task"]["ticket"])


if __name__ == "__main__":
    unittest.main()
