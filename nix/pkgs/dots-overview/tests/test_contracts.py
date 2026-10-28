"""Every emitted file validates against its schema in docs/contracts, and a bad one does not."""
import copy
import json
import stat
import time
import unittest

import helpers
import schema
from dots_overview import atomic, attention, cli, config, heatmap, nowstate, sources_notify, sync


class Contracts(helpers.Scratch):
    def setUp(self):
        super().setUp()
        self.tw = helpers.FakeTw(self)
        self.tw.seed(desc="Review the detection rules", ref="gh:acme/repo#886", src="gh", url="https://example.com/1",
                     srcstate="review:open", tags=["mirror", "attn"], entry_ts=int(time.time()) - 600)
        self.tw.seed(desc="claude work", src="claude", agent="Vega", sess="abc", pane="w1:p1", wspace="w1",
                     tags=["mirror", "attn"], start_ts=int(time.time()) - 60, entry_ts=int(time.time()) - 900)

    def check(self, name, doc):
        errs = schema.errors(doc, schema.load(name))
        self.assertEqual(errs, [], f"{name}: {errs}")

    def test_all_six_files_validate(self):
        cli.cmd_fast(type("A", (), {"apps": "today"}))
        cli._put("mirror", sync.mirror_doc(int(time.time())))
        for name in ("now", "activity", "attention", "heatmap", "mirror", "meta"):
            path = config.STATE_DIR / f"{name}.json"
            self.assertTrue(path.exists(), name)
            self.check(name, json.loads(path.read_text()))

    def test_files_are_0600_and_dir_0700(self):
        cli.cmd_fast(type("A", (), {"apps": "today"}))
        for p in config.STATE_DIR.glob("*.json"):
            self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600, p.name)
        self.assertEqual(stat.S_IMODE(config.STATE_DIR.stat().st_mode), 0o700)

    def test_schema_rejects_wrong_version_and_shape(self):
        doc = attention.build(self.tw.tasks, [], int(time.time()))
        self.check("attention", doc)
        bad = copy.deepcopy(doc)
        bad["v"] = 2
        self.assertTrue(schema.errors(bad, schema.load("attention")))
        bad = copy.deepcopy(doc)
        bad["counts"].pop("failed")
        self.assertTrue(schema.errors(bad, schema.load("attention")))
        bad = copy.deepcopy(doc)
        bad["items"][0]["urgency"] = "loud"
        self.assertTrue(schema.errors(bad, schema.load("attention")))

    def test_heatmap_is_119_days_with_scores_0_to_4(self):
        doc = heatmap.build([], now=int(time.time()))
        self.check("heatmap", doc)
        self.assertEqual(len(doc["days"]), 119)
        self.assertEqual(doc["spanDays"], 119)

    def test_heatmap_score_ramp(self):
        self.assertEqual([heatmap.score(s, 100) for s in (0, 1, 25, 26, 50, 75, 76, 100)], [0, 1, 1, 2, 2, 3, 4, 4])
        self.assertEqual(heatmap.score(10, 0), 0)

    def test_attention_ranks_waiting_first_and_counts(self):
        now = int(time.time())
        live = [{"pane": "w9:p9", "tab": "w9:t1", "workspace": "w9", "sess": "s9", "status": "blocked", "cwd": "/x"}]
        doc = attention.build(self.tw.tasks, live, now)
        self.check("attention", doc)
        self.assertEqual(doc["items"][0]["kind"], "blocker")
        self.assertTrue(all(i["waiting"] for i in doc["items"][:2]))
        self.assertEqual(doc["counts"]["waiting"], sum(i["waiting"] for i in doc["items"]))
        self.assertEqual(doc["sources"]["mail"]["state"], "unavailable")
        self.assertEqual(doc["sources"]["mail"]["detail"], "no local mail store")

    def test_failed_ops_job_is_red_and_nobody_waits(self):
        config.OPS_STATE.mkdir(parents=True)
        (config.OPS_STATE / "disk-watch.json").write_text(json.dumps(
            {"job": "disk-watch", "status": "fail", "summary": "/ 97%", "changed": int(time.time()) - 5}))
        (config.OPS_STATE / "net-watch.json").write_text(json.dumps(
            {"job": "net-watch", "status": "warn", "summary": "slow", "changed": int(time.time())}))
        doc = attention.build([], [], int(time.time()))
        self.check("attention", doc)
        self.assertEqual(doc["counts"], {"waiting": 0, "failed": 1, "total": 1})

    def test_now_has_focus_block_and_rolls_over(self):
        t0 = 1_000_000
        nowstate.focus_cmd("start", minutes=25, now=t0)
        f = nowstate.focus_block(now=t0 + 60)
        self.assertEqual((f["state"], f["elapsedSec"], f["targetSec"]), ("running", 60, 1500))
        self.assertEqual(nowstate.focus_block(now=t0 + 1500)["state"], "break")
        self.assertEqual(nowstate.focus_block(now=t0 + 1500 + 300)["state"], "idle")
        doc = nowstate.build(self.tw.tasks, [], {"state": "in", "awayReason": None, "sinceTs": 1}, now=t0 + 10)
        self.check("now", doc)

    def test_dm_items_come_from_slack_notifications_only(self):
        from dots_overview import notifylog
        now = int(time.time())
        p = config.STATE_DIR / "notifications.jsonl"
        for app, summ in (("Slack", "New message from Ada"), ("Slack", "#general: lunch"), ("other", "hello")):
            notifylog.append(p, {"ts": now, "app": app, "summary": summ, "body": None, "urgency": "normal", "id": 1})
        items, src = sources_notify.read(now)
        self.assertEqual([i["title"] for i in items], ["New message from Ada"])
        self.assertEqual(src["state"], "ok")


class Atomic(helpers.Scratch):
    def test_replace_failure_leaves_target_intact(self):
        import os
        p = config.STATE_DIR / "x.json"
        atomic.write_json(p, {"v": 1, "a": 1})
        real = os.replace

        def boom(*a):
            raise OSError("disk gone")
        os.replace = boom
        try:
            with self.assertRaises(OSError):
                atomic.write_json(p, {"v": 1, "a": 2})
        finally:
            os.replace = real
        self.assertEqual(json.loads(p.read_text())["a"], 1)

    def test_hard_kill_before_replace_leaves_tmp_and_old_target(self):
        import subprocess
        import sys
        p = config.STATE_DIR / "y.json"
        atomic.write_json(p, {"a": 1})
        code = ("import os,sys;sys.path.insert(0,%r);from dots_overview import atomic;"
                "os.replace=lambda *a: os._exit(9);atomic.write_json(%r,{'a':2})" % (str(helpers.HERE.parent), str(p)))
        r = subprocess.run([sys.executable, "-c", code])
        self.assertEqual(r.returncode, 9)
        self.assertEqual(json.loads(p.read_text())["a"], 1)
        self.assertTrue(list(p.parent.glob("y.json.*.tmp")))

    def test_mode_is_0600(self):
        p = config.STATE_DIR / "z.json"
        atomic.write_json(p, {})
        self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
