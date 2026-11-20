# SPDX-License-Identifier: MIT
"""Session helpers for the shell: the away picker's choices, the declare-then-lock
step, and the "blocked while a long command runs" guard.

  session.py choices                 JSON list of picker rows, salah first near an iqamah
  session.py declare KEY             timetrack away --declare KEY, then loginctl lock-session
  session.py blocker [--min-age S]   JSON {"blocked": false} or {"blocked": true, cmd, pane}

argv only, no shell. It adds no data path: declare is the same two commands the old
fzf picker ran (executable_timetrack-away-pick), and the lock is never skipped.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

# Same keys, order and picker labels as executable_timetrack-away-pick; the keys are the
# CHOICES of timetrack/away.py (tests/test_session.py fails if either drifts).
KEYS = [
    ("salah", "Salah"),
    ("washroom", "Washroom / pantry"),
    ("walk", "Walk / short break"),
    ("meal", "Lunch / long break"),
    ("meeting", "Meeting"),
    ("logout", "Log out for today"),
]

# command -> (subcommands that make it long, show the subcommand). None = any use is long.
WATCH = {
    "terraform": ({"apply", "destroy", "import"}, True),
    "tofu": ({"apply", "destroy", "import"}, True),
    "terragrunt": ({"apply", "destroy"}, True),
    "kubectl": ({"apply", "rollout", "drain", "delete"}, True),
    "helm": ({"upgrade", "install", "uninstall"}, True),
    "nixos-rebuild": ({"switch", "boot", "test", "build"}, True),
    "home-manager": ({"switch"}, True),
    "restic": ({"backup", "restore", "prune", "check"}, True),
    "ansible-playbook": (None, False),
    "rsync": (None, False),
    "pg_dump": (None, False),
    "pg_restore": (None, False),
    "dd": (None, False),
}
MIN_AGE = 10  # seconds a command must have run to count as long
CALL_TIMEOUT = 2  # seconds for one herdr call
DEADLINE = 5  # seconds for the whole check


def timetrack_bin():
    return (os.environ.get("DOTS_SESSION_TIMETRACK") or shutil.which("timetrack")
            or os.path.expanduser("~/.nix-profile/bin/timetrack"))


def _run(argv, timeout=8):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def prayer_now():
    try:
        r = _run([timetrack_bin(), "away", "--prayer"])
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def choices(prayer):
    rows = []
    for key, label in KEYS:
        if key == "salah" and prayer:
            label = "Salah · " + prayer
        rows.append({"key": key, "label": label, "lead": False})
    salah = rows[0]
    rest = rows[1:]
    ordered = [salah] + rest if prayer else rest + [salah]
    ordered[0]["lead"] = True
    return ordered


def declare(key):
    if key not in dict(KEYS):
        print("session: unknown away reason %r" % key, file=sys.stderr)
        return 2
    # Super+Esc is the lock key first: a broken or absent timetrack must never stop the lock.
    ok = False
    try:
        ok = _run([timetrack_bin(), "away", "--declare", key]).returncode == 0
    except (OSError, subprocess.SubprocessError):
        pass
    if not ok:
        try:
            _run(["notify-send", "-a", "timetrack", "Away", "reason not recorded; locking anyway"])
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        return _run(["loginctl", "lock-session"]).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def classify(argv):
    """The label for a watched long command, or None."""
    if not argv:
        return None
    name = os.path.basename(argv[0])
    if name not in WATCH:
        return None
    subs, show = WATCH[name]
    if subs is None:
        return name
    for tok in argv[1:]:
        if tok in subs:
            return name + " " + tok if show else name
    return None


def _herdr_json(*args):
    r = _run(["herdr", *args], timeout=CALL_TIMEOUT)
    if r.returncode != 0:
        raise OSError("herdr " + " ".join(args))
    return json.loads(r.stdout)["result"]


def herdr_panes():
    return _herdr_json("pane", "list")["panes"]


def herdr_procs(pane_id):
    return _herdr_json("pane", "process-info", "--pane", pane_id)["process_info"]["foreground_processes"]


def proc_age(pid):
    """Seconds since the process started, from /proc; a huge number when unreadable."""
    try:
        with open("/proc/%d/stat" % pid) as f:
            start = int(f.read().rsplit(")", 1)[1].split()[19])
        with open("/proc/uptime") as f:
            up = float(f.read().split()[0])
        return up - start / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, IndexError):
        return 1e9


def blocker(list_panes=herdr_panes, procs=herdr_procs, age=proc_age, min_age=MIN_AGE,
            deadline=DEADLINE, clock=time.monotonic):
    """{"blocked": true, cmd, pane} or {"blocked": false}. When herdr could not be read in
    full (error, timeout, deadline) and nothing blocks: {"blocked": false, "unchecked": true}."""
    t0 = clock()
    unchecked = {"blocked": False, "unchecked": True}
    try:
        panes = list_panes()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return unchecked
    partial = False
    for p in panes:
        if clock() - t0 > deadline:
            partial = True
            break
        pid = p.get("pane_id", "")
        try:
            plist = procs(pid)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            partial = True
            continue
        for pr in plist:
            cmd = classify(pr.get("argv") or [])
            if cmd and age(int(pr.get("pid") or 0)) >= min_age:
                m = re.search(r":p(\d+)$", pid)
                return {"blocked": True, "cmd": cmd, "pane": m.group(1) if m else pid}
    return unchecked if partial else {"blocked": False}


def main(argv):
    if len(argv) >= 2 and argv[1] == "choices":
        print(json.dumps(choices(prayer_now())))
        return 0
    if len(argv) == 3 and argv[1] == "declare":
        return declare(argv[2])
    if len(argv) >= 2 and argv[1] == "blocker":
        mins = float(argv[argv.index("--min-age") + 1]) if "--min-age" in argv else MIN_AGE
        print(json.dumps(blocker(min_age=mins)))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
