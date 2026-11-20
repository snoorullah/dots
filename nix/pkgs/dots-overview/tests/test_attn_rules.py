"""Per-repo attention rules (ATTN_REPO_RULES), Slack alert channels, and the `src` of every item."""
import json
import time
import unittest

import helpers
from dots_overview import atomic, attention, config, notifylog, sources_gh, sources_notify, sync

LOGIN = 10_000
NOW = 20_000


def task(ref, state="review:open", **kw):
    t = {"uuid": "u" * 8 + ref, "tags": ["attn"], "src": "gh", "srcstate": state, "ref": ref, "desc": ref,
         "entry_ts": 1}
    t.update(kw)
    return t


def meta(**by_ref):
    return {r: dict({"updatedTs": NOW - 5}, **m) for r, m in by_ref.items()}


def refs(items):
    return [i["ref"] for i in items]


class Rules(unittest.TestCase):
    def test_parse_modes_and_legacy_ignore_key(self):
        cfg = config.Work({"ATTN_REPO_RULES": "app-v2:explicit acme/app-v3:block rfcs:new ops:split bad:nope",
                           "ATTN_IGNORE_REPOS": "old-repo"})
        self.assertEqual(cfg.attn_mode("gh:acme/app-v2#1"), "explicit")
        self.assertEqual(cfg.attn_mode("gh:acme/app-v3#1"), "block")
        self.assertEqual(cfg.attn_mode("gh:other/app-v3#1"), "block" if False else None)
        self.assertEqual(cfg.attn_mode("gh:acme/old-repo#1"), "block")
        self.assertEqual(cfg.attn_mode("gh:acme/ops#1"), "split")
        self.assertIsNone(cfg.attn_mode("gh:acme/bad#1"))
        self.assertTrue(cfg.attn_ignored("gh:acme/old-repo#1"))

    def test_block_drops_everything(self):
        cfg = config.Work({"ATTN_REPO_RULES": "app-v3:block"})
        out = attention.from_tasks([task("gh:acme/app-v3#1"), task("gh:acme/x#2")], NOW, cfg, meta(), LOGIN)
        self.assertEqual(refs(out), ["gh:acme/x#2"])

    def test_explicit_keeps_individual_mention_and_feedback_only(self):
        cfg = config.Work({"ATTN_REPO_RULES": "app-v2:explicit"})
        tasks = [task("gh:acme/app-v2#1"), task("gh:acme/app-v2#2"), task("gh:acme/app-v2#3"),
                 task("gh:acme/app-v2#4", "pr:open", tags=["mirror"]), task("gh:acme/app-v2#5", "issue:open")]
        m = meta(**{"gh:acme/app-v2#1": {"individual": True}, "gh:acme/app-v2#3": {"mention": True},
                    "gh:acme/app-v2#4": {"feedback": True}})
        out = attention.from_tasks(tasks, NOW, cfg, m, LOGIN)
        self.assertEqual(refs(out), ["gh:acme/app-v2#1", "gh:acme/app-v2#3", "gh:acme/app-v2#4"])

    def test_split_marks_old_requests_previous_and_not_waiting(self):
        cfg = config.Work({"ATTN_REPO_RULES": "ops:split"})
        m = {"gh:acme/ops#1": {"updatedTs": LOGIN - 100}, "gh:acme/ops#2": {"updatedTs": LOGIN + 100}}
        out = {i["ref"]: i for i in attention.from_tasks(
            [task("gh:acme/ops#1"), task("gh:acme/ops#2")], NOW, cfg, m, LOGIN)}
        self.assertEqual(out["gh:acme/ops#1"]["section"], "previous")
        self.assertFalse(out["gh:acme/ops#1"]["waiting"])
        self.assertEqual(out["gh:acme/ops#2"]["section"], "main")
        self.assertTrue(out["gh:acme/ops#2"]["waiting"])
        self.assertEqual(out["gh:acme/ops#2"]["ageSec"], NOW - (LOGIN + 100))   # GitHub's time, not mirror creation

    def test_new_drops_requests_older_than_login(self):
        cfg = config.Work({"ATTN_REPO_RULES": "rfcs:new"})
        m = {"gh:acme/rfcs#1": {"updatedTs": LOGIN - 1}, "gh:acme/rfcs#2": {"updatedTs": LOGIN + 1}}
        out = attention.from_tasks([task("gh:acme/rfcs#1"), task("gh:acme/rfcs#2")], NOW, cfg, m, LOGIN)
        self.assertEqual(refs(out), ["gh:acme/rfcs#2"])

    def test_unknown_login_filters_nothing(self):
        cfg = config.Work({"ATTN_REPO_RULES": "rfcs:new ops:split"})
        out = attention.from_tasks([task("gh:acme/rfcs#1"), task("gh:acme/ops#1")], NOW, cfg,
                                   {"gh:acme/rfcs#1": {"updatedTs": 1}}, None)
        self.assertEqual(len(out), 2)
        self.assertTrue(all(i["section"] == "main" for i in out))


def fake_gh(rows_by_flag, views=None):
    calls = []

    def run(args, timeout=30):
        calls.append(args)
        if args[:2] == ["api", "rate_limit"]:
            return "30\n"
        if args[:2] == ["api", "user"]:
            return "me\n"
        if args[:2] == ["pr", "view"]:
            return json.dumps((views or {}).get(args[2], {"comments": [], "reviews": []}))
        for flag, rows in rows_by_flag.items():
            if any(a.startswith(flag) for a in args):
                return json.dumps(rows)
        return "[]"
    return run, calls


def row(n, repo="acme/app-v2", upd="2026-10-28T00:00:00Z"):
    return {"number": n, "title": f"t{n}", "url": f"https://x/{n}", "state": "open",
            "repository": {"nameWithOwner": repo}, "author": {"login": "bob"}, "updatedAt": upd}


class GhFetch(helpers.Scratch):
    def _fetch(self, rules, rows, views=None):
        run, calls = fake_gh(rows, views)
        sources_gh.run = run
        return sources_gh.fetch(config.Work({"ATTN_REPO_RULES": rules}), sleep=lambda s: None,
                                now=sources_gh.epoch("2026-10-29T00:00:00Z")), calls

    def test_individual_request_is_recorded_team_request_is_not(self):
        items, calls = self._fetch("", {"--review-requested": [row(1), row(2)],
                                        "--user-review-requested": [row(1)]})
        by = {i["ref"]: i for i in items if i["kind"] == "review"}
        self.assertTrue(by["gh:acme/app-v2#1"]["individual"])
        self.assertFalse(by["gh:acme/app-v2#2"]["individual"])
        self.assertLessEqual(len([c for c in calls if c[0] == "search"]), sources_gh.MAX_SEARCH)

    def test_mentions_become_mention_items(self):
        items, _ = self._fetch("", {"--mentions": [row(9)]})
        self.assertEqual([(i["kind"], i["mention"]) for i in items], [("mention", True)])

    def test_own_pr_feedback_only_when_someone_else_spoke_last(self):
        views = {"5": {"comments": [{"author": {"login": "me"}, "createdAt": "2026-10-28T01:00:00Z"},
                                    {"author": {"login": "bob"}, "createdAt": "2026-10-28T02:00:00Z"}], "reviews": []},
                 "6": {"comments": [{"author": {"login": "bob"}, "createdAt": "2026-10-28T01:00:00Z"},
                                    {"author": {"login": "me"}, "createdAt": "2026-10-28T02:00:00Z"}], "reviews": []}}
        items, _ = self._fetch("app-v2:explicit", {"--author": [row(5), row(6)]}, views)
        fb = {i["ref"]: i["feedback"] for i in items if i["kind"] == "pr"}
        self.assertEqual(fb, {"gh:acme/app-v2#5": True, "gh:acme/app-v2#6": False})

    def test_no_pr_views_without_explicit_rules(self):
        _, calls = self._fetch("", {"--author": [row(5)]})
        self.assertFalse([c for c in calls if c[0] == "pr"])

    def test_gh_never_writes(self):
        _, calls = self._fetch("app-v2:explicit", {"--author": [row(5)]})
        verbs = {c[0] + " " + (c[1] if len(c) > 1 else "") for c in calls}
        self.assertTrue(verbs <= {"api rate_limit", "api user", "search issues", "search prs", "pr view"})


class SyncMeta(helpers.Scratch):
    def test_sync_writes_gh_meta_sidecar(self):
        helpers.FakeTw(self)

        class G:
            @staticmethod
            def fetch(cfg, sleep=None):
                return [{"ref": "gh:acme/r#1", "src": "gh", "kind": "review", "repo": "acme/r", "url": "u",
                         "title": "t", "state": "open", "updatedAt": "2026-10-28T00:00:00Z", "work": False,
                         "individual": True, "mention": False, "feedback": False}]
        sync.run(config.Work({}), gh=G, erp=type("E", (), {"state_for": staticmethod(lambda c, m: ("off", "x"))}),
                 now=5)
        doc = atomic.read_json(config.STATE_DIR / "gh-meta.json", {})
        self.assertTrue(doc["refs"]["gh:acme/r#1"]["individual"])
        self.assertGreater(doc["refs"]["gh:acme/r#1"]["updatedTs"], 1_700_000_000)


class MentionReachesAttention(helpers.Scratch):
    def test_mention_item_synced_then_surfaced_without_hand_set_tags(self):
        ftw = helpers.FakeTw(self)
        item = {"ref": "gh:acme/app-v2#9", "src": "gh", "kind": "mention", "title": "ping", "state": "open",
                "url": "u", "work": True}
        self.assertTrue(sync.ensure(item, 5))
        self.assertIn("attn", ftw.tasks[0]["tags"])
        cfg = config.Work({"ATTN_REPO_RULES": "app-v2:explicit"})
        out = attention.from_tasks(ftw.tasks, NOW, cfg, meta(**{"gh:acme/app-v2#9": {"mention": True}}), LOGIN)
        self.assertEqual(refs(out), ["gh:acme/app-v2#9"])


class MetaFailSafe(helpers.Scratch):
    def test_explicit_passes_tagged_items_when_meta_untrusted(self):
        cfg = config.Work({"ATTN_REPO_RULES": "app-v2:explicit"})
        t = [task("gh:acme/app-v2#1")]
        self.assertEqual(attention.from_tasks(t, NOW, cfg, {}, LOGIN), [])
        self.assertEqual(refs(attention.from_tasks(t, NOW, cfg, {}, LOGIN, trust_meta=False)), ["gh:acme/app-v2#1"])

    def test_meta_trusted_needs_file_fresh_ts_and_ok_gh(self):
        ok = {"state": "ok"}
        doc = {"ts": NOW, "refs": {}}
        self.assertTrue(attention.meta_trusted(doc, ok, NOW))
        self.assertFalse(attention.meta_trusted(None, ok, NOW))
        self.assertFalse(attention.meta_trusted(doc, {"state": "stale"}, NOW))
        self.assertFalse(attention.meta_trusted(doc, None, NOW))
        self.assertFalse(attention.meta_trusted(dict(doc, ts=NOW - attention.STALE_SYNC - 1), ok, NOW))

    def test_build_without_gh_meta_keeps_explicit_items(self):
        ftw = helpers.FakeTw(self)
        ftw.seed(desc="r", tags=["attn"], src="gh", srcstate="review:open", ref="gh:acme/app-v2#1")
        config.CONF.write_text("ATTN_REPO_RULES=app-v2:explicit\n")
        doc = attention.build(ftw.tasks, [], NOW)
        self.assertIn("gh:acme/app-v2#1", [i["ref"] for i in doc["items"]])


class FeedbackCarry(GhFetch):
    def _prior(self, **refs_):
        atomic.write_json(config.STATE_DIR / "gh-meta.json", {"v": 1, "ts": 1, "refs": refs_})

    def test_failed_view_keeps_previous_feedback(self):
        self._prior(**{"gh:acme/app-v2#5": {"feedback": True}})
        run, _ = fake_gh({"--author": [row(5)]})

        def flaky(args, timeout=30):
            if args[:2] == ["pr", "view"]:
                raise sources_gh.GhError("boom")
            return run(args, timeout)
        sources_gh.run = flaky
        items = sources_gh.fetch(config.Work({"ATTN_REPO_RULES": "app-v2:explicit"}), sleep=lambda s: None,
                                 now=sources_gh.epoch("2026-10-29T00:00:00Z"))
        self.assertTrue([i for i in items if i["kind"] == "pr"][0]["feedback"])

    def test_pr_beyond_view_cap_keeps_previous_feedback(self):
        self._prior(**{"gh:acme/app-v2#2": {"feedback": True}})
        run, _ = fake_gh({})
        sources_gh.run = run
        cfg = config.Work({"ATTN_REPO_RULES": "app-v2:explicit"})
        its = [sources_gh._item(row(n), "pr", cfg) for n in (1, 2)]
        sources_gh._feedback(its, cfg, sources_gh.epoch("2026-10-29T00:00:00Z"), views=1)
        self.assertEqual([i["feedback"] for i in its], [False, True])


class SlackAlerts(helpers.Scratch):
    def _log(self, *summaries):
        p = config.STATE_DIR / "notifications.jsonl"
        now = int(time.time())
        for i, s in enumerate(summaries):
            notifylog.append(p, {"ts": now, "app": "Slack", "summary": s, "body": None, "urgency": "normal", "id": i})
        return now

    def test_alert_channel_becomes_alert_item(self):
        now = self._log("New message in acme-cicd-alerts", "New message from Ada", "#prod-alerts: disk full",
                        "New message in general")
        items, _ = sources_notify.read(now, config.Work({}))
        by = {i["title"]: i for i in items}
        a = by["New message in acme-cicd-alerts"]
        self.assertEqual((a["kind"], a["waiting"], a["src"]), ("alert", False, "alert"))
        self.assertEqual(by["#prod-alerts: disk full"]["kind"], "alert")
        self.assertEqual(by["New message from Ada"]["kind"], "dm")
        self.assertEqual(by["New message from Ada"]["src"], "slack")
        self.assertEqual(by["New message in general"]["kind"], "dm")

    def test_custom_patterns(self):
        now = self._log("New message in acme-pager", "New message in acme-cicd-alerts")
        items, _ = sources_notify.read(now, config.Work({"SLACK_ALERT_CHANNELS": "*-pager, oncall*"}))
        self.assertEqual({i["title"]: i["kind"] for i in items},
                         {"New message in acme-pager": "alert", "New message in acme-cicd-alerts": "dm"})

    def test_alert_counts_as_failed_not_waiting(self):
        now = self._log("New message in acme-cicd-alerts")
        doc = attention.build([], [], now)
        self.assertEqual((doc["counts"]["failed"], doc["counts"]["waiting"]), (1, 0))


class SrcField(helpers.Scratch):
    def test_every_item_has_a_known_src(self):
        now = int(time.time())
        p = config.STATE_DIR / "notifications.jsonl"
        notifylog.append(p, {"ts": now, "app": "Slack", "summary": "New message from Ada", "body": None,
                             "urgency": "normal", "id": 1})
        atomic.write_json(config.STATE_DIR / "inbox.json", {"updated": now, "waiting_me": 2, "replied": 0})
        live = [{"pane": "w1:p1", "status": "blocked", "workspace": "w1", "sess": "s"}]
        from dots_overview import herdr
        herdr.waiting, real = (lambda s, sub=None: True), herdr.waiting
        self.addCleanup(setattr, herdr, "waiting", real)
        doc = attention.build([task("gh:acme/r#1"), task("TASK-1", "task:overdue", src="erp", tags=["attn"]),
                               task("c1", "task:open", src="claude", entry_ts=now - 5)], live, now)
        srcs = {i["id"].split(":")[0] + ":" + str(i["src"]) for i in doc["items"]}
        self.assertTrue({"dm:slack", "mail:mail", "blocker:herdr", "review:gh"} <= srcs, srcs)
        self.assertTrue(all(i["src"] in {"mail", "slack", "gh", "erp", "alert", "ops", "herdr", "claude", "timetrack"}
                            for i in doc["items"]))

    def test_mail_item_carries_no_content(self):
        now = int(time.time())
        atomic.write_json(config.STATE_DIR / "inbox.json", {"updated": now, "waiting_me": 3})
        doc = attention.build([], [], now)
        m = [i for i in doc["items"] if i["src"] == "mail"][0]
        self.assertEqual((m["kind"], m["waiting"], m["title"]), ("mail", True, "3 mails waiting on you"))


if __name__ == "__main__":
    unittest.main()
