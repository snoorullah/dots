# SPDX-License-Identifier: MIT
"""Tests for py/wp.py. Fake swww, dots-theme and matugen on PATH stand in for the real ones,
HOME and XDG_STATE_HOME are temp dirs, so nothing real is set, themed or read."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(os.path.dirname(HERE), "py", "wp.py")
sys.path.insert(0, os.path.dirname(PY))
import wp  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32
JPG = b"\xff\xd8\xff\xe0" + b"\0" * 32
WEBP = b"RIFF\0\0\0\0WEBPVP8 " + b"\0" * 16

MATUGEN = """{"colors": {"dark": {"surface": "#0f1a1f", "on_surface": "%s", "primary": "#8ccff1"}}}"""


def fake(d, name, body):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)


class Env:
    def __init__(self, text="#e7edf0", swww_img="exit 0", query="exit 0"):
        self.d = tempfile.mkdtemp()
        self.home = os.path.join(self.d, "home")
        self.state = os.path.join(self.d, "state")
        self.walls = os.path.join(self.home, "walls")
        os.makedirs(self.walls)
        self.log = os.path.join(self.d, "log")
        bin_ = os.path.join(self.d, "bin")
        os.makedirs(bin_)
        fake(bin_, "swww", 'echo "swww $*" >> "%s"\ncase "$1" in query) %s;; img) %s;; esac' % (self.log, query, swww_img))
        fake(bin_, "swww-daemon", 'echo "swww-daemon" >> "%s"' % self.log)
        fake(bin_, "dots-theme", 'echo "dots-theme $*" >> "%s"' % self.log)
        fake(bin_, "matugen", "cat <<'EOF'\n" + (MATUGEN % text) + "\nEOF")
        self.env = dict(os.environ, HOME=self.home, XDG_STATE_HOME=self.state,
                        PATH=bin_ + ":/usr/bin:/bin", DOTS_WP_WAIT="0")
        self.env.pop("WALLPAPER_DIR", None)

    def put(self, rel, data=PNG):
        p = os.path.join(self.walls, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)
        return p

    def run(self, *args):
        r = subprocess.run([sys.executable, "-I", PY, *args], env=self.env, capture_output=True, text=True)
        out = json.loads(r.stdout) if r.stdout.strip() else None
        return r, out

    def calls(self):
        time.sleep(0.2)          # dots-theme is detached; give it a moment to log
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except OSError:
            return []


class Scan(unittest.TestCase):
    def test_lists_images_recursively_sorted_and_counts(self):
        e = Env()
        e.put("b.png"); e.put("sub/a.jpg", JPG); e.put("c.webp", WEBP); e.put("notes.txt", b"hi")
        r, o = e.run("scan")
        self.assertEqual(r.returncode, 0)
        self.assertEqual([i["rel"] for i in o["items"]], ["b.png", "c.webp", "sub/a.jpg"])
        self.assertEqual(o["count"], 3)
        self.assertEqual(o["skipped"], 0)
        self.assertEqual(o["name"], "walls")
        self.assertTrue(all(i["ok"] for i in o["items"]))

    def test_scan_reports_the_current_wallpaper(self):
        e = Env()
        p = e.put("a.png")
        self.assertEqual(e.run("scan")[1]["cur"], "")
        e.run("apply", p)
        self.assertEqual(e.run("scan")[1]["cur"], p)

    def test_unreadable_file_is_skipped_but_listed_not_ok(self):
        e = Env()
        e.put("good.png"); e.put("bad.png", b"not an image at all")
        r, o = e.run("scan")
        self.assertEqual(o["count"], 2)
        self.assertEqual(o["skipped"], 1)
        bad = [i for i in o["items"] if i["rel"] == "bad.png"][0]
        self.assertFalse(bad["ok"])

    def test_missing_folder_is_empty_not_an_error(self):
        e = Env()
        r, o = e.run("scan", os.path.join(e.d, "nowhere"))
        self.assertEqual(r.returncode, 0)
        self.assertEqual(o["count"], 0)
        self.assertEqual(o["items"], [])
        self.assertFalse(o["exists"])

    def test_env_folder_and_saved_folder_order(self):
        e = Env()
        other = os.path.join(e.d, "other"); os.makedirs(other)
        open(os.path.join(other, "x.png"), "wb").write(PNG)
        r, o = e.run("folder", other)
        self.assertTrue(o["ok"])
        r, o = e.run("scan")
        self.assertEqual(o["count"], 1)
        e.env["WALLPAPER_DIR"] = e.walls
        r, o = e.run("scan")
        self.assertEqual(o["count"], 0)

    def test_folder_rejects_a_file_and_a_missing_path(self):
        e = Env()
        p = e.put("a.png")
        self.assertFalse(e.run("folder", p)[1]["ok"])
        self.assertFalse(e.run("folder", os.path.join(e.d, "no"))[1]["ok"])

    def test_favourites_are_marked_and_toggle(self):
        e = Env()
        p = e.put("a.png"); e.put("b.png")
        self.assertEqual(e.run("fav", p)[1]["fav"], True)
        r, o = e.run("scan")
        self.assertEqual([i["fav"] for i in o["items"]], [True, False])
        self.assertEqual(e.run("fav", p)[1]["fav"], False)


class Palette(unittest.TestCase):
    def test_dark_text_passes_and_is_not_tuned(self):
        e = Env(text="#e7edf0")
        p = e.put("a.png")
        r, o = e.run("palette", p)
        self.assertEqual(o["surface"], "#0f1a1f")
        self.assertGreaterEqual(o["ratio"], 4.5)
        self.assertFalse(o["tuned"])
        self.assertIn("dark", o["tags"])

    def test_low_contrast_text_is_tuned_up_to_aa(self):
        e = Env(text="#3a4a52")
        p = e.put("a.png")
        r, o = e.run("palette", p)
        self.assertLess(o["ratio"], 4.5)
        self.assertTrue(o["tuned"])
        self.assertGreaterEqual(wp.ratio(o["surface"], o["tunedText"]), 4.5)

    def test_ratio_of_black_on_white(self):
        self.assertAlmostEqual(wp.ratio("#000000", "#ffffff"), 21.0, places=1)

    def test_no_matugen_is_an_error_object_not_a_crash(self):
        e = Env()
        os.remove(os.path.join(e.d, "bin", "matugen"))
        r, o = e.run("palette", e.put("a.png"))
        self.assertEqual(r.returncode, 0)
        self.assertIn("error", o)

    def test_a_missing_file_is_an_error_object(self):
        e = Env()
        r, o = e.run("palette", os.path.join(e.walls, "gone.png"))
        self.assertIn("error", o)

    def test_second_call_is_served_from_the_cache(self):
        e = Env()
        p = e.put("a.png")
        e.run("palette", p)
        os.remove(os.path.join(e.d, "bin", "matugen"))
        r, o = e.run("palette", p)
        self.assertNotIn("error", o)


class Apply(unittest.TestCase):
    def test_apply_runs_swww_cache_and_theme_in_that_order(self):
        e = Env()
        p = e.put("a.png")
        r, o = e.run("apply", p)
        self.assertTrue(o["ok"], o)
        calls = e.calls()
        self.assertTrue(calls[0].startswith("swww query"))
        img = [c for c in calls if c.startswith("swww img")][0]
        self.assertIn(p, img)
        self.assertIn("--transition-type fade", img)
        self.assertEqual(open(os.path.join(e.home, ".cache", "current-wallpaper")).read(), p)
        self.assertIn("dots-theme wallpaper " + p, calls)

    def test_apply_for_one_output_does_not_touch_cache_or_theme(self):
        e = Env()
        p = e.put("a.png")
        r, o = e.run("apply", p, "--output", "DP-1")
        self.assertTrue(o["ok"])
        self.assertTrue(any("-o DP-1" in c for c in e.calls() if c.startswith("swww img")))
        self.assertFalse(os.path.exists(os.path.join(e.home, ".cache", "current-wallpaper")))
        self.assertFalse(any(c.startswith("dots-theme") for c in e.calls()))

    def test_palette_current_and_mode_skip_dots_theme(self):
        for mode in ("current", "mode"):
            e = Env()
            r, o = e.run("apply", e.put("a.png"), "--palette", mode)
            self.assertTrue(o["ok"])
            self.assertFalse(any(c.startswith("dots-theme") for c in e.calls()), mode)

    def test_daemon_is_started_when_query_fails(self):
        e = Env(query="exit 1")
        e.run("apply", e.put("a.png"))
        self.assertIn("swww-daemon", e.calls())

    def test_a_failing_swww_reports_not_ok_and_keeps_the_cache(self):
        e = Env(swww_img="exit 1")
        p = e.put("a.png")
        r, o = e.run("apply", p)
        self.assertFalse(o["ok"])
        self.assertFalse(os.path.exists(os.path.join(e.home, ".cache", "current-wallpaper")))
        self.assertFalse(any(c.startswith("dots-theme") for c in e.calls()))

    def test_refuses_a_path_that_is_not_a_file_or_not_an_image(self):
        e = Env()
        self.assertFalse(e.run("apply", os.path.join(e.walls, "gone.png"))[1]["ok"])
        self.assertFalse(e.run("apply", e.put("x.png", b"junk"))[1]["ok"])
        self.assertFalse(any(c.startswith("swww img") for c in e.calls()))

    def test_remembers_the_previous_wallpaper_and_revert_goes_back(self):
        e = Env()
        a, b = e.put("a.png"), e.put("b.png")
        e.run("apply", a)
        e.run("apply", b)
        r, o = e.run("revert")
        self.assertTrue(o["ok"])
        self.assertEqual(open(os.path.join(e.home, ".cache", "current-wallpaper")).read(), a)

    def test_lock_toggle_links_the_wallpaper_for_hyprlock(self):
        e = Env()
        p = e.put("a.png")
        e.run("state", "lock", "on")
        e.run("apply", p)
        link = os.path.join(e.home, ".cache", "dots-lock-wallpaper")
        self.assertEqual(os.path.realpath(link), os.path.realpath(p))
        e.run("state", "lock", "off")
        e.run("apply", p)
        self.assertFalse(os.path.lexists(link))

    def test_preview_changes_the_desktop_only(self):
        e = Env()
        p = e.put("a.png")
        r, o = e.run("preview", p)
        self.assertTrue(o["ok"])
        self.assertFalse(os.path.exists(os.path.join(e.home, ".cache", "current-wallpaper")))
        self.assertFalse(any(c.startswith("dots-theme") for c in e.calls()))

    def test_restore_reapplies_the_cached_wallpaper_without_theme(self):
        e = Env()
        p = e.put("a.png")
        e.run("apply", p)
        open(e.log, "w").close()
        r, o = e.run("restore")
        self.assertTrue(o["ok"])
        self.assertTrue(any(c.startswith("swww img") and p in c for c in e.calls()))
        self.assertFalse(any(c.startswith("dots-theme") for c in e.calls()))


class Shuffle(unittest.TestCase):
    def test_off_by_default(self):
        e = Env()
        e.put("a.png")
        self.assertEqual(e.run("shuffle-tick")[1]["action"], "off")

    def test_on_applies_a_different_wallpaper(self):
        e = Env()
        a, b = e.put("a.png"), e.put("b.png")
        e.run("apply", a)
        e.run("state", "shuffle", "on")
        r, o = e.run("shuffle-tick")
        self.assertEqual(o["action"], "applied")
        self.assertEqual(o["path"], b)

    def test_next_steps_on_demand_even_with_shuffle_off(self):
        e = Env()
        a, b = e.put("a.png"), e.put("b.png")
        e.run("apply", a)
        r, o = e.run("next")
        self.assertEqual(o["action"], "applied")
        self.assertEqual(o["path"], b)

    def test_held_by_salah_or_focus_changes_nothing(self):
        e = Env()
        e.put("a.png"); e.put("b.png")
        e.run("state", "shuffle", "on")
        for why in ("salah", "focus"):
            r, o = e.run("shuffle-tick", "--hold", why)
            self.assertEqual(o["action"], "held")
            self.assertEqual(o["why"], why)
        self.assertFalse(any(c.startswith("swww img") for c in e.calls()))

    def test_prefers_favourites_when_there_are_any(self):
        e = Env()
        a, b, c = e.put("a.png"), e.put("b.png"), e.put("c.png")
        e.run("apply", a)
        e.run("fav", c)
        e.run("state", "shuffle", "on")
        for _ in range(4):
            self.assertEqual(e.run("shuffle-tick")[1]["path"], c)


class State(unittest.TestCase):
    def test_state_roundtrip_and_unknown_key_refused(self):
        e = Env()
        self.assertEqual(e.run("state", "shuffle", "on")[1]["ok"], True)
        self.assertEqual(e.run("state")[1]["shuffle"], True)
        self.assertFalse(e.run("state", "nonsense", "x")[1]["ok"])

    def test_no_shell_and_no_network_in_the_source(self):
        src = open(PY).read()
        for bad in ("shell=True", "os.system", "urllib", "socket", "http://", "https://"):
            self.assertNotIn(bad, src)


if __name__ == "__main__":
    unittest.main()
