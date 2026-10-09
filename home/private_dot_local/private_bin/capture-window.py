#!/usr/bin/env python3
"""capture-window — Layer-1 spine, window-focus stream (Powerhouse capture).

Reads the Hyprland event socket (socket2) and appends one JSON line per active-window
change to ~/capture/<device>/window/YYYY-MM-DD.jsonl. This is the highest-value single
ADHD signal: app dwell + context-switch rate (fragmentation).

Design contract (blueprint/design/08-capture-layer.md):
  - daemon-driven, zero human action; delivers value the moment it runs.
  - append-only JSONL, one file per UTC day (auto-rolls at midnight).
  - each record: {ts_utc, source, device, stream, event, class, title}. UTC only.
  - PERSONAL machine only -> titles captured raw (never run on a work machine).
  - self-heals: auto-discovers the socket, reconnects across Hyprland restarts, so it
    needs no maintenance (the completion-recursion rule: no upkeep required).
"""
import os
import glob
import json
import time
import socket
import datetime
import pathlib
import platform

DEVICE = platform.node() or "unknown"
BASE = pathlib.Path.home() / "capture" / DEVICE / "window"


def socket2_path():
    """Newest Hyprland event socket for this user (survives HIS changes on restart)."""
    xdg = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    socks = sorted(glob.glob(f"{xdg}/hypr/*/.socket2.sock"), key=os.path.getmtime)
    return socks[-1] if socks else None


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def append(rec):
    day = utc_now().strftime("%Y-%m-%d")
    BASE.mkdir(parents=True, exist_ok=True)
    with open(BASE / f"{day}.jsonl", "a") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def emit(event, cls, title):
    append({
        "ts_utc": utc_now().isoformat(timespec="milliseconds"),
        "source": "hyprland",
        "device": DEVICE,
        "stream": "window",
        "event": event,
        "class": cls,
        "title": title,
    })


def run():
    path = None
    while path is None:            # wait for Hyprland if we started first
        path = socket2_path()
        if path is None:
            time.sleep(2)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    emit("daemon_start", "", "")
    # socket2 emits newline-delimited "EVENT>>DATA" lines; we want activewindow.
    for raw in s.makefile("r", encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        if line.startswith("activewindow>>"):
            cls, _, title = line[len("activewindow>>"):].partition(",")
            emit("focus", cls, title)


def main():
    while True:
        try:
            run()
        except (FileNotFoundError, ConnectionError, OSError):
            pass                    # Hyprland restarted / socket gone -> rediscover
        time.sleep(3)


if __name__ == "__main__":
    main()
