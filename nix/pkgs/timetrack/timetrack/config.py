"""Paths, and the policy this repo is not allowed to contain.

`dots` is a PUBLIC repo, so nothing machine-, person- or company-specific lives here:
payroll figures, holiday dates, git author identities and the backfill calibration all
come from hand-copied files under ~/.config/timetrack/ (mode 0600) that chezmoi does not
manage. Every accessor below has a safe default so the package still imports and runs on
a machine where those files were never copied.
"""
import os
import tomllib
from datetime import date
from pathlib import Path

HOME = Path.home()
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
XDG_DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")

CONF_DIR = XDG_CONFIG / "timetrack"
# Layer 3 of the dead-man's switch. Its existence is the whole interface: every
# enforcement path checks for the file before it draws anything, and timetrack-deadman
# reaps a panel already on screen within one 30-second cycle when it appears. A plain
# `touch` has to be enough, because the state this exists for is one where the Python
# here may be what is broken.
PANIC = CONF_DIR / "PANIC"
PAYROLL_TOML = CONF_DIR / "payroll.toml"
HOLIDAYS_TOML = CONF_DIR / "holidays.toml"
CATEGORIES_TOML = CONF_DIR / "categories.toml"
WEB_TOML = CONF_DIR / "web.toml"
HABITS_TOML = CONF_DIR / "habits.toml"

STATE_DIR = Path(os.environ.get("TIMETRACK_STATE_DIR") or XDG_DATA / "timetrack")
# dots-overview's record of which Claude session ran where (written by dots-track-hook).
# Read-only here: termclass joins it to pane time. Local file, never leaves the machine.
SESSIONS_JSONL = (Path(os.environ.get("DOTS_OVERVIEW_STATE_DIR")
                       or Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state")
                       / "dots-overview") / "sessions.jsonl")
WORK_DB = STATE_DIR / "work.db"
PRIVATE_DB = STATE_DIR / "private.db"
LOGIND_JSONL = STATE_DIR / "events" / "logind.jsonl"

VAULT = Path(os.environ.get("TIMETRACK_VAULT") or HOME / "powerhouse")
VAULT_DAILY = VAULT / "timetrack" / "daily"
EXPORT_DIR = VAULT / "exports"
# The Obsidian-editable timesheet (vault.py): one markdown table per month, one note per day.
TIMESHEET = VAULT / "time" / "Timesheet"
TIMESHEET_DAYS = TIMESHEET / "days"
VAULT_STATE = STATE_DIR / "vault-rendered.json"

TASK = "task"
TIMEW = "timew"

# Bump when a derivation rule changes. Recorded on every row so a number can always be
# traced to the rules that produced it, and so a submitted figure never silently moves.
RULESET = "v1"

_WEEKDAY = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


def panic():
    """True while enforcement is disabled. Collection is NOT affected, deliberately:
    the user turning off the prompts must not also lose the record of the day."""
    return PANIC.exists()


def _load(path):
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"timetrack: {path} is not valid TOML: {exc}")


def payroll():
    return _load(PAYROLL_TOML)


def hours_per_day():
    return int(payroll().get("rules", {}).get("hours_per_day", 8))


def week_off():
    """Weekday numbers (Mon=0) that are not working days."""
    names = payroll().get("rules", {}).get("week_off", ["Sat", "Sun"])
    return {_WEEKDAY[str(n).strip().lower()[:3]] for n in names}


def gross_monthly():
    v = payroll().get("salary", {}).get("gross_monthly")
    return float(v) if v is not None else None


def currency():
    return payroll().get("salary", {}).get("currency", "")


def calibration():
    """Multiplier correcting git-derived spans against measured spans.

    Default 1.0 -- uncalibrated, and therefore honest. A machine that has been measured
    against a real source sets its own factor in local config.
    """
    return float(payroll().get("backfill", {}).get("calibration", 1.0))


def backfill_authors():
    """Git author emails that count as "me". Personal identifiers: local config only."""
    raw = payroll().get("backfill", {}).get("authors", [])
    return [str(a).strip().lower() for a in raw if str(a).strip()]


def backfill_repo_globs():
    return [str(g) for g in payroll().get("backfill", {}).get("repos", ["~/work/*"])]


def web_ticket_prefixes():
    """Which id prefixes in a URL count as a ticket. An allow-list: ERP URLs also carry
    employee and HR record ids (EMP-00097), which are not work items and must not be
    counted as one."""
    raw = payroll().get("web", {}).get("ticket_prefixes", ["TASK", "PROJ", "ISS"])
    return tuple(str(p).strip().upper() + "-" for p in raw if str(p).strip())


def web():
    """Browser classification settings (webclass.py). Unmanaged and hand-written: the work
    domains and GitHub orgs name the employer, so they never go in the public repo.

        model = "qwen3-coder:30b"
        work_domains = ["erp.example.com", "portal.azure.com"]
        work_github_orgs = ["example-org"]
        nonwork_domains = ["outlook.cloud.microsoft"]   # e.g. mail: not task work by itself
    """
    return _load(WEB_TOML)


def gap_bridge_seconds():
    return int(payroll().get("backfill", {}).get("gap_bridge_minutes", 45)) * 60


def lead_in_seconds():
    return int(payroll().get("backfill", {}).get("lead_in_minutes", 20)) * 60


def workday_gap_seconds():
    """A gap this long or longer is sleep, so it ends the workday.

    Two levels of clustering, because they answer different questions: the short gap
    (gap_bridge_minutes) decides what counts as ACTIVE time inside a day, while this one
    decides where one workday stops and the next begins. Without it a nocturnal schedule
    collapses into nonsense -- an 01:20 start and a 22:45 finish on the same calendar date
    look like a 21-hour day when they are really the tail of one shift and the start of
    the next.
    """
    return int(float(payroll().get("backfill", {}).get("workday_gap_hours", 8)) * 3600)


def holidays():
    """{date: label} of paid holidays. Hand-maintained because the ERP `Holiday` DocType
    is permission-denied for this account, so the dates cannot be fetched."""
    out = {}
    for _year, table in _load(HOLIDAYS_TOML).items():
        if not isinstance(table, dict):
            continue
        for key, label in table.items():
            try:
                out[date.fromisoformat(str(key))] = str(label)
            except ValueError:
                raise SystemExit(f"timetrack: {HOLIDAYS_TOML}: '{key}' is not an ISO date")
    return out


def habits(section):
    """Phase 3 settings (salah, health, login), each a table in habits.toml. Unmanaged:
    an empty dict means every default in the module that asks."""
    v = _load(HABITS_TOML).get(section, {})
    return v if isinstance(v, dict) else {}
