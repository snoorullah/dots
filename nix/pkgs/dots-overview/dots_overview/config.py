"""Paths, and the work.conf reader.

`dots` is a PUBLIC repo: nothing company-specific lives here. Org names, the ERP base URL
and the list of company projects come from ~/.config/dots-work/work.conf, a file a human
writes by hand and chezmoi never manages. Every accessor has a safe default, so the
package imports and runs on a machine where that file was never written.

work.conf is KEY=VALUE, shell-style comments and optional quotes. It is parsed here, not
sourced: nothing in it is ever executed.
"""
import os
import shlex
from pathlib import Path

HOME = Path.home()
VERSION = "1"
WRITER = f"dots-overview {VERSION}"

STATE_DIR = Path(os.environ.get("DOTS_OVERVIEW_STATE_DIR")
                 or Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "dots-overview")
CONF = Path(os.environ.get("DOTS_WORK_CONF")
            or Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "dots-work/work.conf")
OPS_STATE = Path(os.environ.get("OPS_STATE")
                 or Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "dots-ops/state")
TT_DIR = Path(os.environ.get("TIMETRACK_STATE_DIR")
              or Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "timetrack")

# A state file older than this is stale to every reader (the spec's 180 s).
STALE_SEC = 180
NOTIF_CAP = 5000


def _split(v):
    return v.replace(",", " ").split()


def parse(text):
    """KEY=VALUE lines -> dict of strings. Quotes are honoured, `#` starts a comment."""
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        if not k.replace("_", "").isalnum():
            continue
        try:
            parts = shlex.split(v, comments=True)
        except ValueError:
            parts = [v.strip()]
        out[k] = " ".join(parts)
    return out


class Work:
    """The parsed work.conf, with the defaults the spec names."""

    def __init__(self, raw=None):
        raw = raw if raw is not None else self._load()
        self.raw = raw
        self.gh_org = raw.get("WORK_GH_ORG", "")
        self.gh_repos = _split(raw.get("WORK_GH_REPOS", ""))
        self.erp_mode = raw.get("ERP_MODE", "off") or "off"
        self.erp_base_url = raw.get("ERP_BASE_URL", "")
        self.erp_key_file = raw.get("ERP_KEY_FILE", "")
        self.erp_doctypes = [d.strip() for d in raw.get("ERP_DOCTYPES", "ToDo,HD Ticket,Task").split(",") if d.strip()]
        self.work_projects = _split(raw.get("WORK_PROJECTS", ""))
        self.notify_body_apps = _split(raw.get("NOTIFY_BODY_APPS", ""))
        self.redact_words = _split(raw.get("REDACT_WORDS", ""))
        self.report_dir = Path(os.path.expanduser(raw.get("REPORT_DIR") or "~/powerhouse/reports/daily"))

    @staticmethod
    def _load():
        try:
            return parse(CONF.read_text(encoding="utf-8"))
        except OSError:
            return {}

    def is_work_repo(self, name_with_owner):
        """True when an owner/repo is company work under WORK_GH_ORG / WORK_GH_REPOS."""
        if not name_with_owner:
            return False
        if self.gh_repos:
            return name_with_owner in self.gh_repos
        return bool(self.gh_org) and name_with_owner.split("/", 1)[0].lower() == self.gh_org.lower()

    def is_work_task(self, t):
        """A Taskwarrior task (export dict) counted as company work, for the brief."""
        if t.get("project") and t["project"] in self.work_projects:
            return True
        if t.get("src") == "erp":
            return True
        if t.get("src") == "gh":
            ref = t.get("ref") or ""
            repo = ref[3:].split("#", 1)[0] if ref.startswith("gh:") else ""
            return self.is_work_repo(repo)
        return False
