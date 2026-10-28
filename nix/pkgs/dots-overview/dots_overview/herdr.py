"""herdr, read through its CLI. herdr is local, so this is allowed; it only ever reads
(`api snapshot`, `pane get`) and focuses (`workspace focus`, `tab focus`).

`run` is the seam tests replace.
"""
import json
import subprocess


def run(args, timeout=5):
    try:
        p = subprocess.run(["herdr"] + list(args), capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return None
    return p.stdout if p.returncode == 0 else None


def snapshot():
    """The live agents, one dict per pane, or None when herdr is not reachable."""
    out = run(["api", "snapshot"])
    if out is None:
        return None
    try:
        snap = json.loads(out)["result"]["snapshot"]
    except (ValueError, KeyError, TypeError):
        return None
    agents = []
    for a in snap.get("agents") or []:
        sess = (a.get("agent_session") or {}).get("value")
        agents.append({
            "pane": a.get("pane_id"), "tab": a.get("tab_id"), "workspace": a.get("workspace_id"),
            "sess": sess, "status": a.get("agent_status") or "unknown", "cwd": a.get("cwd"),
            "title": a.get("terminal_title_stripped") or "", "focused": bool(a.get("focused")),
        })
    return agents


def pane(pane_id):
    """tab / workspace / session of one pane, or {} when unknown."""
    out = run(["pane", "get", pane_id])
    try:
        p = json.loads(out)["result"]["pane"]
    except (ValueError, KeyError, TypeError):
        return {}
    return {"pane": p.get("pane_id"), "tab": p.get("tab_id"), "workspace": p.get("workspace_id"),
            "sess": (p.get("agent_session") or {}).get("value"), "cwd": p.get("cwd")}


def focus(workspace, tab=None):
    """Bring a workspace (and tab) to the front. True when herdr accepted the first call."""
    ok = run(["workspace", "focus", workspace]) is not None
    if ok and tab:
        run(["tab", "focus", tab])
    return ok


def waiting(status):
    """herdr's blocked / waiting states mean an agent is stopped on me."""
    return status in ("blocked", "waiting")
