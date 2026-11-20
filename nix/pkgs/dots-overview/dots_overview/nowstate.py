"""now.json: what I am doing this minute.

The focus timer lives here and nowhere else: T3 asks `dots-overview focus start|stop|break`
to persist a change and reads `now.json.focus` back, so the QML never owns a clock. No
timer writes to work.db; the only state is the small focus.json beside the outputs.
"""
import os
import re
import time
from pathlib import Path

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


HD_REF = re.compile(r"^(?:HD[ -]?#?)?(\d{3,6})$")
HD_IN_TEXT = re.compile(r"\bHD[ -]?#?(\d{3,6})\b")
TASK_ID = re.compile(r"\bTASK-\d{4}-\d+\b")
GH_REF = re.compile(r"^gh:[^/\s]+/([^#\s]+)#(\d+)$")


def _hd(n):
    return f"HD {int(n):04d}"


def ticket_map_path():
    """Where the TASK-id -> HD-number pairs live. DOTS_TICKET_MAP overrides; the default is the
    ticket-desk snapshot the desk tooling already writes. Nothing here is fetched."""
    env = os.environ.get("DOTS_TICKET_MAP")
    return Path(env) if env else Path.home() / ".claude" / "ticket-desk" / "snapshot.json"


def load_ticket_map(path=None):
    """{TASK-id: 'HD nnnn'} from a local snapshot (inProgress[].also, sections[].items[].title)."""
    try:
        doc = atomic.read_json(Path(path) if path else ticket_map_path(), None)
    except Exception:
        return {}
    if not isinstance(doc, dict):
        return {}
    out = {}
    for r in doc.get("inProgress") or []:
        if not isinstance(r, dict):
            continue
        ids = [str(r.get("id") or "")] + [str(a) for a in (r.get("also") or [])]
        task = next((i for i in ids if TASK_ID.fullmatch(i)), None)
        hd = next((m.group(1) for i in ids for m in [HD_IN_TEXT.fullmatch(i)] if m), None)
        if task and hd:
            out.setdefault(task, _hd(hd))
    for sec in doc.get("sections") or []:
        for it in (sec.get("items") or []) if isinstance(sec, dict) else []:
            if not isinstance(it, dict):
                continue
            m, k = HD_IN_TEXT.fullmatch(str(it.get("id") or "")), TASK_ID.search(str(it.get("title") or ""))
            if m and k:
                out.setdefault(k.group(0), _hd(m.group(1)))
    return out


def ticket_for(t, pairs=None):
    """The human ticket for a task: 'HD 8580' or 'repo#212'. None when none is known; never an
    internal TASK-/local: id. Order: the ref itself, an HD number the title names, the pair map."""
    if not t:
        return None
    ref, desc = str(t.get("ref") or ""), str(t.get("desc") or "")
    m = HD_REF.match(ref)
    if m:
        return _hd(m.group(1))
    m = GH_REF.match(ref)
    if m:
        return f"{m.group(1)}#{m.group(2)}"
    m = HD_IN_TEXT.search(desc)
    if m:
        return _hd(m.group(1))
    pairs = pairs or {}
    for k in [ref] + TASK_ID.findall(desc):
        if k in pairs:
            return pairs[k]
    return None


def build(tasks, live, clock, now=None, tickets=None):
    """Assemble now.json from pending tasks, the herdr snapshot and the clock block."""
    now = int(now or time.time())
    if tickets is None:
        tickets = load_ticket_map()
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
                "workspace": t.get("wspace"), "sess": t.get("sess"), "ticket": ticket_for(t, tickets)}
    agent = None
    if ag:
        agent = {"name": names.for_session(ag.get("sess")), "pane": ag["pane"], "tab": ag.get("tab"),
                 "workspace": ag.get("workspace"), "sess": ag.get("sess"), "status": ag["status"], "cwd": ag.get("cwd")}
    return {"v": 1, "ts": now, "task": task, "agent": agent,
            "focus": focus_block(zone=(t or {}).get("project"), now=now), "clock": clock}
