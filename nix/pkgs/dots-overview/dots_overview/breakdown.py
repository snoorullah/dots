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
import json
import os
import re
import subprocess

from . import tw

ALLOWED = re.compile(r"[^A-Za-z0-9 ,.:/_#()-]")
PROJECT = re.compile(r"^[A-Za-z0-9._-]{1,40}$")
URL = re.compile(r"^https?://[^\s'\"<>]{1,400}$")
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


def run(ref, start=False, model=ask_model, opener=subprocess.Popen):
    """Create the subtasks. Returns {'steps': [...], 'fallback': bool, 'started': uuid|None}."""
    parent = tw.by_ref(ref)
    if parent is None:
        raise tw.TwError(f"no task carries ref {ref}")
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
        tw.start(uuids[0])
        started = uuids[0]
        url = parent.get("url")
        if url and URL.match(url):
            opener(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                   start_new_session=True)
    return {"steps": steps, "fallback": used_fallback, "started": started}
