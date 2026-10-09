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
  - retention: CAPTURE_RETENTION_DAYS=N (env) deletes YYYY-MM-DD.jsonl day files older than
    N days, checked once per UTC day; unset or 0 keeps everything. capture-window.service sets 365.
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


def retention_days():
    try:
        return max(0, int(os.environ.get("CAPTURE_RETENTION_DAYS", "0") or 0))
    except ValueError:
        return 0


_pruned_day = None


def prune(day):
    """Delete day files older than CAPTURE_RETENTION_DAYS (by the date in the name); once per UTC day."""
    global _pruned_day
    keep = retention_days()
    if keep == 0 or _pruned_day == day:
        return
    _pruned_day = day
    cutoff = (utc_now() - datetime.timedelta(days=keep)).strftime("%Y-%m-%d")
    for f in BASE.glob("[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl"):
        if f.stem < cutoff:
            try:
                f.unlink()
            except OSError:
                pass


def append(rec):
    day = utc_now().strftime("%Y-%m-%d")
    BASE.mkdir(parents=True, exist_ok=True)
    prune(day)
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
