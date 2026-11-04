#!/usr/bin/env bash
# backfill/aw.not_afk: only a genuinely live not-afk event extends to now. A zero-length
# not-afk stub sharing its timestamp with an open afk event is not presence.
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONPATH=nix/pkgs/timetrack python3 - <<'PY'
from datetime import datetime, timezone
from timetrack.backfill import aw
fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")
def ev(ts, status, dur):
    return {"timestamp": ts, "duration": dur, "data": {"status": status}}
aw.bucket = lambda kind: "afk"
now = datetime(2026, 11, 4, 16, 0, tzinfo=timezone.utc)
def spans(events):
    aw._get = lambda path, timeout=15: events
    return [(a.astimezone(timezone.utc).strftime("%H:%M"), b.astimezone(timezone.utc).strftime("%H:%M"))
            for a, b in aw.not_afk(now=now)]
# 1. stub listed first, afk open at the same instant: no presence after 20:00
check("tie stub first", spans([ev("2026-11-03T21:00:00Z", "not-afk", 0), ev("2026-11-03T21:00:00Z", "afk", 0),
                               ev("2026-11-03T20:00:00Z", "not-afk", 3600)]), [("20:00", "21:00")])
# 2. afk listed first: same answer
check("tie afk first", spans([ev("2026-11-03T21:00:00Z", "afk", 0), ev("2026-11-03T21:00:00Z", "not-afk", 0),
                              ev("2026-11-03T20:00:00Z", "not-afk", 3600)]), [("20:00", "21:00")])
# 3. a genuinely live not-afk still runs to now
check("live run", spans([ev("2026-11-04T15:00:00Z", "not-afk", 0), ev("2026-11-04T14:00:00Z", "afk", 3600)]),
      [("15:00", "16:00")])
if fails:
    print("aw-live FAILED:"); [print("  " + f) for f in fails]; raise SystemExit(1)
print("aw-live ok (3 scenarios)")
PY
