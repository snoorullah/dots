import json
import os
import subprocess
import sys
import tempfile
import unittest

PY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "js", "launcher_recents.py")


class Recents(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.env = dict(os.environ, DOTS_LAUNCHER_STATE=self.d)

    def run_(self, *a):
        return json.loads(subprocess.run([sys.executable, "-I", PY, *a], capture_output=True, text=True, env=self.env).stdout)

    def add(self, p, key, **kw):
        return self.run_("add", json.dumps(dict(p=p, key=key, title=key, **kw)))

    def test_newest_first_and_deduped(self):
        self.add("cmd", "a"); self.add("cmd", "b"); self.add("cmd", "a")
        self.assertEqual([r["key"] for r in self.run_("load")["rows"]], ["a", "b"])

    def test_shows_eight_keeps_fifty(self):
        for i in range(60):
            self.add("p", "k%d" % i)
        self.assertEqual(len(self.run_("load")["rows"]), 8)
        self.assertEqual(len(json.load(open(os.path.join(self.d, "recents.json")))), 50)

    def test_sensitive_is_refused(self):
        self.add("clip", "secret", sensitive=True)
        self.assertEqual(self.run_("load")["rows"], [])

    def test_missing_fields_are_refused_and_bad_json_is_an_error(self):
        self.assertEqual(self.run_("add", json.dumps({"p": "x"}))["rows"], [])
        self.assertIn("error", self.run_("add", "{nope"))

    def test_file_is_private(self):
        self.add("p", "k")
        self.assertEqual(os.stat(os.path.join(self.d, "recents.json")).st_mode & 0o777, 0o600)

    def test_forget(self):
        self.add("p", "k"); self.run_("forget")
        self.assertEqual(self.run_("load")["rows"], [])


if __name__ == "__main__":
    unittest.main()
