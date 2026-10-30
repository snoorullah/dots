"""touchpoints.db, inside the encrypted store. The only module that opens it."""
import sqlite3

from . import config

SCHEMA = """
-- One row per thing someone is waiting on: them on me (direction 'me') or me on them
-- ('them'). `key` is the message-id (mail) or 'channel:ts' (Slack) of the message that
-- opened it; `thread` is how a reply is recognised (notmuch thread id, 'channel:thread_ts').
CREATE TABLE IF NOT EXISTS item (
  id            INTEGER PRIMARY KEY,
  source        TEXT NOT NULL CHECK (source IN ('mail','slack')),
  direction     TEXT NOT NULL CHECK (direction IN ('them','me')),
  key           TEXT NOT NULL UNIQUE,
  thread        TEXT,
  counterpart   TEXT,
  subject       TEXT,
  purpose       TEXT,          -- why: what was asked, in one line
  task_ref      TEXT,          -- the Taskwarrior/ERP/GitHub ref it belongs to
  session       TEXT,          -- the Claude session that sent it, when one did
  state         TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','replied','done','dropped')),
  created_unix  INTEGER NOT NULL,
  updated_unix  INTEGER NOT NULL,
  reply_unix    INTEGER,
  reply_ref     TEXT,
  reply_summary TEXT,
  notified_unix INTEGER,
  draft         TEXT           -- a suggested reply; never sent by anything here
);
CREATE INDEX IF NOT EXISTS ix_item_thread ON item(thread);
CREATE INDEX IF NOT EXISTS ix_item_state ON item(state, source);

-- Alert mail is a stream of repeats; this is its state. A notification is a TRANSITION.
CREATE TABLE IF NOT EXISTS alert_state (
  name          TEXT NOT NULL,
  scope         TEXT NOT NULL,
  severity      TEXT,
  state         TEXT NOT NULL CHECK (state IN ('firing','resolved')),
  since_unix    INTEGER NOT NULL,    -- when it entered this state
  last_unix     INTEGER NOT NULL,    -- last mail about it
  repeats       INTEGER NOT NULL DEFAULT 1,
  notified_unix INTEGER,
  PRIMARY KEY (name, scope)
);

-- Read-only analyses an agent prepared while the user was away.
CREATE TABLE IF NOT EXISTS prep (
  id            INTEGER PRIMARY KEY,
  kind          TEXT NOT NULL,       -- alert | mail | slack
  ref           TEXT NOT NULL UNIQUE,
  title         TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('queued','running','done','failed','skipped')),
  created_unix  INTEGER NOT NULL,
  finished_unix INTEGER,
  path          TEXT,                -- markdown under STATE/prep/
  summary       TEXT,
  seen_unix     INTEGER
);

-- What happened, for the brief: every notification, reply and prepared analysis.
CREATE TABLE IF NOT EXISTS event (
  ts_unix  INTEGER NOT NULL,
  kind     TEXT NOT NULL,
  ref      TEXT,
  detail   TEXT
);
CREATE INDEX IF NOT EXISTS ix_event_ts ON event(ts_unix);

-- One row per alert mail, keyed by Message-ID: whether its sender passed the entry gate.
-- Offering a ticket needs THIS mail to be authed, never "some mail with this name was".
CREATE TABLE IF NOT EXISTS alert_msg (
  msgid        TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  scope        TEXT NOT NULL,
  authed       INTEGER NOT NULL,
  ts_unix      INTEGER NOT NULL,
  event_rowid  INTEGER               -- the alert_firing event this mail caused, if any
);
-- which Message-ID a prep row was made from
CREATE TABLE IF NOT EXISTS prep_msg (
  ref    TEXT PRIMARY KEY,
  msgid  TEXT NOT NULL
);
"""


def open_db():
    if not config.mounted():
        raise SystemExit("dots-inbox: the mail store is locked (not logged in?)")
    config.STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    conn = sqlite3.connect(config.DB, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(SCHEMA)
    return conn


def log(conn, kind, ref=None, detail=None, ts=None):
    import time
    conn.execute("INSERT INTO event(ts_unix, kind, ref, detail) VALUES(?,?,?,?)",
                 (int(ts or time.time()), kind, ref, detail))
