import base64
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest

CLIP = os.environ.get("DOTS_CLIP") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "..", "private_dot_local", "private_bin", "executable_dots-clip")


def png(w, h):
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", w, h) + b"x" * 20


class Clip(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.state = os.path.join(self.d, "state")
        self.rt = os.path.join(self.d, "rt")
        os.makedirs(self.rt, mode=0o700)
        self.log = os.path.join(self.d, "exec.log")
        self.env = dict(os.environ, DOTS_CLIP_STATE=self.state, XDG_RUNTIME_DIR=self.rt, DOTS_CLIP_EXEC_LOG=self.log, HOME=self.d)
        self.env.pop("DOTS_CLIP_TYPES", None)

    def run_(self, *a, stdin=None, types=None):
        env = dict(self.env)
        if types is not None:
            env["DOTS_CLIP_TYPES"] = types
        else:
            env["DOTS_CLIP_TYPES"] = "text/plain"
        p = subprocess.run([sys.executable, "-I", CLIP, *a], input=stdin, capture_output=True, env=env)
        self.rc, self.err = p.returncode, p.stderr.decode()
        out = p.stdout.decode()
        return json.loads(out) if out.strip() else None

    def store(self, text, types=None):
        return self.run_("store", stdin=text.encode(), types=types)

    def rows(self, q=""):
        return self.run_("list", q)["rows"]

    def titles(self, q=""):
        return [r["title"] for r in self.rows(q) if r["key"] != "__info"]

    def logged(self):
        return [json.loads(x) for x in open(self.log)] if os.path.exists(self.log) else []

    # ---- at rest -----------------------------------------------------------------
    def test_plaintext_never_touches_disk_and_files_are_private(self):
        self.store("kubectl get nodes -o wide")
        blob = b"".join(open(os.path.join(self.state, f), "rb").read() for f in os.listdir(self.state))
        self.assertNotIn(b"kubectl", blob)
        for f in ("key", "history.enc"):
            self.assertEqual(os.stat(os.path.join(self.state, f)).st_mode & 0o777, 0o600, f)
        self.assertEqual(os.stat(self.state).st_mode & 0o777, 0o700)

    def test_image_bytes_are_encrypted_too(self):
        self.run_("store", "--image", stdin=png(64, 48))
        self.assertNotIn(b"IHDR", open(os.path.join(self.state, "history.enc"), "rb").read())

    def test_a_lost_key_starts_clean_not_crashed(self):
        self.store("one")
        os.remove(os.path.join(self.state, "key"))
        self.assertEqual(self.titles(), [])

    # ---- what is never stored ----------------------------------------------------
    def test_password_manager_hint_is_skipped(self):
        self.store("hunter-two", types="text/plain\nx-kde-passwordManagerHint")
        self.assertEqual(self.titles(), [])

    def test_other_sensitive_hints_are_skipped(self):
        for t in ("text/plain\norg.nspasteboard.ConcealedType", "text/plain\ntext/x-sensitive", "text/plain\napplication/x-keepassxc-thing"):
            self.store("abc-%s" % t[-6:], types=t)
        self.assertEqual(self.titles(), [])

    def test_secret_patterns_are_skipped_and_announced(self):
        for s in ("-----BEGIN OPENSSH PRIVATE KEY-----\nabc", "ghp_" + "a" * 36, "password = correct-horse-battery", "AKIA" + "A" * 16):
            self.store(s)
        self.assertEqual(self.titles(), [])
        self.assertTrue(any(a[0] == "notify-send" for a in self.logged()))

    def test_empty_and_whitespace_are_skipped(self):
        self.store(""); self.store("   \n")
        self.assertEqual(self.titles(), [])

    def test_plain_text_is_stored(self):
        self.store("hello there")
        self.assertEqual(self.titles(), ["hello there"])

    def test_huge_text_is_skipped(self):
        self.store("x" * ((1 << 20) + 5))
        self.assertEqual(self.titles(), [])

    # ---- list --------------------------------------------------------------------
    def test_row_shape_matches_the_board(self):
        self.store("kubectl get nodes -o wide")
        self.store("https://example.com/pull/2291")
        self.run_("store", "--image", stdin=png(640, 380))
        r = {x["title"]: x for x in self.rows()}
        self.assertEqual(r["kubectl get nodes -o wide"]["icon"], "terminal-window")
        self.assertEqual(r["https://example.com/pull/2291"]["icon"], "globe")
        self.assertEqual(r["https://example.com/pull/2291"]["preview"]["head"], "Link")
        img = r["Screenshot, 640 × 380"]
        self.assertEqual(img["icon"], "image")
        self.assertTrue(os.path.isfile(img["preview"]["image"]))
        self.assertEqual(os.stat(img["preview"]["image"]).st_mode & 0o777, 0o600)
        self.assertEqual([a["label"] for a in r["kubectl get nodes -o wide"]["actions"]], ["Paste", "Pin", "Delete"])
        self.assertTrue(r["kubectl get nodes -o wide"]["actions"][0]["primary"])

    def test_info_row_is_last_and_has_no_actions(self):
        self.store("a")
        last = self.rows()[-1]
        self.assertEqual((last["key"], last["actions"]), ("__info", []))
        self.assertEqual(last["preview"]["head"], "Not stored")
        self.assertNotIn("__info", [r["key"] for r in self.rows("a")])

    def test_newest_first_and_filter(self):
        self.store("alpha one"); self.store("beta two"); self.store("alpha three")
        self.assertEqual(self.titles(), ["alpha three", "beta two", "alpha one"])
        self.assertEqual(self.titles("ALPHA"), ["alpha three", "alpha one"])

    def test_empty_history_has_a_hint(self):
        self.assertTrue(self.run_("list", "")["hint"])

    def test_duplicates_collapse_to_the_top(self):
        self.store("same"); self.store("other"); self.store("same")
        self.assertEqual(self.titles(), ["same", "other"])

    # ---- actions -----------------------------------------------------------------
    def test_pin_survives_clear_and_sorts_first(self):
        self.store("keep me"); self.store("drop me"); self.store("newest")
        keep = next(r for r in self.rows() if r["title"] == "keep me")
        self.assertIn("toast", self.run_("pin", keep["key"]))
        self.assertEqual(self.titles()[0], "keep me")
        self.assertEqual([a["label"] for a in self.rows()[0]["actions"]], ["Paste", "Unpin", "Delete"])
        self.run_("clear")
        self.assertEqual(self.titles(), ["keep me"])
        self.run_("unpin", keep["key"]); self.run_("clear")
        self.assertEqual(self.titles(), [])

    def test_pinned_flag_survives_a_recopy(self):
        self.store("sticky")
        self.run_("pin", self.rows()[0]["key"])
        self.store("sticky")
        self.run_("clear")
        self.assertEqual(self.titles(), ["sticky"])

    def test_delete(self):
        self.store("one"); self.store("two")
        self.run_("delete", next(r for r in self.rows() if r["title"] == "one")["key"])
        self.assertEqual(self.titles(), ["two"])
        self.assertIn("error", self.run_("delete", "nope"))

    def test_clear_purges_decrypted_previews(self):
        self.run_("store", "--image", stdin=png(10, 10))
        p = self.rows()[0]["preview"]["image"]
        self.assertTrue(os.path.exists(p))
        self.run_("clear")
        self.assertFalse(os.path.exists(p))

    def test_purge_previews_keeps_history(self):
        self.run_("store", "--image", stdin=png(10, 10))
        p = self.rows()[0]["preview"]["image"]
        self.run_("purge-previews")
        self.assertFalse(os.path.exists(p))
        self.assertEqual(len(self.titles()), 1)

    def test_paste_text_and_image_use_wl_copy(self):
        self.store("paste me")
        self.assertIn("toast", self.run_("paste", self.rows()[0]["key"]))
        self.assertEqual(self.logged()[-1], ["wl-copy", "--type", "text/plain"])
        self.run_("store", "--image", stdin=png(8, 8))
        self.run_("paste", self.rows()[0]["key"])
        self.assertEqual(self.logged()[-1], ["wl-copy", "--type", "image/png"])
        self.assertIn("error", self.run_("paste", "nope"))

    def test_history_is_capped_but_pins_are_not_dropped(self):
        self.store("pinned one")
        self.run_("pin", self.rows()[0]["key"])
        for i in range(105):
            self.store("item %d" % i)
        self.assertLessEqual(len([r for r in self.rows() if r["key"] != "__info"]), 60)    # list shows at most 60
        self.assertEqual(self.titles()[0], "pinned one")


if __name__ == "__main__":
    unittest.main()
