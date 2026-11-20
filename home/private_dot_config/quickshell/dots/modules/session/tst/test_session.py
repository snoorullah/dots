# SPDX-License-Identifier: MIT
"""Tests for py/session.py. Fake binaries on PATH stand in for timetrack, loginctl,
notify-send and herdr, so nothing real is declared, locked or read."""
import ast
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(os.path.dirname(HERE), "py", "session.py")
ROOT = os.path.abspath(os.path.join(HERE, *[".."] * 7))
sys.path.insert(0, os.path.dirname(PY))
import session  # noqa: E402


def fake(dirpath, name, body):
    p = os.path.join(dirpath, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)


class Env:
    """A temp bin dir first on PATH, plus a log every fake appends its argv to."""

    def __init__(self, tt="exit 0", lc="exit 0", ns="exit 0", herdr="exit 1"):
        self.d = tempfile.mkdtemp()
        self.log = os.path.join(self.d, "log")
        for n, b in (("timetrack", tt), ("loginctl", lc), ("notify-send", ns), ("herdr", herdr)):
            fake(self.d, n, 'echo "%s $*" >> "%s"\n%s' % (n, self.log, b))
        self.env = dict(os.environ, PATH=self.d + ":/usr/bin:/bin", DOTS_SESSION_TIMETRACK=os.path.join(self.d, "timetrack"))

    def run(self, *args):
        return subprocess.run([sys.executable, "-I", PY, *args], env=self.env, capture_output=True, text=True)

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return f.read().splitlines()


class Keys(unittest.TestCase):
    def test_keys_match_timetrack_away_choices(self):
        with open(os.path.join(ROOT, "nix/pkgs/timetrack/timetrack/away.py")) as f:
            tree = ast.parse(f.read())
        node = next(n for n in tree.body if isinstance(n, ast.Assign)
                    and isinstance(n.targets[0], ast.Name) and n.targets[0].id == "CHOICES")
        want = [k.value for k in node.value.keys]
        self.assertEqual([k for k, _ in session.KEYS], want)

    def test_keys_and_labels_match_the_existing_picker(self):
        with open(os.path.join(ROOT, "home/private_dot_local/private_bin/executable_timetrack-away-pick")) as f:
            src = f.read()
        rows = re.findall(r"^(?:rest=\")?(\w+)\t([^\n\"]+)", src, re.M)
        got = {k: v for k, v in rows}
        for k, label in session.KEYS:
            if k == "salah":
                continue
            self.assertEqual(got.get(k), label, k)

    def test_choices_salah_first_only_near_a_prayer(self):
        near = session.choices("Asr")
        self.assertEqual([c["key"] for c in near][:2], ["salah", "washroom"])
        self.assertEqual(near[0]["label"], "Salah · Asr")
        self.assertTrue(near[0]["lead"])
        far = session.choices("")
        self.assertEqual([c["key"] for c in far][-1], "salah")
        self.assertEqual(far[-1]["label"], "Salah")
        self.assertTrue(far[0]["lead"])
        self.assertEqual(sum(1 for c in far if c["lead"]), 1)

    def test_choices_command_reads_prayer(self):
        e = Env(tt='[ "$1 $2" = "away --prayer" ] && echo Maghrib; exit 0')
        out = json.loads(e.run("choices").stdout)
        self.assertEqual(out[0]["label"], "Salah · Maghrib")

    def test_choices_command_survives_missing_timetrack(self):
        e = Env(tt="exit 3")
        out = json.loads(e.run("choices").stdout)
        self.assertEqual(len(out), 6)
        self.assertEqual(out[-1]["key"], "salah")


class Declare(unittest.TestCase):
    def test_declares_then_locks_exactly_as_the_old_picker(self):
        e = Env()
        r = e.run("declare", "meal")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(e.calls(), ["timetrack away --declare meal", "loginctl lock-session"])

    def test_failed_declare_still_locks_and_says_so(self):
        e = Env(tt="exit 1")
        r = e.run("declare", "walk")
        self.assertEqual(r.returncode, 0)
        c = e.calls()
        self.assertEqual(c[0], "timetrack away --declare walk")
        self.assertTrue(c[1].startswith("notify-send -a timetrack Away"))
        self.assertEqual(c[-1], "loginctl lock-session")

    def test_unknown_key_records_nothing_and_does_not_lock(self):
        e = Env()
        r = e.run("declare", "nap; rm -rf /")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(e.calls(), [])

    def test_logout_key_goes_through_the_same_path(self):
        e = Env()
        e.run("declare", "logout")
        self.assertEqual(e.calls()[0], "timetrack away --declare logout")
        self.assertEqual(e.calls()[-1], "loginctl lock-session")


class Blocker(unittest.TestCase):
    def test_classify(self):
        c = session.classify
        self.assertEqual(c(["terraform", "apply", "-auto-approve"]), "terraform apply")
        self.assertEqual(c(["/usr/bin/terraform", "-chdir=x", "apply"]), "terraform apply")
        self.assertEqual(c(["tofu", "destroy"]), "tofu destroy")
        self.assertEqual(c(["helm", "upgrade", "--install", "x"]), "helm upgrade")
        self.assertEqual(c(["kubectl", "apply", "-f", "-"]), "kubectl apply")
        self.assertEqual(c(["nixos-rebuild", "switch"]), "nixos-rebuild switch")
        self.assertEqual(c(["rsync", "-a", "a", "b"]), "rsync")
        self.assertEqual(c(["restic", "backup", "/"]), "restic backup")
        self.assertIsNone(c(["terraform", "plan"]))
        self.assertIsNone(c(["kubectl", "get", "pods"]))
        self.assertIsNone(c(["zsh"]))
        self.assertIsNone(c(["claude", "--resume", "x"]))
        self.assertIsNone(c(["vim", "terraform"]))
        self.assertIsNone(c([]))

    def panes(self, procs_by_pane):
        def lister():
            return [{"pane_id": p} for p in procs_by_pane]

        def info(pid):
            return [{"argv": a, "pid": n} for n, a in enumerate(procs_by_pane[pid], 100)]
        return lister, info

    def test_blocked_names_command_and_pane_number(self):
        lister, info = self.panes({"w1:p1": [["zsh"]], "w1:p2": [["terraform", "apply"]]})
        b = session.blocker(lister, info, age=lambda pid: 99, min_age=10)
        self.assertEqual(b, {"blocked": True, "cmd": "terraform apply", "pane": "2"})

    def test_a_young_process_does_not_block(self):
        lister, info = self.panes({"w1:p2": [["terraform", "apply"]]})
        self.assertFalse(session.blocker(lister, info, age=lambda pid: 2, min_age=10)["blocked"])

    def test_nothing_running_is_not_blocked(self):
        lister, info = self.panes({"w1:p1": [["zsh"]], "w1:p2": [["claude"]]})
        self.assertEqual(session.blocker(lister, info, age=lambda pid: 99, min_age=10), {"blocked": False})

    def test_deadline_stops_the_scan_and_says_unchecked(self):
        lister, info = self.panes({"w1:p1": [["zsh"]], "w1:p2": [["terraform", "apply"]]})
        ticks = iter([0, 0, 99, 99, 99])
        b = session.blocker(lister, info, age=lambda pid: 99, min_age=10, deadline=5, clock=lambda: next(ticks))
        self.assertEqual(b, {"blocked": False, "unchecked": True})

    def test_unreadable_pane_with_no_block_is_unchecked(self):
        def info(pid):
            raise OSError("gone")
        b = session.blocker(lambda: [{"pane_id": "w1:p1"}], info, age=lambda pid: 99)
        self.assertEqual(b, {"blocked": False, "unchecked": True})

    def test_herdr_calls_have_a_short_timeout(self):
        self.assertLessEqual(session.CALL_TIMEOUT, 2)
        self.assertLessEqual(session.DEADLINE, 5)

    def test_unreadable_pane_is_skipped_not_fatal(self):
        def lister():
            return [{"pane_id": "w1:p1"}, {"pane_id": "w1:p2"}]

        def info(pid):
            if pid == "w1:p1":
                raise OSError("gone")
            return [{"argv": ["helm", "upgrade"], "pid": 7}]
        b = session.blocker(lister, info, age=lambda pid: 99, min_age=10)
        self.assertEqual(b["pane"], "2")

    def test_command_with_no_herdr_is_not_blocked_but_unchecked(self):
        e = Env(herdr="exit 1")
        self.assertEqual(json.loads(e.run("blocker", "--min-age", "0").stdout),
                         {"blocked": False, "unchecked": True})

    def test_command_parses_herdr_json(self):
        body = (
            'case "$2" in\n'
            "list) echo '{\"result\":{\"panes\":[{\"pane_id\":\"w3:p4\"}]}}';;\n"
            "process-info) echo '{\"result\":{\"process_info\":{\"foreground_processes\":"
            "[{\"argv\":[\"terraform\",\"apply\"],\"pid\":%d}]}}}';;\n"
            "esac" % os.getpid()
        )
        e = Env(herdr=body)
        out = json.loads(e.run("blocker", "--min-age", "0").stdout)
        self.assertEqual(out, {"blocked": True, "cmd": "terraform apply", "pane": "4"})


if __name__ == "__main__":
    unittest.main()
