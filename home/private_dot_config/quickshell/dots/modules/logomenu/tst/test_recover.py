# SPDX-License-Identifier: MIT
"""Tests for py/recover.py. Fake quickshell, dots-shell, hyprctl, loginctl and ghostty on PATH
log their argv, so nothing real is restarted, locked or logged out."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(os.path.dirname(HERE), "py", "recover.py")


def fake(d, name, body):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)


class Env:
    def __init__(self, fail=()):
        self.d = tempfile.mkdtemp()
        self.log = os.path.join(self.d, "log")
        b = os.path.join(self.d, "bin")
        os.makedirs(b)
        for n in ("quickshell", "dots-shell", "hyprctl", "loginctl", "ghostty"):
            fake(b, n, 'echo "%s $*" >> "%s"\n%s' % (n, self.log, "exit 1" if n in fail else "exit 0"))
        self.env = dict(os.environ, PATH=b + ":/usr/bin:/bin", XDG_STATE_HOME=os.path.join(self.d, "state"),
                        DOTS_QS_DIR="/qs/dots", XDG_SESSION_ID="7", DOTS_RECOVER_WAIT="0")

    def run(self, *args):
        r = subprocess.run([sys.executable, "-I", PY, *args], env=self.env, capture_output=True, text=True)
        return r, (json.loads(r.stdout) if r.stdout.strip() else None)

    def calls(self):
        time.sleep(0.15)
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except OSError:
            return []


class Recover(unittest.TestCase):
    def test_reload_shell_kills_quickshell_then_starts_it_through_dots_shell(self):
        e = Env()
        r, o = e.run("reload-shell")
        self.assertTrue(o["ok"], o)
        self.assertEqual(e.calls(), ["quickshell kill -p /qs/dots", "dots-shell start"])

    def test_reload_hyprland(self):
        e = Env()
        self.assertTrue(e.run("reload-hypr")[1]["ok"])
        self.assertEqual(e.calls(), ["hyprctl reload"])

    def test_fall_back_to_waybar_and_back(self):
        e = Env()
        e.run("waybar")
        e.run("full-shell")
        self.assertEqual(e.calls(), ["dots-shell use waybar", "dots-shell use quickshell"])

    def test_lock_and_logout_use_loginctl_with_the_session_id(self):
        e = Env()
        e.run("lock")
        e.run("logout")
        self.assertEqual(e.calls(), ["loginctl lock-session", "loginctl terminate-session 7"])

    def test_logout_without_a_session_id_does_nothing(self):
        e = Env()
        del e.env["XDG_SESSION_ID"]
        r, o = e.run("logout")
        self.assertFalse(o["ok"])
        self.assertEqual(e.calls(), [])

    def test_log_opens_a_terminal_on_quickshell_log(self):
        e = Env()
        e.run("log")
        self.assertEqual(e.calls(), ["ghostty -e quickshell log -p /qs/dots"])

    def test_a_failing_step_is_reported(self):
        e = Env(fail=("hyprctl",))
        self.assertFalse(e.run("reload-hypr")[1]["ok"])

    def test_missing_binary_is_reported_not_raised(self):
        e = Env()
        os.remove(os.path.join(e.d, "bin", "hyprctl"))
        r, o = e.run("reload-hypr")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(o["ok"])

    def test_unknown_action_is_refused(self):
        e = Env()
        self.assertFalse(e.run("rm-rf")[1]["ok"])
        self.assertEqual(e.calls(), [])


class Mode(unittest.TestCase):
    def test_default_then_set_then_get(self):
        e = Env()
        self.assertEqual(e.run("mode")[1]["mode"], "Heavy work")
        self.assertTrue(e.run("mode", "set", "Focus")[1]["ok"])
        self.assertEqual(e.run("mode")[1]["mode"], "Focus")

    def test_unknown_mode_and_salah_by_hand_are_refused(self):
        e = Env()
        self.assertFalse(e.run("mode", "set", "Party")[1]["ok"])
        self.assertFalse(e.run("mode", "set", "Salah")[1]["ok"])
        self.assertEqual(e.run("mode")[1]["mode"], "Heavy work")

    def test_a_damaged_file_reads_as_the_default(self):
        e = Env()
        e.run("mode", "set", "Meeting")
        with open(os.path.join(e.d, "state", "dots-mode", "current"), "w") as f:
            f.write("garbage")
        self.assertEqual(e.run("mode")[1]["mode"], "Heavy work")


class Source(unittest.TestCase):
    def test_no_shell_no_network(self):
        with open(PY) as f:
            src = f.read()
        for bad in ("shell=True", "os.system", "urllib", "socket", "http://", "https://"):
            self.assertNotIn(bad, src)


if __name__ == "__main__":
    unittest.main()
