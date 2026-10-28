"""The task gate's pure logic: the Bash allowlist, switches, session resolution, the Stop verdict cache.

The end-to-end behaviour (real Taskwarrior, the hook script, the installer) is tests/taskgate.sh.
"""
import os
import time
import unittest

import helpers
from dots_overview import gate, task


class Allowlist(unittest.TestCase):
    def test_reads_and_the_way_out_are_open(self):
        for c in ("dots-task list", "dots-task new 'a; b (c)' --project p", 'dots-task new "a (b); c" --project p',
                  "git status", "git log --oneline", "git diff HEAD~1", "ls -la", "cat a.txt", "rg -n x .",
                  "grep -rn x .", "task list", "task ref.is:HD-1 export", "task 4 info", "pwd"):
            self.assertTrue(gate.allowlisted(c), c)

    def test_chaining_and_expansion_are_refused(self):
        for c in ("ls; id", "ls && id", "ls || id", "ls | sh", "cat $(id)", "ls `id`", "ls > f", "cat < f", "ls &",
                  "ls\nid", 'dots-task new "$(id)" --project p', 'dots-task new "a`id`" --project p',
                  "ls \\; id", "ls 'open", 'ls "open', "ls ${HOME}", "(ls)", "{ ls; }"):
            self.assertFalse(gate.allowlisted(c), c)

    def test_writes_and_look_alikes_are_refused(self):
        for c in ("task add x", "task done 1", "task modify 1 a", "task rc.hooks=1 list", "git push", "git commit -m x",
                  "git -c core.pager=x log", "git diff --output=f", "rg --pre ./x y", "rm -rf x", "echo hi",
                  "/tmp/x/git status", "/tmp/x/dots-task list", "python3 -c 1", ""):
            self.assertFalse(gate.allowlisted(c), c)


class State(helpers.Scratch):
    def test_declaration_opens_the_gate_only_with_a_task_or_exemption(self):
        self.assertFalse(task.declared_ok(task.read_decl("s1")))
        task.write_decl("s1", ref="X-1")
        self.assertFalse(task.declared_ok(task.read_decl("s1")))      # no uuid: not a binding
        task.write_decl("s1", uuid="u", ref="X-1")
        self.assertTrue(task.declared_ok(task.read_decl("s1")))
        task.write_decl("s2", exempt=True, reason="why")
        self.assertTrue(task.declared_ok(task.read_decl("s2")))

    def test_hostile_session_ids_never_touch_a_path(self):
        for s in ("../x", "a/b", "", "x" * 65, "a b"):
            self.assertIsNone(task.read_decl(s))

    def test_session_resolution_order(self):
        self.assertEqual(task.resolve_session({"CLAUDE_CODE_SESSION_ID": "env-s"}), ("env-s", "CLAUDE_CODE_SESSION_ID"))
        self.assertEqual(task.resolve_session({"DOTS_SESSION_ID": "d", "CLAUDE_CODE_SESSION_ID": "c"})[0], "d")
        self.assertEqual(task.resolve_session({"DOTS_SESSION_ID": "../x"}, cwd="/nowhere"), (None, None))
        now = int(time.time())
        task.touch_live("old", "/w", "w1:p1")
        task.touch_live("new", "/w", "w1:p1")
        task.atomic.write_json(task._p("live", "old"), {"v": 1, "sess": "old", "cwd": "/w", "pane": "w1:p1", "ts": now - 50})
        self.assertEqual(task.resolve_session({"HERDR_PANE_ID": "w1:p1"}, now=now), ("new", "pane"))
        self.assertEqual(task.resolve_session({}, cwd="/w/sub", now=now), ("new", "cwd"))
        self.assertEqual(task.resolve_session({}, cwd="/elsewhere", now=now), (None, None))
        self.assertEqual(task.resolve_session({"HERDR_PANE_ID": "w1:p1"}, now=now + 3 * 86400), (None, None))


class Switches(helpers.Scratch):
    def test_kill_file_and_env(self):
        self.assertFalse(gate.kill_switch({}))
        self.assertTrue(gate.kill_switch({"DOTS_TASK_GATE": "off"}))
        self.assertFalse(gate.kill_switch({"DOTS_TASK_GATE": "on"}))
        (task.config.CONF.parent).mkdir(parents=True, exist_ok=True)
        (task.config.CONF.parent / "task-gate-off").write_text("")
        self.assertTrue(gate.kill_switch({}))

    def test_headless_runs_are_exempt(self):
        self.assertTrue(gate.headless({"CLAUDE_CODE_ENTRYPOINT": "sdk-cli", "HERDR_PANE_ID": "w1:p1"}))
        self.assertFalse(gate.headless({}))
        self.assertFalse(gate.headless({"CLAUDE_CODE_ENTRYPOINT": "cli", "HERDR_PANE_ID": "w1:p1"}))

    def test_pretool_decisions(self):
        env = {"HERDR_PANE_ID": "w1:p1"}
        hook = {"session_id": "s1", "tool_name": "Edit", "tool_input": {}}
        self.assertIn("dots-task", gate.pretool(hook, env))
        self.assertIsNone(gate.pretool(dict(hook, tool_name="Read"), env))
        task.write_decl("s1", uuid="u", ref="X-1")
        self.assertIsNone(gate.pretool(hook, env))
        self.assertIsNone(gate.pretool(dict(hook, session_id="../bad"), env))      # fail open on junk


class StopVerdicts(helpers.Scratch):
    def setUp(self):
        super().setUp()
        task.write_decl("s1", uuid="uuid-1234", ref="X-1", title="Fix the form", project="p")
        # the prompt comes after the declaration: a turn declared after its prompt is never judged
        task.atomic.write_json(task._p("turn", "s1"), {"v": 1, "ts": int(time.time()) + 5, "hash": "h1",
                                                       "prompt": "write me a poem about the sea at night"})
        self.calls = []
        self.answers = ["different"]
        real = gate.ask_llm
        gate.ask_llm = lambda *a, **k: (self.calls.append(a), self.answers.pop(0) if self.answers else None)[1]
        self.addCleanup(setattr, gate, "ask_llm", real)

    def stop(self, **kw):
        return gate.stop(dict({"session_id": "s1"}, **kw), {"HERDR_PANE_ID": "w1:p1"}, time.monotonic() + 4)

    def test_blocks_once_then_never_for_that_prompt(self):
        self.assertEqual(self.stop()["decision"], "block")
        self.assertIsNone(self.stop())
        self.assertEqual(len(self.calls), 1)

    def test_loop_guard(self):
        self.assertIsNone(self.stop(stop_hook_active=True))
        self.assertEqual(self.calls, [])

    def test_failure_allows_and_is_not_cached(self):
        self.answers = [None, "different"]
        self.assertIsNone(self.stop())
        self.assertEqual(self.stop()["decision"], "block")

    def test_match_is_cached(self):
        self.answers = ["same"]
        self.assertIsNone(self.stop())
        self.assertIsNone(self.stop())
        self.assertEqual(len(self.calls), 1)

    def test_loopback_only(self):
        self.assertTrue(gate._loopback("http://127.0.0.1:11434"))
        self.assertTrue(gate._loopback("http://localhost:1"))
        self.assertFalse(gate._loopback("http://203.0.113.9:11434"))
        self.assertFalse(gate._loopback("http://127.0.0.1.evil.example:1"))


if __name__ == "__main__":
    unittest.main()
