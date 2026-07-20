"""Canonical paths + the 4am logical-day boundary for the timetrack rollup."""
import os
from datetime import datetime, date, timedelta
from pathlib import Path

HOME = Path.home()

# Phase 5 (dotfiles/NixOS port): these were hardcoded absolute paths
# (/home/linuxbrew/.linuxbrew/bin/task, /usr/bin/timew) on the live box.
# On the laptop, task/timew are resolved bare -- the `timetrack` runner
# (home/modules/timetrack.nix) guarantees both are on PATH via
# writeShellApplication's runtimeInputs (taskwarrior3 + timewarrior).
TASK = "task"    # taskwarrior3 (nixpkgs)
TIMEW = "timew"  # timewarrior (nixpkgs)
AW_BASE = "http://127.0.0.1:5600"
LOGIND_JSONL = HOME / ".local/share/timetrack/events/logind.jsonl"

DB_PATH = HOME / ".local/share/timetrack/timetrack.db"
DATA_REPO = HOME / ".local/share/timetrack/data-repo"      # private git clone; dump into DATA_REPO/tables/
VAULT_DAILY = HOME / "powerhouse/timetrack/daily"          # PERSONAL vault only
CATEGORIES_TOML = HOME / ".config/timetrack/categories.toml"

WEB_BUCKET = None          # aw-watcher-web bucket id (e.g. "aw-watcher-web-brave"); None = auto-detect/skip

HABIT_SPRINT_START = None  # date | None — set to start the "day X of 14" graduation countdown in the note header

DAY_BOUNDARY_HOUR = 4

def logical_date(dt: datetime) -> date:
    """The 'day' a timestamp belongs to, with the day starting at 04:00 local."""
    return (dt - timedelta(hours=DAY_BOUNDARY_HOUR)).date()
