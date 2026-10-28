"""now.json: what I am doing this minute.

The focus timer lives here and nowhere else: T3 asks `dots-overview focus start|stop|break`
to persist a change and reads `now.json.focus` back, so the QML never owns a clock. No
timer writes to work.db; the only state is the small focus.json beside the outputs.
"""
import time

from . import atomic, config, names

FOCUS = "focus.json"
DEFAULT_MIN = 25
BREAK_MIN = 5


def _focus_path():
    return config.STATE_DIR / FOCUS


def focus_cmd(action, minutes=None, zone=None, now=None):
    """start / stop / break. Returns the persisted state."""
    now = int(now or time.time())
    if action == "start":
        st = {"state": "running", "zone": zone, "startedAt": now, "targetSec": int(minutes or DEFAULT_MIN) * 60}
    elif action == "break":
        st = {"state": "break", "zone": zone, "startedAt": now, "targetSec": int(minutes or BREAK_MIN) * 60}
    elif action == "stop":
        st = {"state": "idle", "zone": None, "startedAt": None, "targetSec": 0}
    else:
        raise ValueError(f"unknown focus action {action!r}")
    atomic.write_json(_focus_path(), st)
    return st


def focus_block(zone=None, now=None):
    """The `focus` block. A finished running block rolls into a break, a finished break into idle."""
    now = int(now or time.time())
    st = atomic.read_json(_focus_path(), None) or {"state": "idle", "targetSec": 0}
    state = st.get("state") if st.get("state") in ("running", "break") and st.get("startedAt") else "idle"
    if state == "running" and now - st["startedAt"] >= int(st["targetSec"]):
        st = focus_cmd("break", zone=st.get("zone"), now=st["startedAt"] + int(st["targetSec"]))
        state = "break"
    if state == "break" and now - st["startedAt"] >= int(st["targetSec"]):
        st = focus_cmd("stop")
        state = "idle"
    if state == "idle":
        return {"state": "idle", "zone": None, "startedAt": None, "endsAt": None, "elapsedSec": 0, "targetSec": 0}
    started = int(st["startedAt"])
    target = int(st["targetSec"])
    return {"state": state, "zone": st.get("zone") or zone, "startedAt": started, "endsAt": started + target,
            "elapsedSec": max(0, now - started), "targetSec": target}


def build(tasks, live, clock, now=None):
    """Assemble now.json from pending tasks, the herdr snapshot and the clock block."""
    now = int(now or time.time())
    started = [t for t in tasks if t.get("start_ts")]
    started.sort(key=lambda t: t["start_ts"])
    t = started[-1] if started else None
    live = live or []
    ag = None
    if t and t.get("sess"):
        ag = next((a for a in live if a.get("sess") == t["sess"]), None)
    if ag is None:
        ag = next((a for a in live if a.get("focused")), None)
    task = None
    if t:
        task = {"uuid": t["uuid"], "id": t.get("id"), "desc": t.get("desc", ""), "ref": t.get("ref"),
                "src": t.get("src"), "project": t.get("project"), "tags": t.get("tags") or [],
                "startedAt": t.get("start_ts"), "agent": t.get("agent"), "pane": t.get("pane"),
                "workspace": t.get("wspace"), "sess": t.get("sess")}
    agent = None
    if ag:
        agent = {"name": names.for_session(ag.get("sess")), "pane": ag["pane"], "tab": ag.get("tab"),
                 "workspace": ag.get("workspace"), "sess": ag.get("sess"), "status": ag["status"], "cwd": ag.get("cwd")}
    return {"v": 1, "ts": now, "task": task, "agent": agent,
            "focus": focus_block(zone=(t or {}).get("project"), now=now), "clock": clock}
