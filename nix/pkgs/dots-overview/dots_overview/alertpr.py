"""Alert -> local ticket. User-initiated only: dots-inbox calls `dots-overview alert-task`
after a click on "Create ticket"; nothing here runs on its own.

The ticket is a LOCAL Taskwarrior task (src=claude, ref local:<hex>), tagged `alert` and
`attn` so it shows in the attention list as kind 'alert'. Two annotations carry what the
launcher needs: `prep: <markdown>` (the read-only analysis) and, when the alert maps to a
checkout, `repo: <dir>`. No ERP, no Linear, no GitHub issue.
"""
import fcntl
import os
import re
from pathlib import Path

from . import config, task, tw

TITLE_MAX = 120
BAD_NAME = re.compile(r"[^A-Za-z0-9_.-]")      # the name is a stranger's mail subject


def _path(p, what, must_dir):
    p = Path(os.path.expanduser(p or ""))
    if not p.is_absolute() or any(c in str(p) for c in "\n\r\0"):
        raise task.TaskError(f"{what} must be an absolute path")
    if must_dir and not p.is_dir():
        raise task.TaskError(f"{what} is not a directory: {p}")
    if not must_dir and not p.is_file():
        raise task.TaskError(f"{what} is not a file: {p}")
    return str(p)


def create(name, project, prep, repo=None, test=None):
    """One task for the alert; returns the task dict. A repeat for the same prep file
    returns the existing task instead of making a second one."""
    prep = _path(prep, "prep", False)
    config.STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(config.STATE_DIR / "alert-task.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)         # check-then-add must not interleave
        return _create(name, project, prep, repo, test)


def _create(name, project, prep, repo, test=None):
    for t in tw.pending():
        if "alert" in (t.get("tags") or []) and any(
                (a.get("description") or "") == f"prep: {prep}" for a in t.get("annotations") or []):
            return t
    title = "Alert: " + (BAD_NAME.sub("", name or "").strip()[:TITLE_MAX] or "unnamed")
    t = task.new_task(title, project, tags=("alert", "attn"))
    tw.annotate(t["uuid"], f"prep: {prep}")
    if repo:
        tw.annotate(t["uuid"], f"repo: {_path(repo, 'repo', True)}")
        if test and "\n" not in test and "\r" not in test and "\0" not in test and len(test) <= 200:
            tw.annotate(t["uuid"], f"test: {test.strip()}")      # from the owner's rules.toml
    return tw.export(t["uuid"])[0]


def annotation(t, key):
    """Value of a `key: value` annotation on task t, or None."""
    for a in t.get("annotations") or []:
        d = a.get("description") or ""
        if d.startswith(key + ": "):
            return d[len(key) + 2:].strip()
    return None
