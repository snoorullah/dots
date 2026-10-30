"""The task gate: Claude Code hooks that make "no agent works without a declared task" real.

One entry point, `dots-overview task-hook <event>`, wrapped by the `dots-task-hook` script:

    session   SessionStart      inject the current task (or the instruction to declare one)
    prompt    UserPromptSubmit  same, and remember this turn's prompt for the Stop check
    pretool   PreToolUse        DENY Edit/Write/MultiEdit/NotebookEdit/Bash with no declared task
    stop      Stop              steering: ask the local model whether the turn matches the task

Availability beats enforcement everywhere EXCEPT the one deliberate hard edge, the PreToolUse
deny. Every other failure (bad JSON, missing state, a hung model, an exception) prints nothing
and exits 0, which Claude Code reads as "no opinion". Even the deny fails open if the hook
dies: the gate is a policy, not a security boundary.

Reads only local state files; the Stop check talks to Ollama on loopback and nothing else.
"""
import hashlib
import json
import os
import re
import shlex
import sys
import time
import urllib.parse
import urllib.request

from . import atomic, config, task

GATED_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit", "Bash")
BUDGET = 4.0                    # the installer gives each hook 5 s (stop: 6 s)
OLLAMA = "http://127.0.0.1:11434"
MODEL = "qwen3-coder:30b"
LLM_TIMEOUT = 3.0
TURN, VERDICTS = "turn", "verdicts"
TRIVIAL_PROMPT = 18             # "continue", "yes do it": nothing to classify
# Turns the harness starts, not the user: a subagent's report, a background-task notice,
# a hook's feedback. Their text is boilerplate, so the model read them as "different work"
# and the Stop check blocked turns that were plainly the declared task.
HARNESS_PROMPT = ("Another Claude session sent a message", "<task-notification", "[SYSTEM NOTIFICATION",
                  "Stop hook feedback", "<system-reminder>", "<agent-message", "<bash-input>",
                  "<bash-stdout>", "<local-command")
OFF_WORDS = ("off", "0", "false", "no")

NO_TASK = ("Before editing or running commands, declare the task: `dots-task list`, then `dots-task declare <ref>` "
           "or `dots-task new \"<title>\" --project <p>`. If the user's request is different work from the current "
           "task, switch or create a new task, or ask the user whether to log it.")


# ---- switches -------------------------------------------------------------------------

def kill_switch(env):
    if (env.get("DOTS_TASK_GATE") or "").lower() in OFF_WORDS:
        return True
    return (config.CONF.parent / "task-gate-off").exists()


def headless(env):
    """`claude -p` and SDK runs: nobody is there to declare a task.

    Verified 2026-10-28: a `claude -p` run's hooks see CLAUDE_CODE_ENTRYPOINT=sdk-cli (an
    interactive session sees "cli"), and they also inherit HERDR_PANE_ID from the pane that
    launched them, so the pane says nothing about who is at the keyboard. Jobs that spawn
    `claude -p` may also set DOTS_TASK_GATE=off explicitly.
    """
    return (env.get("CLAUDE_CODE_ENTRYPOINT") or "").startswith("sdk")


# ---- the Bash allowlist ---------------------------------------------------------------

def _plain(cmd):
    """True when the shell would run `cmd` as ONE simple command with no expansion.

    Outside quotes: no ; & | < > ( ) { } $ ` backslash or newline. Inside single quotes anything
    goes (the shell does not look). Inside double quotes only $ ` and backslash matter.
    """
    quote = None
    for c in cmd:
        if quote == "'":
            quote = None if c == "'" else quote
        elif quote == '"':
            if c in "$`\\":
                return False
            quote = None if c == '"' else quote
        elif c in "'\"":
            quote = c
        elif c in ";&|<>(){}$`\\\n\r":
            return False
    return quote is None


TASK_READ = {"list", "export", "info", "ls", "next", "all", "count", "projects", "tags", "summary"}
TASK_WRITE = {"add", "modify", "done", "delete", "start", "stop", "edit", "annotate", "denotate", "append",
              "prepend", "duplicate", "undo", "sync", "purge", "import", "config", "log", "context"}
GIT_READ = {"status", "log", "diff"}
DOTS_TASK = ("dots-task", "~/.local/bin/dots-task", os.path.expanduser("~/.local/bin/dots-task"))


def allowlisted(cmd):
    """Commands that stay open before a task is declared: the way OUT of the gate, and reads."""
    if not _plain(cmd or ""):
        return False
    try:
        argv = shlex.split(cmd)
    except ValueError:
        return False
    if not argv:
        return False
    exe, args = argv[0], argv[1:]
    if exe in DOTS_TASK:
        return True
    if exe in ("ls", "cat", "grep", "pwd"):
        return True
    if exe == "rg":
        return not any(a.startswith(("--pre", "--hostname-bin")) for a in args)
    if exe == "git":
        return (bool(args) and args[0] in GIT_READ
                and not any(a.startswith(("--output", "-o", "--ext-diff")) for a in args))
    if exe == "task":
        return (any(a in TASK_READ for a in args) and not any(a in TASK_WRITE for a in args)
                and not any(a.startswith("rc") for a in args))
    return False


# ---- PreToolUse -----------------------------------------------------------------------

def deny_text(tool):
    return (f"No task declared for this session, so {tool} is refused (reading and searching are still open). "
            + NO_TASK + " For genuinely trivial non-work: `dots-task none \"<reason>\"`. "
            "If it is unclear which task this is, ask the user.")


def pretool(hook, env):
    """The deny reason, or None to allow."""
    tool = hook.get("tool_name")
    if tool not in GATED_TOOLS or kill_switch(env) or headless(env):
        return None
    sess = str(hook.get("session_id") or "")
    if not task.SESS_RE.match(sess):
        return None
    # a subagent's hook carries its parent's session_id (verified 2026-10-28), so the
    # parent's declaration covers it with no further lookup
    d = task.read_decl(sess)
    if task.declared_ok(d):
        return None
    if tool == "Bash" and allowlisted(str((hook.get("tool_input") or {}).get("command") or "")):
        return None
    return deny_text(tool)


# ---- context --------------------------------------------------------------------------

def context_text(sess):
    d = task.read_decl(sess)
    if not task.declared_ok(d):
        return NO_TASK
    if d.get("exempt"):
        return f"This session is declared untracked ({d.get('reason')}). If real work starts, declare a task."
    proj = f", project {d['project']}" if d.get("project") else ""
    return (f"Task for this session: {d.get('ref') or d.get('uuid', '')[:8]} \"{d.get('title')}\"{proj}. "
            "If the user's request is different work, `dots-task switch <ref>` or "
            "`dots-task new \"<title>\" --project <p>`, or ask the user whether to log it.")


def token_value(sess):
    d = task.read_decl(sess)
    if not task.declared_ok(d):
        return "no-task"
    return "untracked" if d.get("exempt") else (d.get("ref") or d.get("uuid", "")[:8])


def on_context(event, hook, env):
    sess = str(hook.get("session_id") or "")
    if not task.SESS_RE.match(sess) or hook.get("agent_id"):
        return None
    # a `claude -p` run inherits the launching pane: recording it, or refreshing that pane's
    # ticket token from it, would overwrite the interactive agent that owns the pane
    if headless(env):
        return None
    pane = env.get("HERDR_PANE_ID") or None
    task.touch_live(sess, hook.get("cwd"), pane if pane and task.PANE_RE.match(pane) else None)
    # an agent dispatched by Break down & start (launch.py) arrives with its step named
    if event == "SessionStart" and not task.declared_ok(task.read_decl(sess)):
        want = (env.get("DOTS_TASK_DECLARE") or "").strip()
        if re.fullmatch(r"[0-9a-f-]{36}", want):
            try:
                t = task.find(want)
                if t:
                    task.declare(sess, t, env=env)
            except Exception:
                pass
    if event == "UserPromptSubmit":
        p = str(hook.get("prompt") or "")
        auto = p.lstrip().startswith(HARNESS_PROMPT)
        at = task.read_decl(sess) if task.SESS_RE.match(sess) else None
        atomic.write_json(task._p(TURN, sess), {"v": 1, "ts": int(time.time()), "prompt": p[:600], "auto": auto,
                                                "decl": (at or {}).get("uuid"),
                                                "hash": hashlib.sha256(p.encode("utf-8", "replace")).hexdigest()[:16]})
    task.refresh_token(pane, token_value(sess), timeout=1.0)
    if kill_switch(env):
        return None
    return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": context_text(sess)}}


# ---- Stop: is this turn the declared task? --------------------------------------------

def _loopback(url):
    host = urllib.parse.urlparse(url).hostname or ""
    return host in ("127.0.0.1", "localhost", "::1")


def ask_llm(title, project, prompt, env, timeout):
    """'same' | 'related' | 'different' | None (any failure). Ollama on loopback only."""
    base = env.get("DOTS_OLLAMA_URL") or OLLAMA
    if not _loopback(base) or timeout < 0.3:
        return None
    q = ("You classify whether a user's request belongs to a work task. Reply with JSON only: "
         "{\"verdict\":\"same\"|\"related\"|\"different\"}. Use \"different\" only when the request is clearly "
         "unrelated work (another project or topic), not merely a new step.\n"
         f"Task: {title} (project {project or 'none'})\nRequest: {prompt}\n")
    body = json.dumps({"model": env.get("DOTS_TASK_MODEL") or MODEL, "prompt": q, "stream": False,
                       "format": "json", "keep_alive": "10m", "options": {"temperature": 0, "num_predict": 30}}).encode()
    req = urllib.request.Request(base.rstrip("/") + "/api/generate", data=body, headers={"Content-Type": "application/json"})
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))      # never via a proxy
        with opener.open(req, timeout=timeout) as r:
            out = json.loads(json.loads(r.read(65536).decode("utf-8", "replace")).get("response") or "{}")
        v = str(out.get("verdict") or "").lower()
        return v if v in ("same", "related", "different") else None
    except Exception:
        return None


def stop(hook, env, deadline):
    """The block output, or None. Never blocks twice for one prompt, never when already continuing."""
    if hook.get("stop_hook_active") or hook.get("agent_id") or kill_switch(env) or headless(env):
        return None
    sess = str(hook.get("session_id") or "")
    d = task.read_decl(sess) if task.SESS_RE.match(sess) else None
    if not d or d.get("exempt") or not d.get("uuid"):
        return None                                 # nothing declared: the PreToolUse gate's business
    turn = atomic.read_json(task._p(TURN, sess))
    if not isinstance(turn, dict) or len(str(turn.get("prompt") or "").strip()) < TRIVIAL_PROMPT:
        return None
    if turn.get("auto"):
        return None                                 # the harness started this turn, not the user
    if d.get("uuid") != turn.get("decl") and int(d.get("ts") or 0) > int(turn.get("ts") or 0):
        return None                                 # moved to another task after the prompt: already answered
    # (re-declaring the SAME task after the prompt does not count: that would be a way round the check)
    vpath = task._p(VERDICTS, sess)
    cache = atomic.read_json(vpath)
    cache = cache if isinstance(cache, dict) else {}
    key = f"{turn.get('hash')}:{d['uuid'][:8]}"
    hit = cache.get(key)
    if hit and (hit.get("blocked") or hit.get("verdict") != "different"):
        return None
    verdict = (hit or {}).get("verdict") or ask_llm(d.get("title"), d.get("project"), turn["prompt"], env,
                                                    min(LLM_TIMEOUT, deadline - time.monotonic()))
    if verdict is None:
        return None                                 # model down or slow: allow, and do not cache a non-answer
    block = verdict == "different"
    cache = dict(sorted(cache.items(), key=lambda kv: kv[1].get("ts", 0))[-20:])
    cache[key] = {"verdict": verdict, "blocked": block, "ts": int(time.time())}
    atomic.write_json(vpath, cache)
    if not block:
        return None
    ref = d.get("ref") or d.get("uuid", "")[:8]
    return {"decision": "block", "reason": (
        f"This turn looks like different work from the declared task {ref} (\"{d.get('title')}\"). "
        "If it belongs to another existing task: `dots-task switch <ref>`. If it is new work: "
        "`dots-task new \"<title>\" --project <p>`, or ask the user \"log this as a ticket?\". "
        "If it does belong to the current task, say so briefly and finish.")}


# ---- entry ----------------------------------------------------------------------------

def main(event):
    deadline = time.monotonic() + BUDGET
    try:
        hook = json.loads(sys.stdin.read(1 << 20) or "{}")
    except (OSError, ValueError):
        return 0
    if not isinstance(hook, dict):
        return 0
    env = os.environ
    out = None
    try:
        if event in ("session", "prompt"):
            out = on_context("SessionStart" if event == "session" else "UserPromptSubmit", hook, env)
        elif event == "pretool":
            why = pretool(hook, env)
            if why:
                out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                              "permissionDecisionReason": why}}
        elif event == "stop":
            out = stop(hook, env, deadline)
    except Exception:
        out = None
    if out:
        sys.stdout.write(json.dumps(out) + "\n")
    return 0
