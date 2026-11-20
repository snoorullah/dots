# SPDX-License-Identifier: MIT
"""Tests for py/pins.py and py/rank.py. A fake `llm` on PATH stands in for the local model."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PINS = os.path.join(os.path.dirname(HERE), "py", "pins.py")
RANK = os.path.join(os.path.dirname(HERE), "py", "rank.py")

WINS = [
    {"id": "w1", "title": "switcher.qml - dots", "app": "Editor", "ticket": "TICKET-9"},
    {"id": "w2", "title": "zsh git status", "app": "Terminal", "ticket": ""},
    {"id": "w6", "title": "Switcher spec review notes", "app": "Notes", "ticket": "TICKET-9"},
    {"id": "w9", "title": "Downloads", "app": "Files", "ticket": ""},
]


def fake(d, name, body):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)


class Env:
    def __init__(self, llm=None):
        self.d = tempfile.mkdtemp()
        b = os.path.join(self.d, "bin")
        os.makedirs(b)
        self.seen = os.path.join(self.d, "seen")
        if llm is not None:
            fake(b, "llm", 'echo "$*" > "%s"\n%s' % (self.seen, llm))
        self.env = dict(os.environ, PATH=b + ":/usr/bin:/bin", XDG_STATE_HOME=os.path.join(self.d, "state"),
                        DOTS_RANK_TIMEOUT="0.6")

    def pins(self, *args):
        r = subprocess.run([sys.executable, "-I", PINS, *args], env=self.env, capture_output=True, text=True)
        return json.loads(r.stdout)

    def rank(self, q, wins=WINS):
        r = subprocess.run([sys.executable, "-I", RANK, q], input=json.dumps(wins), env=self.env,
                           capture_output=True, text=True)
        self.last = r
        return json.loads(r.stdout)

    def prompt(self):
        with open(self.seen) as f:
            return f.read()


class Pins(unittest.TestCase):
    def test_set_list_unset(self):
        e = Env()
        self.assertEqual(e.pins("list")["pins"], {})
        self.assertTrue(e.pins("set", "0xd2", "TICKET-123")["ok"])
        self.assertEqual(e.pins("list")["pins"], {"0xd2": "TICKET-123"})
        self.assertTrue(e.pins("unset", "0xd2")["ok"])
        self.assertEqual(e.pins("list")["pins"], {})

    def test_bad_address_or_ticket_is_refused(self):
        e = Env()
        self.assertFalse(e.pins("set", "d2; rm", "TICKET-1")["ok"])
        self.assertFalse(e.pins("set", "0xd2", "x" * 80)["ok"])
        self.assertFalse(e.pins("set", "0xd2", "")["ok"])
        self.assertEqual(e.pins("list")["pins"], {})

    def test_prune_drops_windows_that_no_longer_exist(self):
        e = Env()
        e.pins("set", "0xa1", "T-1")
        e.pins("set", "0xb2", "T-2")
        e.pins("prune", "0xb2", "0xc3")
        self.assertEqual(e.pins("list")["pins"], {"0xb2": "T-2"})

    def test_current_ticket_roundtrip(self):
        e = Env()
        self.assertEqual(e.pins("current")["ticket"], "")
        self.assertTrue(e.pins("ticket", "TICKET-123")["ok"])
        self.assertEqual(e.pins("current")["ticket"], "TICKET-123")

    def test_a_damaged_store_reads_as_empty(self):
        e = Env()
        e.pins("set", "0xa1", "T-1")
        with open(os.path.join(e.d, "state", "dots-winswitch", "pins.json"), "w") as f:
            f.write("{nope")
        self.assertEqual(e.pins("list")["pins"], {})


class Rank(unittest.TestCase):
    def test_model_answer_is_used_and_validated(self):
        e = Env(llm="echo 'w6, w1, nonsense, w3'")
        o = e.rank("which window was I using for the spec review?")
        self.assertEqual(o["via"], "model")
        self.assertEqual(o["ids"], ["w6", "w1"])

    def test_prompt_has_titles_and_ids_only(self):
        e = Env(llm="echo w6")
        e.rank("spec review")
        p = e.prompt()
        self.assertIn("Switcher spec review notes", p)
        self.assertIn("w6", p)
        self.assertNotIn("TICKET-9", p)

    def test_the_list_can_come_as_an_argument(self):
        e = Env(llm="echo w9")
        r = subprocess.run([sys.executable, "-I", RANK, "downloads", json.dumps(WINS)], env=e.env,
                           capture_output=True, text=True)
        self.assertEqual(json.loads(r.stdout)["ids"], ["w9"])

    def test_slow_model_falls_back_to_fuzzy(self):
        e = Env(llm="sleep 5; echo w9")
        o = e.rank("spec review notes")
        self.assertEqual(o["via"], "fuzzy")
        self.assertEqual(o["ids"][0], "w6")

    def test_no_llm_binary_falls_back_to_fuzzy(self):
        e = Env()
        o = e.rank("downloads")
        self.assertEqual(o["via"], "fuzzy")
        self.assertEqual(o["ids"], ["w9"])

    def test_model_failure_or_empty_answer_falls_back(self):
        for body in ("exit 1", "echo ''", "echo 'sorry, I cannot'"):
            e = Env(llm=body)
            self.assertEqual(e.rank("spec")["via"], "fuzzy", body)

    def test_nothing_matches_gives_an_empty_list(self):
        e = Env()
        self.assertEqual(e.rank("zzzzqq")["ids"], [])


class Source(unittest.TestCase):
    def test_no_shell_no_network(self):
        for p in (PINS, RANK):
            with open(p) as f:
                src = f.read()
            for bad in ("shell=True", "os.system", "urllib", "socket", "http://", "https://"):
                self.assertNotIn(bad, src, p)


if __name__ == "__main__":
    unittest.main()
