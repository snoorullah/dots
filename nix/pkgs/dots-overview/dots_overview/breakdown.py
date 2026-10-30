"""Break a ticket into 2-5 steps with the LOCAL model, then start the first one.

The model is a drafting aid, not an authority. Its output is untrusted text:

  1. it must parse as a JSON array, else the fallback runs;
  2. every step is stripped to [A-Za-z0-9 ,.:/_#()-] BEFORE any length check, so a shell
     metacharacter, a newline or a tag like "+evil" cannot survive;
  3. 2-5 steps of 8-80 characters, else the fallback runs;
  4. steps reach `task` only as argv elements after `--` (see tw.add), never a shell string.

The fallback is one subtask named after the parent, so the feature always produces
something usable even when the model is down, slow or hostile.
"""
import fcntl
import json
import os
import re
import subprocess

from . import config
from . import tw

ALLOWED = re.compile(r"[^A-Za-z0-9 ,.:/_#()-]")
PROJECT = re.compile(r"^[A-Za-z0-9._-]{1,40}$")
URL = re.compile(r"^https?://[^\s'\"<>]{1,400}$")
ALERT_STEPS = ("Fix the alert in a sandbox copy", "Review the patch, then push as a draft PR")
MIN_STEPS, MAX_STEPS, MIN_LEN, MAX_LEN = 2, 5, 8, 80


def clean(step):
    return " ".join(ALLOWED.sub("", str(step)).split())


def validate(raw):
    """Model text -> list of clean steps, or None when it is not acceptable."""
    try:
        data = json.loads(raw[raw.index("["):raw.rindex("]") + 1])
    except ValueError:
        return None
    if not isinstance(data, list) or not MIN_STEPS <= len(data) <= MAX_STEPS:
        return None
    steps = [clean(x) for x in data if isinstance(x, str)]
    if len(steps) != len(data) or not all(MIN_LEN <= len(s) <= MAX_LEN for s in steps):
        return None
    return steps


def fallback(title, ref):
    t = clean(title)[:MAX_LEN].strip()
    return [t if len(t) >= MIN_LEN else clean(f"Work on {ref}")[:MAX_LEN]]


def ask_model(title, runner=subprocess.run):
    prompt = ("Break this ticket into 2 to 5 short concrete steps. Reply with ONLY a JSON array of "
              "strings, each 8 to 80 characters, plain words, no markdown.\nTicket: " + clean(title)[:200])
    llm = os.environ.get("DOTS_LLM") or "llm"
    try:
        p = runner([llm, prompt], capture_output=True, text=True, timeout=90, stdin=subprocess.DEVNULL)
        return p.stdout if p.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def notify(summary, body=""):
    """A desktop notification; the button runs for ~20 s of model time and must say so."""
    try:
        subprocess.Popen(["notify-send", "-a", "Overview", "-i", "view-list-tree", summary, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def existing(ref):
    """Pending subtasks already made for this ref, oldest first."""
    subs = [t for t in tw.pending() if t.get("parentref") == ref and "sub" in (t.get("tags") or [])]
    return sorted(subs, key=lambda t: t.get("entry_ts") or 0)


def run(ref, start=False, model=ask_model, opener=subprocess.Popen, say=notify, dispatch=None):
    """Create the subtasks, or reuse the ones a previous click made.

    Returns {'steps': [...], 'fallback': bool, 'started': uuid|None, 'reused': bool}.
    One run per ref at a time (a second click while the model thinks waits, then reuses)."""
    lock_path = config.STATE_DIR / f"breakdown-{re.sub(r'[^A-Za-z0-9_-]', '_', ref)[:80]}.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with open(lock_path, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _run(ref, start, model, opener, say, dispatch)


def _dispatch(parent, steps, current, step_uuid):
    from . import launch
    t = next((x for x in tw.pending() if x["uuid"] == step_uuid), {"uuid": step_uuid})
    return launch.launch(parent, steps, current, t)


def _run(ref, start, model, opener, say, dispatch):
    parent = tw.by_ref(ref)
    if parent is None:
        say(f"Break down {ref}: not found", "No task carries that ref.")
        raise tw.TwError(f"no task carries ref {ref}")
    have = existing(ref)
    reused = bool(have)
    used_fallback = False
    if reused:
        steps, uuids = [t.get("desc", "") for t in have], [t["uuid"] for t in have]
    else:
        from . import launch
        if launch.is_alert(parent):         # the title came from a stranger's mail: no model sees it
            steps = list(ALERT_STEPS)
        else:
            say(f"Breaking down {ref}", "Asking the local model for steps...")
            steps = validate(model(parent.get("desc", "")))
            used_fallback = steps is None
            if used_fallback:
                steps = fallback(parent.get("desc", ""), ref)
        attrs = {"parentref": ref}
        if PROJECT.match(parent.get("project") or ""):
            attrs["project"] = parent["project"]
        uuids = [tw.add(s, tags=("sub", "mirror"), **attrs) for s in steps]
    started = None
    if start and uuids:
        if not any(t.get("start_ts") for t in have):
            tw.start(uuids[0])
        started = uuids[0]
        url = parent.get("url")
        if url and URL.match(url):
            opener(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                   start_new_session=True)
    agent = None
    if started:
        try:
            agent = (dispatch or _dispatch)(parent, steps, steps[0], started)
        except Exception as e:          # the steps exist and are started; the agent is a bonus
            agent = {"error": str(e)[:200]}
    head = f"{ref}: {len(steps)} step(s)" + (" (already broken down)" if reused else "") + \
        (" (model unavailable: one step)" if used_fallback else "")
    lines = [f"{'▶' if i == 0 and started else '•'} {s}" for i, s in enumerate(steps)]
    if agent and agent.get("error"):
        lines.append(f"Agent not launched: {agent['error']}")
    elif agent:
        lines.append(("Agent already on it in " if agent.get("reused") else "Agent briefing you in the Hangar, ")
                     + str(agent.get("pane")))
    say(head, "\n".join(lines))
    return {"steps": steps, "fallback": used_fallback, "started": started, "reused": reused, "agent": agent}
