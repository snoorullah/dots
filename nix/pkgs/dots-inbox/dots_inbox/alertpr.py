"""Prepared alert -> [Create ticket] [Ignore]. User-initiated: a click, or nothing happens.

Create makes ONE local Taskwarrior task through `dots-overview alert-task` (no ERP, no
Linear, no GitHub issue); the overview's "Break down & start" then launches the agent that
may open a DRAFT PR (dots-overview launch.py holds the deny rules). Ignore records the
alert NAME so it is not offered again within the prep window.

Which project and checkout an alert belongs to is the user's business, in rules.toml:
  [alerts.repos."HighCPU*"]     # alert-name glob, first match wins
  project = "platform"
  repo = "~/work/some-checkout"
  test = "make test"            # optional: the one command the agent runs to check its fix
No match: the task is made in project `alerts` with no repo and nothing is prepared.
"""
import fnmatch
import os
import subprocess
import time

from . import config, db
from . import notify as _nt

run = subprocess.run              # seams for tests
ask = _nt.ask
ASK_TIMEOUT = 60
DEFAULT_PROJECT = "alerts"


def mapping(name, cfg=None):
    """(project, repo-or-None) for an alert name."""
    repos = ((cfg if cfg is not None else config.rules()).get("alerts", {}).get("repos") or {})
    if isinstance(repos, dict):
        for glob, v in repos.items():
            if isinstance(v, dict) and fnmatch.fnmatchcase(name.lower(), str(glob).lower()):
                repo = os.path.expanduser(str(v.get("repo") or "")) or None
                return str(v.get("project") or DEFAULT_PROJECT), repo
    return DEFAULT_PROJECT, None


def test_cmd(name, cfg=None):
    """The mapped test command for an alert name, or None."""
    repos = ((cfg if cfg is not None else config.rules()).get("alerts", {}).get("repos") or {})
    if isinstance(repos, dict):
        for glob, v in repos.items():
            if isinstance(v, dict) and fnmatch.fnmatchcase(name.lower(), str(glob).lower()):
                return str(v.get("test") or "").strip() or None
    return None


def _seen(conn, kind, name, window):
    return conn.execute("SELECT 1 FROM event WHERE kind=? AND ref=? AND ts_unix > ?",
                        (kind, name, int(time.time()) - window)).fetchone() is not None


def authed(conn, ref, window):
    r = conn.execute("SELECT m.authed, m.ts_unix FROM prep_msg p JOIN alert_msg m ON m.msgid=p.msgid "
                     "WHERE p.ref=?", (ref,)).fetchone()
    return bool(r and r["authed"] and r["ts_unix"] > time.time() - window)


def create(conn, name, prep_path, cfg=None):
    """Make the task. Returns its ref, or raises RuntimeError."""
    project, repo = mapping(name, cfg)
    argv = ["dots-overview", "alert-task", "--name", name, "--project", project, "--prep", str(prep_path)]
    if repo:
        argv += ["--repo", repo]
        tc = test_cmd(name, cfg)
        if tc:
            argv += ["--test", tc]
    try:
        r = run(argv, capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        raise RuntimeError(f"cannot run dots-overview: {e}")
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or f"exit {r.returncode}").strip()[:300])
    ref = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    db.log(conn, "alert_ticketed", name, ref)
    conn.commit()
    return ref


def offer(conn, row, summary, path, window, cfg=None):
    """Ask once. Returns 'create', 'ignore', 'skipped' (already answered this window) or None."""
    name = row["ref"].split("|", 1)[0]
    # only the very mail this prep was made from, and only if it passed the entry gate
    # (alerts.authenticated: our authserv-id, dmarc=pass aligned with From). Keyed by Message-ID:
    # an earlier real alert of the same name authorises nothing about a later mail.
    if not authed(conn, row["ref"], window):
        return "skipped"
    if _seen(conn, "alert_ignored", name, window) or _seen(conn, "alert_ticketed", name, window):
        return "skipped"
    key = ask("dots-inbox", f"Prepared: {row['title']}", summary,
              [("create", "Create ticket"), ("ignore", "Ignore")], ASK_TIMEOUT)
    if key == "ignore":
        db.log(conn, "alert_ignored", name, row["title"])
        conn.commit()
    elif key == "create":
        try:
            ref = create(conn, name, path, cfg)
            _nt.toast("dots-inbox", f"Ticket {ref}", f"{name}: break it down in the overview to start")
        except RuntimeError as e:
            _nt.toast("dots-inbox", f"No ticket for {name}", str(e)[:200], urgency="critical")
    return key
