#!/usr/bin/env bash
# lock: tests for the hyprlock screen. hyprlock cannot render offscreen (it needs a Wayland session
# lock), so there are no PNGs. What is proven instead:
#   1  dots-lock-info unit tests (fixtures): fields, markup escaping, never fails, no task names,
#      colours from the template, baseline for "while you were away", under 100 ms per call
#   2  hyprlock.conf.tmpl renders through chezmoi, blocks balance, no unrendered template text
#   3  every cmd[] label calls a script that exists in the source (or a tool on PATH)
#   4  static rules: colours only from the palette, no Nerd Font glyphs, no Quickshell dependency,
#      no network tools, unlock hint and input field present, no task names
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
src="$root/home/private_dot_local/private_bin/executable_dots-lock-info"
tmpl="$root/home/private_dot_config/hypr/hyprlock.conf.tmpl"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
ok()  { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# ---- 1. unit tests --------------------------------------------------------------------------
if python3 -W ignore -I - "$src" "$work" <<'PY'
import json, os, shutil, stat, subprocess, sys, tempfile, time, unittest

SRC, WORK = sys.argv[1], sys.argv[2]
NOW = 1795197600  # fixed clock for every test
SECRET = "SECRETTITLE"


def make_env(root):
    st, tt, ac, ad = (os.path.join(root, d) for d in ("state", "track", "adhdconf", "adhddata"))
    for d in (st, tt, ac, ad):
        os.makedirs(d, exist_ok=True)
    bindir = os.path.join(root, "bin")
    os.makedirs(bindir, exist_ok=True)
    env = {"PATH": bindir + ":/usr/bin:/bin", "HOME": root, "TZ": "UTC", "DOTS_STATE_DIR": st,
           "DOTS_TIMETRACK_DIR": tt, "DOTS_ADHD_DIR": ac, "DOTS_ADHD_DATA": ad,
           "DOTS_LOCK_NOW": str(NOW), "XDG_RUNTIME_DIR": root}
    return env, st, tt, ac, ad, bindir


def stub(bindir, name, body):
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(p, 0o755)


def run(env, *args):
    t = time.time()
    r = subprocess.run([sys.executable, "-I", SRC, *args], env=env, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr, time.time() - t


def jw(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f)


def fixtures(st, tt, ac, ad):
    jw(os.path.join(st, "activity.json"), {"ts": NOW - 60, "buckets": {
        "today": {"workedSec": 18720, "tasksDone": 5, "byRef": [{"ref": "x", "title": SECRET}]},
        "month": {"workedSec": 30 * 14400, "tasksDone": 30 * 2}}})
    jw(os.path.join(st, "now.json"), {"task": {"desc": SECRET}, "clock": {"state": "in"}})
    jw(os.path.join(st, "attention.json"), {"items": (
        [{"kind": "erp", "title": SECRET}] + [{"kind": "mail", "title": SECRET}] * 3
        + [{"kind": "review", "title": SECRET}] * 2 + [{"kind": "blocker", "title": SECRET}]
        + [{"kind": "alert", "title": SECRET}] * 4 + [{"kind": "dm", "title": SECRET}])})
    with open(os.path.join(ac, "prayer-times.conf"), "w") as f:
        f.write("# auto\nFajr 05:38    # adhan\nDhuhr 13:30\nAsr 17:15\nMaghrib 17:45\nIsha 19:10\n")
    d = time.strftime("%Y-%m-%d", time.gmtime(NOW))
    with open(os.path.join(ad, "salah.log"), "w") as f:
        f.write(f"{d}\tFajr\tjamaah\tx\n{d}\tDhuhr\tmissed\tx\n{d}\tAsr\tjamaah\tx\n")


class T(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(dir=WORK)
        self.env, self.st, self.tt, self.ac, self.ad, self.bin = make_env(self.root)
        for n in ("wpctl", "hyprctl", "playerctl"):
            stub(self.bin, n, "exit 1")

    def out(self, *a):
        rc, o, e, _ = run(self.env, *a)
        self.assertEqual(rc, 0, e)
        return o

    def test_empty_data_prints_nothing_and_exits_zero(self):
        for f in ("away", "stat1", "stat2", "stat3", "day", "prayer", "music", "away-counts"):
            self.assertEqual(self.out(f), "", f)
        self.assertEqual(self.out("bogus"), "")
        self.assertEqual(self.out(), "")

    def test_corrupt_data_never_fails(self):
        for n in ("activity.json", "now.json", "attention.json"):
            with open(os.path.join(self.st, n), "w") as f:
                f.write("{not json")
        with open(os.path.join(self.tt, "away-intent.json"), "w") as f:
            f.write("\x00\x01")
        with open(os.path.join(self.ac, "prayer-times.conf"), "w") as f:
            f.write("Fajr 99:99\nIsha x:y\n")
        with open(os.path.join(self.ad, "salah.log"), "w") as f:
            f.write("garbage\n\t\t\nnot-a-date\tFajr\tmissed\n")
        for f in ("date", "away", "status", "stat1", "stat2", "stat3", "day", "prayer", "music", "away-counts", "all"):
            self.out(f)
        self.assertEqual(self.out("prayer"), "")

    def test_hijri_and_gregorian(self):
        # 1 Ramadan 1446 began on 2025-03-01 in the civil tabular calendar
        self.env["DOTS_LOCK_NOW"] = str(time.mktime((2025, 3, 1, 12, 0, 0, 0, 0, 0)) - time.timezone)
        self.assertEqual(self.out("date").strip(), "1 Ramadan 1446")

    def test_stats_against_average(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        s1 = self.out("stat1", "--up", "8ccff1", "--down", "f2b04d", "--dim", "a7b4bb")
        self.assertIn("5:12", s1)           # 18720 s
        self.assertIn("worked", s1)
        self.assertIn("▲ 1:12", s1)    # 5:12 vs 4:00 average
        self.assertIn('foreground="#8ccff1"', s1)
        s2 = self.out("stat2", "--up", "8ccff1", "--down", "f2b04d")
        self.assertIn("▲ 3", s2)       # 5 vs 2 a day
        s3 = self.out("stat3", "--up", "8ccff1", "--down", "f2b04d")
        self.assertIn("2/3", s3)
        self.assertIn("salah on time", s3)

    def test_stat_below_average_uses_down_colour(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        a = json.load(open(os.path.join(self.st, "activity.json")))
        a["buckets"]["today"]["workedSec"] = 3600
        jw(os.path.join(self.st, "activity.json"), a)
        s = self.out("stat1", "--up", "8ccff1", "--down", "f2b04d")
        self.assertIn("▼ 3:00", s)
        self.assertIn('foreground="#f2b04d"', s)

    def test_stale_activity_from_another_day_is_omitted(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        a = json.load(open(os.path.join(self.st, "activity.json")))
        a["ts"] = NOW - 3 * 86400
        jw(os.path.join(self.st, "activity.json"), a)
        for f in ("stat1", "stat2", "day"):
            self.assertEqual(self.out(f), "", f)

    def test_day_line(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        d = self.out("day")
        self.assertIn("5:12", d)
        self.assertIn("worked of 8:00", d)
        self.assertIn("logout 20:48", d)    # fixed clock is 18:00 UTC; 2:48 of work left
        self.assertIn("in 2:48", d)

    def test_next_prayer_wraps_to_fajr(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        p = self.out("prayer")              # fixed clock is 18:00 UTC
        self.assertIn("Isha 19:10", p)
        self.assertIn("in 1:10", p)
        self.env["DOTS_LOCK_NOW"] = str(NOW + 2 * 3600)    # 20:00, after Isha
        p = self.out("prayer")
        self.assertIn("Fajr 05:38", p)
        self.assertIn("in 9:38", p)

    def test_away_chip_from_intent_and_now_json(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        self.assertEqual(self.out("away"), "")
        jw(os.path.join(self.tt, "away-intent.json"), {"label": "Isha", "since": NOW - 374})
        a = self.out("away")
        self.assertIn("Out for Isha", a)
        self.assertIn("06:14", a)
        jw(os.path.join(self.tt, "away-intent.json"), {"label": "Done", "key": "logout", "since": NOW - 60})
        self.assertIn("Logged out for today", self.out("away"))
        os.remove(os.path.join(self.tt, "away-intent.json"))
        jw(os.path.join(self.st, "now.json"), {"clock": {"state": "away", "awayReason": "Walk", "sinceTs": NOW - 65}})
        self.assertIn("Out for Walk", self.out("away"))
        self.assertIn("01:05", self.out("away"))

    def test_away_counts_are_counts_only(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        o = self.out("away-counts")
        for n, label in ((1, "assigned"), (3, "new mail"), (2, "reviews asked"), (1, "agents need you"), (4, "alerts")):
            self.assertRegex(o, rf">{n}</span>\s+{label}")
        self.assertNotIn(SECRET, o)

    def test_away_counts_baseline_under_hyprlock(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        fake = os.path.join(self.root, "hyprlock")
        os.symlink(shutil.which("sh"), fake)
        att = os.path.join(self.st, "attention.json")
        items = json.load(open(att))["items"]
        more = os.path.join(self.root, "more.json")
        jw(more, {"items": items + [{"kind": "mail", "title": SECRET}] * 2})
        cmd = f'{sys.executable} -I {SRC} away-counts; echo ---; cp {more} {att}; {sys.executable} -I {SRC} away-counts; true'
        r = subprocess.run([fake, "-c", cmd], env=self.env, capture_output=True, text=True)
        first, second = r.stdout.split("---")
        self.assertEqual(first.strip(), "", first)             # lock just started: nothing is new
        self.assertRegex(second, r">2</span>\s+new mail")
        self.assertNotIn("alerts", second)

    def test_no_task_names_anywhere(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        stub(self.bin, "playerctl", 'case "$1" in status) echo Playing;; *) printf "Song\\tBand";; esac')
        o = self.out("all")
        self.assertNotIn(SECRET, o)
        self.assertNotIn("TASK-", o)

    def test_music_escaped_and_only_while_playing(self):
        stub(self.bin, "playerctl", 'case "$1" in status) echo Paused;; *) printf "A <b> & C\\tBand";; esac')
        self.assertEqual(self.out("music"), "")
        stub(self.bin, "playerctl", 'case "$1" in status) echo Playing;; *) printf "A <b> & C\\tBand";; esac')
        m = self.out("music")
        self.assertIn("A &lt;b&gt; &amp; C", m)
        self.assertIn("Band", m)

    def test_status_line(self):
        stub(self.bin, "wpctl", 'echo "Volume: 0.64"')
        stub(self.bin, "hyprctl", 'echo \'{"keyboards":[{"main":true,"active_keymap":"English (US)"}]}\'')
        s = self.out("status")
        self.assertIn("64%", s)
        self.assertIn("EN", s)
        stub(self.bin, "wpctl", 'echo "Volume: 0.40 [MUTED]"')
        self.assertIn("muted", self.out("status"))

    def test_bad_colour_is_ignored(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        s = self.out("stat1", "--up", '8ccff1"><x', "--dim", "zzzzzz")
        self.assertNotIn("<x", s)
        self.assertNotIn("zzzzzz", s)

    def test_each_field_under_100ms(self):
        fixtures(self.st, self.tt, self.ac, self.ad)
        stub(self.bin, "wpctl", 'echo "Volume: 0.64"')
        stub(self.bin, "hyprctl", 'echo \'{"keyboards":[{"main":true,"active_keymap":"English (US)"}]}\'')
        stub(self.bin, "playerctl", 'case "$1" in status) echo Playing;; *) printf "Song\\tBand";; esac')
        for f in ("date", "away", "status", "stat1", "stat2", "stat3", "day", "prayer", "music", "away-counts"):
            best = min(run(self.env, f)[3] for _ in range(3))
            self.assertLess(best, 0.1, f"{f} took {best * 1000:.0f} ms")


if __name__ == "__main__":
    unittest.main(argv=["lock"], verbosity=1)
PY
then ok "dots-lock-info unit tests"; else bad "dots-lock-info unit tests"; fi

# ---- 2. template renders --------------------------------------------------------------------
conf="$work/hyprlock.conf"
if chezmoi execute-template --source "$root/home" <"$tmpl" >"$conf" 2>"$work/err" && [ -s "$conf" ]; then
  ok "hyprlock.conf.tmpl renders"
else
  bad "hyprlock.conf.tmpl does not render: $(head -3 "$work/err")"
fi
if grep -q '{{\|}}' "$conf"; then bad "rendered config still has template text"; else ok "no unrendered template text"; fi
python3 -I - "$conf" <<'PY' && ok "blocks balance, known types, one input-field" || bad "config structure"
import re, sys
t = open(sys.argv[1]).read()
depth, kinds = 0, []
for raw in t.splitlines():
    l = raw.strip()
    if not l or l.startswith("#"):
        continue
    m = re.match(r"^(\w[\w-]*)\s*\{$", l)
    if m:
        assert depth == 0, f"nested block: {l}"
        depth += 1
        kinds.append(m.group(1))
    elif l == "}":
        assert depth == 1, "stray }"
        depth -= 1
    elif depth == 0:
        assert l.startswith("source") or l.startswith("$"), f"top-level line: {l}"
    else:
        assert "=" in l, f"not key = value: {l}"
assert depth == 0, "unclosed block"
assert set(kinds) <= {"general", "background", "label", "input-field"}, set(kinds)
assert kinds.count("input-field") == 1 and kinds.count("background") == 1 and kinds.count("general") == 1
assert kinds.count("label") >= 12, kinds.count("label")
PY

# ---- 3. every cmd[] calls something that exists ---------------------------------------------
while IFS= read -r line; do
  cmdline="${line#*] }"
  first="${cmdline%% *}"
  case "$first" in
    '~/.local/bin/'*)
      name="${first#'~/.local/bin/'}"
      if [ -f "$root/home/private_dot_local/private_bin/executable_$name" ] || [ -f "$root/home/private_dot_local/private_bin/executable_$name.tmpl" ]; then
        ok "cmd[] script exists: $name"
      else bad "cmd[] calls a missing script: $name"; fi ;;
    *)
      if command -v "$first" >/dev/null 2>&1; then ok "cmd[] tool exists: $first"; else bad "cmd[] calls a missing tool: $first"; fi ;;
  esac
done < <(grep -E '^[[:space:]]*text = cmd\[' "$conf" | sed 's/^[[:space:]]*text = //' | sort -u)
# every dots-lock-info field the template asks for is one the script serves
python3 -I - "$conf" "$src" <<'PY' && ok "every dots-lock-info field in the config is served" || bad "unknown dots-lock-info field in the config"
import re, sys
conf, src = open(sys.argv[1]).read(), open(sys.argv[2]).read()
fields = set(re.findall(r"dots-lock-info (\S+)", conf))
served = set(re.findall(r'"([a-z0-9-]+)": f_', src))
assert fields and fields <= served, fields - served
PY

# ---- 4. static rules ------------------------------------------------------------------------
pal="$(grep -oE '#[0-9a-fA-F]{6}' "$root/home/.chezmoidata/palette.yaml" | tr -d '#' | tr 'A-F' 'a-f' | sort -u)"
bad_hex=0
while read -r h; do
  grep -qx "$h" <<<"$pal" || { bad "colour $h is not in the palette"; bad_hex=1; }
done < <(grep -oE '(rgb\(|foreground="##|--(up|down|dim) )[0-9a-fA-F]{6}' "$conf" | grep -oE '[0-9a-fA-F]{6}$' | tr 'A-F' 'a-f' | sort -u)
[ "$bad_hex" = 0 ] && ok "every colour comes from the palette"
if grep -v '^[[:space:]]*#' "$src" | grep -qE '#[0-9a-fA-F]{6}'; then bad "dots-lock-info hard-codes a hex colour"; else ok "dots-lock-info has no hex colours (the template passes them)"; fi
if LC_ALL=C.UTF-8 grep -qP '[\x{E000}-\x{E0AF}\x{E0D5}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$conf" "$src"; then bad "Nerd Font glyph present"; else ok "no Nerd Font glyphs"; fi
if grep -v '^[[:space:]]*#' "$conf" | grep -iqE 'quickshell|qs ipc|\bqs\b|dots-shell'; then bad "lock config depends on Quickshell"; else ok "unlock does not depend on Quickshell"; fi
if grep -vE '^[[:space:]]*#' "$src" | grep -qE '\b(curl|wget|requests|urllib|http\.client|socket\.(create_connection|connect)|shell=True|os\.system)\b'; then
  bad "dots-lock-info uses the network or a shell string"; else ok "dots-lock-info: no network, argv-only exec"; fi
grep -q 'Enter to unlock · your timer keeps running' "$conf" && ok "unlock hint present" || bad "unlock hint missing"
grep -q 'WHILE YOU WERE AWAY' "$conf" && grep -q 'TODAY SO FAR' "$conf" && ok "board section headers present" || bad "board section headers missing"
if grep -iE 'task|ticket-title|subject|summary' "$conf" | grep -v '^[[:space:]]*#' | grep -q .; then bad "config mentions task names"; else ok "no task names on the lock screen"; fi
if command -v hyprlock >/dev/null; then hyprlock --help >/dev/null 2>&1 && ok "hyprlock present (--help only; it has no config check)" || echo "NOTE hyprlock --help failed"; fi

echo
[ "$fails" -eq 0 ] && echo "lock: all passed" || echo "lock: $fails FAILED"
exit $((fails > 0))
