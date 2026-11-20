#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Logo menu actions. Every one is a short local argv sequence; the menu runs this detached,
so a step that stops the shell (reload, waybar fallback) does not stop the steps after it.
One JSON object on stdout, exit 0 always. No shell, no network.

  recover.py reload-shell | reload-hypr | waybar | full-shell | log | lock | logout
  recover.py mode [set NAME]
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

MODES = ["Focus", "Meeting", "Salah", "Heavy work", "Winding down", "Off duty"]
DEFAULT_MODE = "Heavy work"


def qs_dir():
    return os.environ.get("DOTS_QS_DIR") or str(Path(os.environ.get("HOME", "~")).expanduser() / ".config/quickshell/dots")


def run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=30).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def steps(seq, wait=0.0):
    done = []
    for argv in seq:
        ok = run(argv)
        done.append({"argv": argv, "ok": ok})
        if not ok and argv[0] != "quickshell":    # killing a shell that is not running is fine
            return {"ok": False, "steps": done}
        time.sleep(wait)
    return {"ok": True, "steps": done}


def session_id():
    sid = os.environ.get("XDG_SESSION_ID", "")
    return sid if re.fullmatch(r"[A-Za-z0-9_-]{1,32}", sid) else ""


def act(name):
    wait = float(os.environ.get("DOTS_RECOVER_WAIT", "0.4"))
    if name == "reload-shell":
        return steps([["quickshell", "kill", "-p", qs_dir()], ["dots-shell", "start"]], wait)
    if name == "reload-hypr":
        return steps([["hyprctl", "reload"]])
    if name == "waybar":
        return steps([["dots-shell", "use", "waybar"]])
    if name == "full-shell":
        return steps([["dots-shell", "use", "quickshell"]])
    if name == "log":
        return steps([["ghostty", "-e", "quickshell", "log", "-p", qs_dir()]])
    if name == "lock":
        return steps([["loginctl", "lock-session"]])
    if name == "logout":
        sid = session_id()
        if not sid:
            return {"ok": False, "error": "no session id"}
        return steps([["loginctl", "terminate-session", sid]])
    return {"ok": False, "error": "unknown action"}


def mode_file():
    base = os.environ.get("XDG_STATE_HOME") or str(Path(os.environ.get("HOME", "~")).expanduser() / ".local/state")
    return Path(base) / "dots-mode" / "current"


def mode(args):
    f = mode_file()
    if len(args) == 2 and args[0] == "set":
        # Salah is derived from the prayer times, never chosen by hand
        if args[1] not in MODES or args[1] == "Salah":
            return {"ok": False, "error": "unknown mode"}
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp = f.with_name("current.tmp")
        tmp.write_text(args[1])
        os.replace(tmp, f)
    try:
        cur = f.read_text().strip()
    except OSError:
        cur = ""
    return {"ok": True, "mode": cur if cur in MODES and cur != "Salah" else DEFAULT_MODE, "modes": MODES}


def main(argv):
    if not argv:
        out = {"ok": False, "error": "usage"}
    elif argv[0] == "mode":
        out = mode(argv[1:])
    else:
        if argv[0] in ("reload-shell", "waybar", "full-shell"):
            try:
                os.setsid()
            except OSError:
                pass
        out = act(argv[0])
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
