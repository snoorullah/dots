import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(HERE, "..", "js", "launcher_cmds.py")


class Env:
    def __init__(self):
        self.d = tempfile.mkdtemp()
        self.log = os.path.join(self.d, "exec.log")
        self.env = dict(os.environ, DOTS_LAUNCHER_CONFIG=os.path.join(self.d, "cfg"), DOTS_LAUNCHER_STATE=os.path.join(self.d, "st"),
                        DOTS_LAUNCHER_EXEC_LOG=self.log, EDITOR="nvim", HOME=self.d)
        self.env.pop("VISUAL", None)

    def run(self, *args):
        p = subprocess.run([sys.executable, "-I", PY, *args], capture_output=True, text=True, env=self.env)
        self.rc, self.err = p.returncode, p.stderr
        return json.loads(p.stdout)

    def argvs(self):
        return [json.loads(x) for x in open(self.log)] if os.path.exists(self.log) else []

    def seed(self, cmds):
        os.makedirs(self.env["DOTS_LAUNCHER_CONFIG"], exist_ok=True)
        with open(os.path.join(self.env["DOTS_LAUNCHER_CONFIG"], "commands.json"), "w") as f:
            json.dump(cmds, f)


CMDS = [{"id": "pods", "name": "Pods not running", "tags": ["k8s"], "cmd": "kubectl get pods -A --field-selector=status.phase!=Running"},
        {"id": "nodes", "name": "Node pressure", "tags": ["k8s"], "cmd": "kubectl describe nodes | grep -A5 Conditions"},
        {"id": "nsp", "name": "Pods in ns", "tags": ["k8s"], "cmd": "kubectl get pods -n <namespace>"},
        {"id": "df", "name": "Disk free", "tags": ["disk"], "cmd": "df -h"}]


class Query(unittest.TestCase):
    def setUp(self):
        self.e = Env()
        self.e.seed(CMDS)

    def test_filters_by_tag_and_ends_with_the_save_row(self):
        o = self.e.run("query", "k8s")
        keys = [r["key"] for r in o["rows"]]
        self.assertEqual(sorted(keys[:-1]), ["nodes", "nsp", "pods"])
        self.assertEqual(keys[-1], "__new")
        self.assertTrue(o["rows"][-1]["noAll"])

    def test_row_shape(self):
        r = self.e.run("query", "pods not")["rows"][0]
        self.assertEqual(r["title"], "Pods not running")
        self.assertEqual(r["sub"], "k8s, never used")
        self.assertEqual([a["label"] for a in r["actions"]], ["Run in pane", "Copy", "Edit"])
        self.assertTrue(r["actions"][0]["primary"])
        self.assertEqual(r["preview"]["head"], "Pods not running")
        self.assertIn("kubectl get pods", r["preview"]["body"])
        self.assertEqual(r["icon"], "terminal-window")

    def test_empty_query_lists_everything(self):
        self.assertEqual(len(self.e.run("query", "")["rows"]), len(CMDS) + 1)

    def test_no_match_still_offers_save(self):
        o = self.e.run("query", "zzzz")
        self.assertEqual([r["key"] for r in o["rows"]], ["__new"])

    def test_missing_file_is_a_hint_not_an_error(self):
        e = Env()
        o = e.run("query", "")
        self.assertNotIn("error", o)
        self.assertTrue(o["hint"])

    def test_save_row_previews_the_name_being_typed(self):
        self.assertIn("my thing", self.e.run("query", "my thing :: echo hi")["rows"][-1]["sub"])


class Run(unittest.TestCase):
    def setUp(self):
        self.e = Env()
        self.e.seed(CMDS)

    def test_runs_in_a_new_pane_via_argv_and_counts_the_use(self):
        o = self.e.run("run", "pods")
        self.assertEqual(o["toast"], "Running in a new pane")
        a = self.e.argvs()
        self.assertEqual(a[0], ["herdr", "pane", "list"])
        self.assertEqual(a[1][:3], ["herdr", "pane", "split"])
        self.assertEqual(a[2], ["herdr", "pane", "run", "test:p9", CMDS[0]["cmd"]])
        self.assertTrue(all(isinstance(x, list) and all(isinstance(y, str) for y in x) for x in a))
        self.assertIn("used 1 time", self.e.run("query", "pods not")["rows"][0]["sub"])

    def test_placeholders_are_typed_but_not_submitted(self):
        self.e.run("run", "nsp")
        self.assertEqual(self.e.argvs()[2][:3], ["herdr", "pane", "send-text"])

    def test_unknown_id_is_an_error(self):
        self.assertIn("error", self.e.run("run", "nope"))

    def test_edit_opens_the_file_in_the_editor(self):
        self.e.run("edit", "pods")
        last = self.e.argvs()[-1]
        self.assertEqual(last[:3], ["herdr", "pane", "run"])
        self.assertTrue(last[3] == "test:p9" and last[4].startswith("nvim ") and last[4].endswith("commands.json"))


class Save(unittest.TestCase):
    def setUp(self):
        self.e = Env()

    def test_save_appends_with_tags_and_a_unique_id(self):
        self.assertEqual(self.e.run("save", "Show pods :: kubectl get pods :: k8s, pods")["toast"], "Saved Show pods")
        self.e.run("save", "Show pods :: kubectl get pods -A")
        cfg = json.load(open(os.path.join(self.e.env["DOTS_LAUNCHER_CONFIG"], "commands.json")))
        self.assertEqual([c["id"] for c in cfg], ["show-pods", "show-pods-2"])
        self.assertEqual(cfg[0]["tags"], ["k8s", "pods"])
        mode = os.stat(os.path.join(self.e.env["DOTS_LAUNCHER_CONFIG"], "commands.json")).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_save_needs_name_and_command(self):
        for bad in ("only a name", " :: echo", "name :: "):
            self.assertIn("error", self.e.run("save", bad), bad)


if __name__ == "__main__":
    unittest.main()
