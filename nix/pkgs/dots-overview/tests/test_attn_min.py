"""ATTN_REPO_MIN: a repo's PRs and issues below the cutoff number never reach attention."""
import unittest

import helpers  # noqa: F401  (sets up the scratch state dir)
from dots_overview import attention, config


def task(ref, kind="review:open"):
    return {"uuid": ref.replace("/", "_").replace("#", "_").ljust(8, "x"), "tags": ["attn"], "src": "gh",
            "srcstate": kind, "ref": ref, "desc": ref, "entry_ts": 100}


class AttnRepoMin(unittest.TestCase):
    def test_below_cutoff_dropped_at_and_above_kept(self):
        cfg = config.Work({"ATTN_REPO_MIN": "app-v2:10000"})
        refs = [i["ref"] for i in attention.from_tasks(
            [task("gh:acme/app-v2#9999"), task("gh:acme/app-v2#10000"), task("gh:acme/app-v2#12345"),
             task("gh:acme/charts#5")], 200, cfg)]
        self.assertEqual(sorted(refs), ["gh:acme/app-v2#10000", "gh:acme/app-v2#12345", "gh:acme/charts#5"])

    def test_owner_repo_form_and_junk(self):
        cfg = config.Work({"ATTN_REPO_MIN": "acme/app-v2:100 bad:xx :5"})
        self.assertTrue(cfg.attn_below_min("gh:acme/app-v2#99"))
        self.assertFalse(cfg.attn_below_min("gh:acme/app-v2#100"))
        self.assertFalse(cfg.attn_below_min("gh:acme/bad#1"))
        self.assertFalse(cfg.attn_below_min("erp:HD 1"))


if __name__ == "__main__":
    unittest.main()
