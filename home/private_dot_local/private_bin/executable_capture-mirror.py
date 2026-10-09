#!/usr/bin/env python3
"""capture-mirror — the day-one mirror (blueprint/design/08 section 5).

Plain "here is what you actually did today", ZERO interpretation. Its only job is to make
the capture visible immediately so the system pays off before any insight exists — the
anti-abandonment piece. Reads today's window stream; prints app dwell + context-switch
count. No judgement, no correlations, no advice.
"""
import sys
import json
import datetime
import pathlib
import platform
import collections

DEVICE = platform.node() or "unknown"
day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
path = pathlib.Path.home() / "capture" / DEVICE / "window" / f"{day}.jsonl"

if not path.exists():
    print(f"no capture yet for {day} ({DEVICE})")
    sys.exit(0)

events = []
for line in path.read_text().splitlines():
    try:
        events.append(json.loads(line))
    except Exception:
        pass

focus = [e for e in events if e.get("event") == "focus"]


def ts(rec):
    return datetime.datetime.fromisoformat(rec["ts_utc"])


dwell = collections.Counter()
switches = 0
prev = None
for e in focus:
    if prev is not None:
        dwell[prev.get("class") or "(none)"] += (ts(e) - ts(prev)).total_seconds()
        if e.get("class") != prev.get("class"):
            switches += 1
    prev = e

total_min = sum(dwell.values()) / 60
print(f"── mirror · {day} · {DEVICE} ──")
print(f"focus changes: {len(focus)}    app switches: {switches}    tracked: {total_min:.0f} min")
if dwell:
    print("time by app (min):")
    for cls, secs in dwell.most_common(12):
        print(f"  {cls:24} {secs / 60:6.1f}")
