#!/usr/bin/env python3
"""timetrack-logind.py — append systemd-logind session/lock/suspend events as JSONL.

Subscribes (system bus) to:
  org.freedesktop.login1.Manager: PrepareForSleep(b), SessionNew, SessionRemoved
  org.freedesktop.login1.Session: Lock, Unlock
Appends one JSON object per line to ~/.local/share/timetrack/events/logind.jsonl.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from jeepney import HeaderFields, MessageType, MatchRule, message_bus
from jeepney.io.blocking import open_dbus_connection

EVENTS = Path.home() / ".local/share/timetrack/events/logind.jsonl"
EVENTS.parent.mkdir(parents=True, exist_ok=True)


def emit(etype, detail=None):
    rec = {
        "ts": datetime.now(timezone.utc).astimezone().isoformat(),
        "source": "logind",
        "type": etype,
        "detail": detail or {},
    }
    with EVENTS.open("a") as f:
        f.write(json.dumps(rec) + "\n")
        f.flush()


def main():
    conn = open_dbus_connection(bus="SYSTEM")
    rules = [
        MatchRule(type="signal", interface="org.freedesktop.login1.Manager",
                  member="PrepareForSleep", path="/org/freedesktop/login1"),
        MatchRule(type="signal", interface="org.freedesktop.login1.Manager",
                  member="SessionNew", path="/org/freedesktop/login1"),
        MatchRule(type="signal", interface="org.freedesktop.login1.Manager",
                  member="SessionRemoved", path="/org/freedesktop/login1"),
        MatchRule(type="signal", interface="org.freedesktop.login1.Session", member="Lock"),
        MatchRule(type="signal", interface="org.freedesktop.login1.Session", member="Unlock"),
    ]
    for r in rules:
        conn.send_and_get_reply(message_bus.AddMatch(r))

    emit("daemon-start")

    while True:
        msg = conn.receive()
        if msg.header.message_type != MessageType.signal:
            continue
        member = msg.header.fields.get(HeaderFields.member)
        path = str(msg.header.fields.get(HeaderFields.path))
        body = list(msg.body) if msg.body else []
        if member == "PrepareForSleep":
            going = bool(body[0]) if body else None
            emit("suspend" if going else "resume", {"prepare_for_sleep": going})
        elif member == "Lock":
            emit("lock", {"path": path})
        elif member == "Unlock":
            emit("unlock", {"path": path})
        elif member == "SessionNew":
            emit("session-new", {"body": [str(b) for b in body]})
        elif member == "SessionRemoved":
            emit("session-removed", {"body": [str(b) for b in body]})


if __name__ == "__main__":
    main()
