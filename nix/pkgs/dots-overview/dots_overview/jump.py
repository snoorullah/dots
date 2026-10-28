"""dots-jump: go to the thing. Everything here is local.

Resolves <ref | agent name | task id | task uuid> through Taskwarrior (the session UDAs the
ingest cycle stamped on the task) and mirror.json (url), then either

    focus   herdr workspace focus <ws> && herdr tab focus <tab>      (default when a pane is known)
    open    xdg-open <url>                                           (default otherwise)
    resume  prints `claude --resume <sess>`                          (run it in the pane's cwd)

Nothing is written anywhere; `--dry-run` prints the argv instead of running it.
"""
import re
import subprocess

from . import atomic, config, herdr, tw

URL = re.compile(r"^https?://[^\s'\"<>]{1,400}$")


def resolve(target, tasks):
    """The one task `target` names, or None. Ambiguity resolves to the most recently modified."""
    t = (target or "").strip()
    if not t:
        return None
    low = t.lower()
    hits = []
    for x in tasks:
        if x.get("ref") == t or str(x.get("id")) == t or (len(low) >= 8 and x.get("uuid", "").startswith(low)):
            hits.append(x)
        elif (x.get("agent") or "").lower() == low:
            hits.append(x)
    hits.sort(key=lambda x: x.get("modified") or "")
    return hits[-1] if hits else None


def last_session(tasks):
    """The most recently touched task that has a pane: `dots-jump --last`."""
    cand = [x for x in tasks if x.get("pane")]
    cand.sort(key=lambda x: x.get("modified") or "")
    return cand[-1] if cand else None


def tab_for(task):
    """The tab of the task's pane: live herdr first, then what the hook recorded."""
    for a in herdr.snapshot() or []:
        if a.get("pane") == task.get("pane") or (task.get("sess") and a.get("sess") == task.get("sess")):
            return a.get("workspace"), a.get("tab"), a.get("pane")
    rec = atomic.read_json(config.STATE_DIR / "sessions" / f"{task.get('sess')}.json", {}) or {}
    return task.get("wspace") or rec.get("workspace"), rec.get("tab"), task.get("pane")


def url_for(task):
    if task.get("url"):
        return task["url"]
    m = atomic.read_json(config.STATE_DIR / "mirror.json", {}) or {}
    for r in m.get("refs", []):
        if r.get("ref") == task.get("ref") and r.get("url"):
            return r["url"]
    return None


def go(task, mode=None, dry=False, runner=subprocess.run):
    """Perform the jump. Returns the text printed for --dry-run / --resume, or '' after acting."""
    mode = mode or ("focus" if task.get("pane") else "open")
    if mode == "resume":
        if not task.get("sess"):
            raise SystemExit("dots-jump: that task has no Claude session")
        return f"claude --resume {task['sess']}"
    if mode == "open":
        url = url_for(task)
        if not url or not URL.match(url):
            raise SystemExit("dots-jump: no url to open")
        argv = ["xdg-open", url]
        if dry:
            return " ".join(argv)
        runner(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        return ""
    ws, tab, pane = tab_for(task)
    if not ws:
        raise SystemExit("dots-jump: pane is gone; try --resume or --open")
    plan = [["herdr", "workspace", "focus", ws]] + ([["herdr", "tab", "focus", tab]] if tab else [])
    if dry:
        return "\n".join(" ".join(a) for a in plan)
    if not herdr.focus(ws, tab):
        raise SystemExit("dots-jump: herdr refused to focus; the pane may have closed")
    return ""


def load_tasks():
    return tw.export("status:pending") + tw.export("status:completed", "limit:200")
