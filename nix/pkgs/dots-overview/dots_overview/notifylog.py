"""Notification log: a read-only eavesdrop on the session bus.

`dbus-monitor` with a match rule on `Notify` only OBSERVES calls other programs make; it
claims no bus name and cannot answer, close or invoke anything. Each call becomes one
line in notifications.jsonl:

    {"ts", "app", "summary", "body" | null, "urgency", "id"}

`body` is stored only for apps in work.conf NOTIFY_BODY_APPS. Everything else keeps its
summary and nothing more, because a notification body is the most private text on the
screen. The file is 0600 and ring-capped at 5000 lines.
"""
import json
import os
import re
import subprocess
import sys
import time

from . import atomic, config

MATCH = "interface='org.freedesktop.Notifications',member='Notify'"
_STR = re.compile(r'^\s*string "(.*)"\s*$')


def parse(lines):
    """Yield one dict per Notify call from `dbus-monitor` text. Pure, so it is unit-tested.

    A Notify call is: app_name, replaces_id, app_icon, summary, body, actions, hints, timeout.
    """
    call = None
    strs = []
    urgency = 1
    pending_urg = False
    for line in lines:
        if line.startswith(("method call", "signal", "method return", "error")):
            if call is not None and len(strs) >= 4:
                yield _mk(call, strs, urgency)
            call = "Notify" if "member=Notify" in line else None
            strs, urgency, pending_urg = [], 1, False
            continue
        if call is None:
            continue
        if 'string "urgency"' in line:
            pending_urg = True
            continue
        if pending_urg and "byte" in line:
            try:
                urgency = int(line.split("byte")[1].split()[0])
            except (IndexError, ValueError):
                pass
            pending_urg = False
            continue
        m = _STR.match(line)
        if m and len(strs) < 5:
            strs.append(m.group(1))
    if call is not None and len(strs) >= 4:
        yield _mk(call, strs, urgency)


def _mk(call, strs, urgency):
    # strs: app_name, app_icon, summary, body (replaces_id is a uint32, not a string)
    return {"app": strs[0], "summary": strs[2], "body": strs[3], "urgency": {0: "low", 1: "normal", 2: "critical"}.get(urgency, "normal")}


def record(event, cfg, now=None):
    """Reduce an event to what policy allows and shape it as a log line."""
    keep_body = event["app"].lower() in [a.lower() for a in cfg.notify_body_apps]
    return {"ts": int(now or time.time()), "app": event["app"], "summary": event["summary"],
            "body": event["body"] if keep_body and event["body"] else None,
            "urgency": event["urgency"], "id": time.time_ns() // 1000000}


def append(path, rec, cap=config.NOTIF_CAP):
    """Append one line, trimming the file to the newest `cap` lines when it overflows."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, separators=(",", ":"), ensure_ascii=False) + "\n")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    if len(lines) > cap + 200:           # trim in batches, not on every line
        atomic.write_text(path, "\n".join(lines[-cap:]) + "\n")


def tail(path, n=200):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()[-n:]
    except OSError:
        return None
    out = []
    for ln in lines:
        try:
            out.append(json.loads(ln))
        except ValueError:
            continue
    return out


def main():
    cfg = config.Work()
    path = config.STATE_DIR / "notifications.jsonl"
    p = subprocess.Popen(["dbus-monitor", "--session", MATCH], stdout=subprocess.PIPE, text=True,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    block = []
    for line in p.stdout:
        if line.startswith(("method call", "signal")) and block:
            for ev in parse(block):
                append(path, record(ev, cfg))
            block = []
        block.append(line.rstrip("\n"))
    for ev in parse(block):
        append(path, record(ev, cfg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
