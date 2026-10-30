"""Paths and the user's own rules.

Everything that names the employer, its senders or its people lives in hand-written,
unmanaged files under ~/.config/dots-mail/ (dots is public). Everything this package
stores lives INSIDE the encrypted mail store (~/Mail/.state), so mail context, Slack
context, prepared analyses and drafts are ciphertext whenever the user is logged out.
"""
import os
import tomllib
from pathlib import Path

HOME = Path.home()
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
XDG_STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state")

MAIL = Path(os.environ.get("DOTS_INBOX_MAIL") or HOME / "Mail")
BOX = MAIL / "work"                      # maildir root and notmuch database
STATE = MAIL / ".state"                  # inside the encryption
DB = STATE / "touchpoints.db"
PREP_DIR = STATE / "prep"                # one markdown file per prepared analysis
BRIEF = STATE / "brief.md"

CONF_DIR = XDG_CONFIG / "dots-mail"
ACCOUNT = CONF_DIR / "account.conf"
RULES = CONF_DIR / "rules.toml"
AGENT_OFF = CONF_DIR / "AGENT_OFF"      # exists = no LLM run of any kind (Claude AND the local model); rules, floors and toasts go on
# the dashboard reads COUNTS only from here: no subject, sender or body ever leaves the store
OVERVIEW_COUNTS = Path(os.environ.get("DOTS_OVERVIEW_STATE_DIR") or XDG_STATE / "dots-overview") / "inbox.json"
PANIC = XDG_CONFIG / "timetrack" / "PANIC"     # one switch silences every prompt on the machine

OLLAMA = "http://127.0.0.1:11434/api/chat"
LOCAL_MODEL = "qwen3-coder:30b"


def account():
    """{MAIL_ADDRESS: ..., ...} from account.conf (shell KEY=value lines)."""
    out = {}
    try:
        for line in ACCOUNT.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def me():
    return account().get("MAIL_ADDRESS", "").lower()


def rules():
    try:
        with open(RULES, "rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError:
        return {}


def mounted():
    # tests point DOTS_INBOX_MAIL at a temp dir that is not a mount
    return os.path.ismount(MAIL) or os.environ.get("DOTS_INBOX_TEST") == "1"


def panic():
    return PANIC.exists()
