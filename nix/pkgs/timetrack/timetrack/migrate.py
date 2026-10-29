"""Explicit DDL with PRAGMA user_version migrations.

The previous design let sqlite_utils infer the schema from whatever happened to be
upserted. On a file that decides someone's pay that is not acceptable: there was no
CREATE TABLE anywhere, so "no work today" and "the table was never created" were
indistinguishable, and `alter=True` meant a typo in a key name silently added a column.

The DDL is embedded here rather than shipped as schema/*.sql so the package stays a
single importable unit with no data files to install -- it is still explicit, versioned
and reviewable in one place.
"""
import sqlite3

from . import dbs

WORK_V1 = """
-- Append-only ledger of clock state transitions: the ONLY source of truth for
-- attendance. Never UPDATEd, never DELETEd. Every reported number is recomputed from
-- these rows, so a daemon outage costs resolution, never data.
CREATE TABLE clock_event (
  id             INTEGER PRIMARY KEY,
  ts             TEXT    NOT NULL,            -- RFC3339 with offset
  ts_unix        INTEGER NOT NULL,
  attendance_day TEXT    NOT NULL,            -- YYYY-MM-DD, inherited from the session
  session_id     INTEGER NOT NULL REFERENCES work_session(id),
  kind           TEXT    NOT NULL,
  ticket         TEXT,
  actor          TEXT    NOT NULL,
  -- Opaque slot id such as 'slot:7'. NEVER a pane title or cwd: those carry company and
  -- cluster names, and this table is the one that may leave the machine.
  actor_ref      TEXT,
  reason_code    TEXT,                        -- enum only, never prose
  provenance     TEXT    NOT NULL,
  ruleset        TEXT    NOT NULL,
  confidence     REAL    NOT NULL DEFAULT 1.0,
  -- No 'lock' member, deliberately: the old code treated a screen lock as a clock-out,
  -- so ten minutes reading a PDF ended the working day. Progress continues behind a
  -- lock screen, and the CHECK makes that a schema-level guarantee.
  CHECK (kind IN ('session_open','session_close','run_start','run_stop',
                  'grace_start','grace_cancel','ticket_bind','ticket_unbind',
                  'deduction_start','deduction_stop','attest')),
  CHECK (actor IN ('human','agent','system')),
  CHECK (confidence > 0.0 AND confidence <= 1.0)
);
CREATE INDEX ix_ce_day  ON clock_event(attendance_day, ts_unix);
CREATE INDEX ix_ce_sess ON clock_event(session_id, ts_unix);
CREATE INDEX ix_ce_tkt  ON clock_event(ticket, ts_unix) WHERE ticket IS NOT NULL;

-- A session owns its attendance_day for good, and every event inherits it. This is what
-- "the login day owns the session" has to mean in practice: logind sessions are useless
-- here (one session stayed open for seven days), so sessions are derived from activity.
CREATE TABLE work_session (
  id             INTEGER PRIMARY KEY,
  opened_ts      TEXT    NOT NULL,
  opened_unix    INTEGER NOT NULL,
  closed_ts      TEXT,
  closed_unix    INTEGER,
  attendance_day TEXT    NOT NULL,
  open_trigger   TEXT    NOT NULL,
  close_trigger  TEXT,
  provenance     TEXT    NOT NULL
);
CREATE INDEX ix_ws_day ON work_session(attendance_day);

-- Breaks. Category only: the free text and the guess live in private.db.
CREATE TABLE deduction (
  id             INTEGER PRIMARY KEY,
  session_id     INTEGER REFERENCES work_session(id),
  attendance_day TEXT    NOT NULL,
  start_unix     INTEGER NOT NULL,
  end_unix       INTEGER,
  category       TEXT    NOT NULL,
  minutes        INTEGER,
  confirmed      INTEGER NOT NULL DEFAULT 0,
  provenance     TEXT    NOT NULL,
  CHECK (category IN ('salah','lunch','washroom','misc','call_personal'))
);
CREATE INDEX ix_ded_day ON deduction(attendance_day);

-- Per-ticket minutes, split so the submitted headline can be human-attended time while
-- agent-only time stays a separate, labelled line.
CREATE TABLE ticket_minutes (
  ticket         TEXT    NOT NULL,
  attendance_day TEXT    NOT NULL,
  minutes        INTEGER NOT NULL,
  human_minutes  INTEGER NOT NULL,
  agent_minutes  INTEGER NOT NULL,
  status         TEXT,
  ruleset        TEXT    NOT NULL,
  computed_unix  INTEGER NOT NULL,
  PRIMARY KEY (ticket, attendance_day)
);

-- The target denominator. note_ref is an opaque key into private.db, never the text.
CREATE TABLE day_class (
  day            TEXT PRIMARY KEY,
  kind           TEXT NOT NULL,
  leave_type     TEXT,
  pay_affecting  INTEGER NOT NULL DEFAULT 0,
  target_minutes INTEGER NOT NULL,
  note_ref       TEXT,
  attested_unix  INTEGER,
  CHECK (kind IN ('working','weekend','holiday','leave_paid','leave_unpaid',
                  'absent','worked_unlogged'))
);

-- Written once per month at submission and never UPDATEd. input_digest pins the exact
-- rows the figure came from, so a later bug cannot move a number already handed over.
CREATE TABLE monthly_submission (
  month          TEXT PRIMARY KEY,
  submitted_unix INTEGER NOT NULL,
  target_minutes INTEGER NOT NULL,
  worked_minutes INTEGER NOT NULL,
  delta_minutes  INTEGER NOT NULL,
  basis          TEXT    NOT NULL,
  ruleset        TEXT    NOT NULL,
  input_digest   TEXT    NOT NULL,
  export_path    TEXT    NOT NULL
);

-- The egress allow-list. Nothing leaves that is not named here, and
-- `timetrack egress --explain` prints this table with the SQL behind each field.
CREATE TABLE egress_field (
  target     TEXT NOT NULL,
  field      TEXT NOT NULL,
  source_sql TEXT NOT NULL,
  PRIMARY KEY (target, field)
);

CREATE TABLE schema_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);

-- Pair run_start with the run_stop that follows it in the same session.
CREATE VIEW v_run_interval AS
WITH ev AS (
  SELECT id, session_id, attendance_day, ts_unix, kind, provenance, confidence, ticket,
         LEAD(ts_unix) OVER w AS next_unix,
         LEAD(kind)    OVER w AS next_kind
  FROM clock_event
  WHERE kind IN ('run_start','run_stop')
  WINDOW w AS (PARTITION BY session_id ORDER BY ts_unix, id)
)
SELECT session_id, attendance_day, ticket, provenance, confidence,
       ts_unix AS start_unix, next_unix AS end_unix, (next_unix - ts_unix) AS seconds
FROM ev
WHERE kind = 'run_start' AND next_kind = 'run_stop' AND next_unix > ts_unix;

CREATE VIEW v_day_span AS
SELECT attendance_day,
       CAST(ROUND(SUM(seconds) / 60.0) AS INTEGER) AS span_minutes,
       MIN(start_unix) AS first_unix,
       MAX(end_unix)   AS last_unix,
       GROUP_CONCAT(DISTINCT provenance) AS provenance,
       MIN(confidence) AS min_confidence
FROM v_run_interval
GROUP BY attendance_day;

CREATE VIEW v_day_deduction AS
SELECT attendance_day,
       CAST(ROUND(SUM(minutes)) AS INTEGER) AS deduction_minutes,
       SUM(CASE WHEN confirmed = 0 THEN 1 ELSE 0 END) AS unconfirmed
FROM deduction
WHERE end_unix IS NOT NULL
GROUP BY attendance_day;

-- net_minutes is NULL when no break has been recorded for the day. That is deliberate:
-- the employer's rule is net of breaks, so presenting a span as if it were net would
-- over-report. A NULL forces the export to show the gap instead of inventing a number.
CREATE VIEW v_day_worked AS
SELECT c.day AS attendance_day, c.kind, c.leave_type, c.pay_affecting, c.target_minutes,
       COALESCE(s.span_minutes, 0) AS span_minutes,
       s.first_unix, s.last_unix, s.provenance, s.min_confidence,
       d.deduction_minutes, d.unconfirmed,
       CASE WHEN d.deduction_minutes IS NULL THEN NULL
            ELSE COALESCE(s.span_minutes, 0) - d.deduction_minutes END AS net_minutes
FROM day_class c
LEFT JOIN v_day_span s      ON s.attendance_day = c.day
LEFT JOIN v_day_deduction d ON d.attendance_day = c.day;
"""

PRIVATE_V1 = """
-- Prose for a classified day (leave reason, attestation note). work.db keeps only the
-- opaque note_ref that points here.
CREATE TABLE day_note (
  note_ref TEXT PRIMARY KEY,
  day      TEXT NOT NULL,
  text     TEXT NOT NULL
);

-- Surplus carry-forward: a private ledger, excluded from anything submitted, because it
-- has not been confirmed as company policy.
CREATE TABLE carry_forward (
  month           TEXT PRIMARY KEY,
  surplus_minutes INTEGER NOT NULL,
  running_balance INTEGER NOT NULL
);

CREATE TABLE schema_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
"""


# --- work v2 ---------------------------------------------------------------
# 'dinner' added to deduction.category. The original five were written for a day shift;
# this user's is 13:30-22:30, so the evening meal is the NORMAL one and 'lunch' would be
# wrong on almost every record. Labelling a 21:34 meal break "lunch" in a payroll export
# is the kind of small untruth that makes a reviewer doubt the rest of the figure.
#
# SQLite cannot alter a CHECK, so the table is rebuilt. Done now, while deduction holds
# a few dozen rows, rather than after a year of them.
WORK_V2 = """
PRAGMA foreign_keys=OFF;
-- The views must go FIRST. SQLite resolves a view's body lazily, so dropping a table a
-- view references leaves the schema in a state where the very next statement fails with
-- "error in view v_day_deduction: no such table: main.deduction". executescript does not
-- run in a transaction, so that failure left the database half-migrated: deduction gone,
-- deduction_new holding the rows, user_version still 1. Recreating the views afterwards
-- is what makes this safe to run on a populated database.
DROP VIEW IF EXISTS v_day_worked;
DROP VIEW IF EXISTS v_day_deduction;

CREATE TABLE deduction_new (
  id             INTEGER PRIMARY KEY,
  session_id     INTEGER REFERENCES work_session(id),
  attendance_day TEXT    NOT NULL,
  start_unix     INTEGER NOT NULL,
  end_unix       INTEGER,
  category       TEXT    NOT NULL,
  minutes        INTEGER,
  confirmed      INTEGER NOT NULL DEFAULT 0,
  provenance     TEXT    NOT NULL,
  CHECK (category IN ('salah','lunch','dinner','washroom','misc','call_personal'))
);
INSERT INTO deduction_new SELECT id, session_id, attendance_day, start_unix, end_unix,
  category, minutes, confirmed, provenance FROM deduction;
DROP TABLE deduction;
ALTER TABLE deduction_new RENAME TO deduction;
CREATE INDEX IF NOT EXISTS ix_ded_day ON deduction(attendance_day);

CREATE VIEW v_day_deduction AS
SELECT attendance_day,
       CAST(ROUND(SUM(minutes)) AS INTEGER) AS deduction_minutes,
       SUM(CASE WHEN confirmed = 0 THEN 1 ELSE 0 END) AS unconfirmed
FROM deduction
WHERE end_unix IS NOT NULL
GROUP BY attendance_day;

CREATE VIEW v_day_worked AS
SELECT c.day AS attendance_day, c.kind, c.leave_type, c.pay_affecting, c.target_minutes,
       COALESCE(s.span_minutes, 0) AS span_minutes,
       s.first_unix, s.last_unix, s.provenance, s.min_confidence,
       d.deduction_minutes, d.unconfirmed,
       CASE WHEN d.deduction_minutes IS NULL THEN NULL
            ELSE COALESCE(s.span_minutes, 0) - d.deduction_minutes END AS net_minutes
FROM day_class c
LEFT JOIN v_day_span s      ON s.attendance_day = c.day
LEFT JOIN v_day_deduction d ON d.attendance_day = c.day;
PRAGMA foreign_keys=ON;
"""

# --- work v3 ---------------------------------------------------------------
# The live clock goes in as a SHADOW. Its runs are recorded in clock_event like any other,
# but they are not summed into the day until schema_meta.live_counts is '1'.
#
# Why it cannot simply count from the day it is switched on, found before switching it on:
#
#   1. v_day_span sums every run regardless of actor, and clockd keeps a run open while an
#      agent advances with the human away. The submitted headline would then carry
#      agent-only time, which D3 says is dashboard-only.
#   2. ActivityWatch already measures the same minutes, so the day would be counted twice,
#      and the hourly AW refresh would then drop its own session and skip the day because a
#      live one exists, losing everything AW measured before the switch.
#
# Until both are settled the headline stays AW plus what the user recorded by hand, exactly
# as before, and the live rows accumulate as evidence: v_live_interval shows them so they
# can be compared against AW day by day before anyone decides they are the better source.
# Promotion is one row, `UPDATE schema_meta SET v='1' WHERE k='live_counts'`, and that row
# is part of input_digest, so a promotion after a submission shows up as drift, not as a
# quietly different number.
#
# Views only, so no table rebuild; wrapped in a transaction because executescript commits as
# it goes and v2 taught what a half-applied migration costs.
_RUN_CTE = """
WITH ev AS (
  SELECT id, session_id, attendance_day, ts_unix, kind, provenance, confidence, ticket, actor,
         LEAD(ts_unix) OVER w AS next_unix,
         LEAD(kind)    OVER w AS next_kind
  FROM clock_event
  WHERE kind IN ('run_start','run_stop') AND {where}
  WINDOW w AS (PARTITION BY session_id ORDER BY ts_unix, id)
)
SELECT session_id, attendance_day, ticket, provenance, confidence, actor,
       ts_unix AS start_unix, next_unix AS end_unix, (next_unix - ts_unix) AS seconds
FROM ev
WHERE kind = 'run_start' AND next_kind = 'run_stop' AND next_unix > ts_unix"""

WORK_V3 = """
BEGIN;
INSERT OR IGNORE INTO schema_meta(k, v) VALUES ('live_counts', '0');
DROP VIEW IF EXISTS v_day_worked;
DROP VIEW IF EXISTS v_day_span;
DROP VIEW IF EXISTS v_run_interval;
CREATE VIEW v_run_interval AS""" + _RUN_CTE.format(
    where="(provenance != 'live' OR (SELECT v FROM schema_meta WHERE k = 'live_counts') = '1')") + """;
CREATE VIEW v_live_interval AS""" + _RUN_CTE.format(where="provenance = 'live'") + """;
CREATE VIEW v_day_span AS
SELECT attendance_day,
       CAST(ROUND(SUM(seconds) / 60.0) AS INTEGER) AS span_minutes,
       MIN(start_unix) AS first_unix,
       MAX(end_unix)   AS last_unix,
       GROUP_CONCAT(DISTINCT provenance) AS provenance,
       MIN(confidence) AS min_confidence
FROM v_run_interval
GROUP BY attendance_day;
CREATE VIEW v_day_worked AS
SELECT c.day AS attendance_day, c.kind, c.leave_type, c.pay_affecting, c.target_minutes,
       COALESCE(s.span_minutes, 0) AS span_minutes,
       s.first_unix, s.last_unix, s.provenance, s.min_confidence,
       d.deduction_minutes, d.unconfirmed,
       CASE WHEN d.deduction_minutes IS NULL THEN NULL
            ELSE COALESCE(s.span_minutes, 0) - d.deduction_minutes END AS net_minutes
FROM day_class c
LEFT JOIN v_day_span s      ON s.attendance_day = c.day
LEFT JOIN v_day_deduction d ON d.attendance_day = c.day;
COMMIT;
"""

# --- work v4 ---------------------------------------------------------------
# egress_field was the allow-list for a sync that will never be built: nothing leaves this
# machine (decided 2026-10-23). A table describing an outbound path invites someone to
# build one, so it goes.
WORK_V4 = """
BEGIN;
DROP TABLE IF EXISTS egress_field;
COMMIT;
"""

# --- private v2 -------------------------------------------------------------
# Browser time per site and per ticket (web.py). Domain and ticket id only -- never the
# URL or the page title. Derived: web.write() replaces a day rather than adding to it.
PRIVATE_V2 = """
BEGIN;
CREATE TABLE web_domain_day (
  day     TEXT    NOT NULL,
  domain  TEXT    NOT NULL,
  seconds INTEGER NOT NULL,
  PRIMARY KEY (day, domain)
);
CREATE TABLE web_ticket_day (
  day     TEXT    NOT NULL,
  ticket  TEXT    NOT NULL,
  seconds INTEGER NOT NULL,
  PRIMARY KEY (day, ticket)
);
COMMIT;
"""

# --- work v5 ---------------------------------------------------------------
# An explicit logout (Super+Esc -> "log out for today"). It ENDS the day: presence after
# it never extends that day's session. Coming back afterwards is a new login, clustered
# afresh. A table, not a clock_event kind, because it must exist before any session does
# -- the AW ingest reads it to decide where sessions end.
WORK_V5 = """
BEGIN;
CREATE TABLE logout (
  ts_unix    INTEGER PRIMARY KEY,
  provenance TEXT    NOT NULL
);
COMMIT;
"""

# --- private v3 -------------------------------------------------------------
# Browser VISITS with what they were (webclass.py). Unlike v2's domain totals this keeps the
# page -- URL without query or fragment, and a redacted title -- because "40m github.com"
# says nothing, and the user asked to see what each visit actually was. private.db only.
PRIVATE_V3 = """
BEGIN;
CREATE TABLE web_visit (
  id          INTEGER PRIMARY KEY,
  day         TEXT    NOT NULL,
  start_unix  INTEGER NOT NULL,
  end_unix    INTEGER NOT NULL,
  seconds     INTEGER NOT NULL,
  domain      TEXT    NOT NULL,
  url         TEXT    NOT NULL,
  title       TEXT,
  ticket      TEXT,
  link        TEXT,
  task_uuid   TEXT,
  activity    TEXT    NOT NULL,
  category    TEXT    NOT NULL,
  work        INTEGER NOT NULL,
  verdict     TEXT    NOT NULL CHECK (verdict IN ('work','delegated','unproductive')),
  agent_share REAL    NOT NULL,
  labelled_by TEXT    NOT NULL,
  model       TEXT
);
CREATE INDEX ix_wv_day ON web_visit(day, start_unix);
-- one label per page, so the model is asked about a page once
CREATE TABLE web_label_cache (
  key          TEXT PRIMARY KEY,
  label        TEXT    NOT NULL,
  created_unix INTEGER NOT NULL
);
COMMIT;
"""

# --- private v4 -------------------------------------------------------------
# Which terminal pane had focus, and what that time was (focuslog.py, termclass.py).
# Pane titles, cwds and labels name the employer and its hosts, so ALL of it lives here and
# never in work.db. focus_span is the raw log (one row per uninterrupted focus on one pane
# with one context; end_unix NULL while open, seen_unix is a heartbeat so a crash can be
# closed where the previous life last looked). term_segment is derived and replaced per day.
PRIVATE_V4 = """
BEGIN;
CREATE TABLE focus_span (
  id            INTEGER PRIMARY KEY,
  start_unix    INTEGER NOT NULL,
  end_unix      INTEGER,
  seen_unix     INTEGER,
  pane_id       TEXT    NOT NULL,
  tab_id        TEXT,
  workspace_id  TEXT,
  terminal_id   TEXT,
  agent_session TEXT,
  ticket_token  TEXT,
  cwd           TEXT,
  ws_label      TEXT,
  tab_label     TEXT,
  pane_label    TEXT
);
CREATE INDEX ix_fs_start ON focus_span(start_unix);
CREATE TABLE term_segment (
  id            INTEGER PRIMARY KEY,
  day           TEXT    NOT NULL,
  start_unix    INTEGER NOT NULL,
  end_unix      INTEGER NOT NULL,
  seconds       INTEGER NOT NULL,
  pane_id       TEXT,
  terminal_id   TEXT,
  agent_session TEXT,
  agent_name    TEXT,
  task_uuid     TEXT,
  ref           TEXT,
  project       TEXT,
  activity      TEXT    NOT NULL,
  verdict       TEXT    NOT NULL CHECK (verdict IN ('work','delegated','unproductive')),
  labelled_by   TEXT    NOT NULL CHECK (labelled_by IN
                  ('session','token','branch','repo','llm','title','none')),
  model         TEXT
);
CREATE INDEX ix_ts_day ON term_segment(day, start_unix);
CREATE TABLE term_day (
  day        TEXT    NOT NULL,
  task_uuid  TEXT    NOT NULL DEFAULT '',
  ref        TEXT    NOT NULL DEFAULT '',
  project    TEXT    NOT NULL DEFAULT '',
  agent_name TEXT    NOT NULL DEFAULT '',
  verdict    TEXT    NOT NULL,
  seconds    INTEGER NOT NULL,
  PRIMARY KEY (day, task_uuid, ref, project, agent_name, verdict)
);
-- one label per (cwd, labels, session summary, prompts), so the model is asked once
CREATE TABLE term_label_cache (
  key          TEXT PRIMARY KEY,
  label        TEXT    NOT NULL,
  created_unix INTEGER NOT NULL
);
COMMIT;
"""

# --- private v5 -------------------------------------------------------------
# Phase 3, all personal and all local: salah (D8), the dose and its checkpoints (D18), the
# login habit (D15) and the blocking-prompt budget (D21). Every reason is an enum code,
# never prose. `day` is the attendance day of the session it happened in, never midnight.
PRIVATE_V5 = """
BEGIN;
-- One row per prayer per day. `enforcement` is what the enforcer did; `status` is how the
-- user says it was prayed (the Super+Shift+; picker), NULL until they say.
CREATE TABLE salah_log (
  id            INTEGER PRIMARY KEY,
  day           TEXT    NOT NULL,
  prayer        TEXT    NOT NULL,
  iqamah_unix   INTEGER,
  nudged_unix   INTEGER,
  snoozed       INTEGER NOT NULL DEFAULT 0,
  locked_unix   INTEGER,
  unlocked_unix INTEGER,
  enforcement   TEXT    NOT NULL CHECK (enforcement IN
                  ('pending','locked','declared','logged','qaza','vetoed','away','spaced',
                   'disabled','panic','no_session')),
  status        TEXT    CHECK (status IN ('jamaah','alone','qaza','missed')),
  qaza_reason   TEXT    CHECK (qaza_reason IN
                  ('meeting','incident','call','travel','long_command','other')),
  veto_reason   TEXT,
  strike        INTEGER NOT NULL DEFAULT 0,
  logged_unix   INTEGER,
  UNIQUE (day, prayer)
);
-- Three strikes pause locking for a week. A row per pause, so the history stays.
CREATE TABLE salah_pause (
  start_unix INTEGER PRIMARY KEY,
  until_unix INTEGER NOT NULL,
  reason     TEXT    NOT NULL
);
CREATE TABLE med_dose (
  ts_unix    INTEGER PRIMARY KEY,
  day        TEXT    NOT NULL,
  provenance TEXT    NOT NULL
);
CREATE TABLE health_checkpoint (
  id            INTEGER PRIMARY KEY,
  day           TEXT    NOT NULL,
  slot          TEXT    NOT NULL CHECK (slot IN ('dose','h1','h3','h6','wrap')),
  due_unix      INTEGER NOT NULL,
  asked_unix    INTEGER,
  answered_unix INTEGER,
  score         INTEGER CHECK (score BETWEEN 1 AND 5),
  outcome       TEXT    NOT NULL CHECK (outcome IN
                  ('pending','answered','dismissed','timeout','skipped')),
  UNIQUE (day, slot)
);
CREATE TABLE login_log (
  ts_unix      INTEGER PRIMARY KEY,
  day          TEXT    NOT NULL,
  first_of_day INTEGER NOT NULL,
  late_minutes INTEGER,
  phase        TEXT    CHECK (phase IN ('nudge','enforce','off')),
  prompt       TEXT    CHECK (prompt IN ('none','toast','panel','deferred','timeout')),
  reason       TEXT    CHECK (reason IN
                  ('slept_late','worked_late','appointment','unwell','other'))
);
-- D21: every blocking prompt, shown or deferred. Salah and away gaps are exempt and
-- never written here.
CREATE TABLE prompt_log (
  ts_unix INTEGER NOT NULL,
  kind    TEXT    NOT NULL,
  outcome TEXT    NOT NULL CHECK (outcome IN ('shown','deferred')),
  PRIMARY KEY (ts_unix, kind)
);
COMMIT;
"""

# --- private v6 -------------------------------------------------------------
# Who set a prayer's status: the user (the picker), or the hourly sweep that marks a prayer
# from inside a session qaza once its time is over.
PRIVATE_V6 = """
BEGIN;
ALTER TABLE salah_log ADD COLUMN status_by TEXT CHECK (status_by IN ('user','auto'));
COMMIT;
"""

# --- private v7 -------------------------------------------------------------
# When the user was last asked, on coming back, whether a prayer was prayed.
PRIVATE_V7 = """
BEGIN;
ALTER TABLE salah_log ADD COLUMN asked_unix INTEGER;
COMMIT;
"""

# --- work v6 ---------------------------------------------------------------
# What the user typed over in Obsidian (vault.py), FIELD BY FIELD. A day_edit row holds only
# the fields the user overrode; every other column is NULL and means "use what was measured".
# So typing a lunch figure does not freeze that day's login and logout (afternoon work that
# is measured later still counts), and emptying a cell sets it back to NULL. A row whose
# columns are all NULL is deleted by vault.py. Nothing measured is ever deleted: the views
# below overlay the row on the measurement, COALESCE by COALESCE.
#
# day_edit_log is append-only and records every change and every refusal, so "who moved this
# number" always has an answer.
#
# `off_minutes` is time between shifts inside the login..logout window that was not work (a
# day that ran 14:00-18:00 and 21:00-02:00 has 180 of it). It is taken out of the span; the
# seven break columns are taken out of the net, as measured deductions are. `unsure` is a
# break nobody has classified: it deducts, and flags the day like an unconfirmed gap.
#
# Where nothing is overridden the views return the measured figure EXACTLY (not a
# recomputation of it), and a measured day with no deduction keeps net_minutes NULL.

WORK_V6 = """
BEGIN;
DROP VIEW IF EXISTS v_day_worked;
DROP VIEW IF EXISTS v_day_deduction;
DROP VIEW IF EXISTS v_day_span;

CREATE TABLE day_edit (
  day           TEXT PRIMARY KEY,
  login_unix    INTEGER,
  logout_unix   INTEGER,
  off_minutes   INTEGER,
  salah         INTEGER,
  lunch         INTEGER,
  dinner        INTEGER,
  washroom      INTEGER,
  misc          INTEGER,
  call_personal INTEGER,
  unsure        INTEGER,
  edited_unix   INTEGER NOT NULL,
  surface       TEXT    NOT NULL CHECK (surface IN ('day','month')),
  CHECK (login_unix IS NULL OR logout_unix IS NULL OR logout_unix > login_unix),
  CHECK ((off_minutes IS NULL OR off_minutes >= 0) AND (salah IS NULL OR salah >= 0)
         AND (lunch IS NULL OR lunch >= 0) AND (dinner IS NULL OR dinner >= 0)
         AND (washroom IS NULL OR washroom >= 0) AND (misc IS NULL OR misc >= 0)
         AND (call_personal IS NULL OR call_personal >= 0) AND (unsure IS NULL OR unsure >= 0))
);

CREATE TABLE day_edit_log (
  id          INTEGER PRIMARY KEY,
  day         TEXT    NOT NULL,
  ts_unix     INTEGER NOT NULL,
  surface     TEXT    NOT NULL,
  action      TEXT    NOT NULL CHECK (action IN ('set','clear','kind','rejected')),
  before_json TEXT,
  after_json  TEXT,
  reason      TEXT
);
CREATE INDEX ix_del_day ON day_edit_log(day, ts_unix);

-- what was measured, before any override
CREATE VIEW v_day_span_measured AS
SELECT attendance_day,
       CAST(ROUND(SUM(seconds) / 60.0) AS INTEGER) AS span_minutes,
       MIN(start_unix) AS first_unix,
       MAX(end_unix)   AS last_unix,
       GROUP_CONCAT(DISTINCT provenance) AS provenance,
       MIN(confidence) AS min_confidence
FROM v_run_interval
GROUP BY attendance_day;

-- measured break minutes by category (confirmed rows only; a meeting row is 0 minutes),
-- with `unsure` the minutes of the rows nobody has classified
CREATE VIEW v_day_break_measured AS
SELECT attendance_day,
       CAST(ROUND(SUM(minutes)) AS INTEGER) AS total_minutes,
       SUM(CASE WHEN confirmed = 0 THEN 1 ELSE 0 END) AS unconfirmed,
       SUM(CASE WHEN confirmed = 1 AND category = 'salah' THEN minutes ELSE 0 END) AS salah,
       SUM(CASE WHEN confirmed = 1 AND category = 'lunch' THEN minutes ELSE 0 END) AS lunch,
       SUM(CASE WHEN confirmed = 1 AND category = 'dinner' THEN minutes ELSE 0 END) AS dinner,
       SUM(CASE WHEN confirmed = 1 AND category = 'washroom' THEN minutes ELSE 0 END) AS washroom,
       SUM(CASE WHEN confirmed = 1 AND category = 'misc' THEN minutes ELSE 0 END) AS misc,
       SUM(CASE WHEN confirmed = 1 AND category = 'call_personal' THEN minutes ELSE 0 END) AS call_personal,
       SUM(CASE WHEN confirmed = 0 THEN minutes ELSE 0 END) AS unsure
FROM deduction
WHERE end_unix IS NOT NULL
GROUP BY attendance_day;

CREATE VIEW v_day_span AS
SELECT attendance_day,
       CASE WHEN edited = 0 THEN m_span
            ELSE CAST(ROUND((last_unix - first_unix) / 60.0 - off) AS INTEGER) END AS span_minutes,
       first_unix, last_unix,
       CASE WHEN edited = 1 THEN 'vault' ELSE m_prov END AS provenance,
       CASE WHEN edited = 1 THEN 1.0 ELSE m_conf END AS min_confidence
FROM (
  SELECT d.day AS attendance_day,
         COALESCE(e.login_unix,  m.first_unix) AS first_unix,
         COALESCE(e.logout_unix, m.last_unix)  AS last_unix,
         COALESCE(e.off_minutes,
                  CAST(ROUND((m.last_unix - m.first_unix) / 60.0) AS INTEGER) - m.span_minutes,
                  0) AS off,
         (e.login_unix IS NOT NULL OR e.logout_unix IS NOT NULL
          OR e.off_minutes IS NOT NULL) AS edited,
         m.span_minutes AS m_span, m.provenance AS m_prov, m.min_confidence AS m_conf
  FROM (SELECT attendance_day AS day FROM v_day_span_measured UNION SELECT day FROM day_edit) d
  LEFT JOIN v_day_span_measured m ON m.attendance_day = d.day
  LEFT JOIN day_edit e ON e.day = d.day
)
WHERE first_unix IS NOT NULL AND last_unix IS NOT NULL;

CREATE VIEW v_day_deduction AS
SELECT attendance_day,
       CASE WHEN edited = 0 THEN m_total
            ELSE CAST(ROUND(salah + lunch + dinner + washroom + misc + call_personal + unsure)
                      AS INTEGER) END AS deduction_minutes,
       CASE WHEN edited = 0 THEN m_unconf
            WHEN unsure > 0 THEN 1 ELSE 0 END AS unconfirmed
FROM (
  SELECT d.day AS attendance_day,
         (e.salah IS NOT NULL OR e.lunch IS NOT NULL OR e.dinner IS NOT NULL
          OR e.washroom IS NOT NULL OR e.misc IS NOT NULL OR e.call_personal IS NOT NULL
          OR e.unsure IS NOT NULL) AS edited,
         COALESCE(e.salah, m.salah, 0)               AS salah,
         COALESCE(e.lunch, m.lunch, 0)               AS lunch,
         COALESCE(e.dinner, m.dinner, 0)             AS dinner,
         COALESCE(e.washroom, m.washroom, 0)         AS washroom,
         COALESCE(e.misc, m.misc, 0)                 AS misc,
         COALESCE(e.call_personal, m.call_personal, 0) AS call_personal,
         COALESCE(e.unsure, m.unsure, 0)             AS unsure,
         m.total_minutes AS m_total, m.unconfirmed AS m_unconf
  FROM (SELECT attendance_day AS day FROM v_day_break_measured UNION SELECT day FROM day_edit) d
  LEFT JOIN v_day_break_measured m ON m.attendance_day = d.day
  LEFT JOIN day_edit e ON e.day = d.day
)
WHERE edited = 1 OR m_total IS NOT NULL;

CREATE VIEW v_day_worked AS
SELECT c.day AS attendance_day, c.kind, c.leave_type, c.pay_affecting, c.target_minutes,
       COALESCE(s.span_minutes, 0) AS span_minutes,
       s.first_unix, s.last_unix, s.provenance, s.min_confidence,
       d.deduction_minutes, d.unconfirmed,
       CASE WHEN d.deduction_minutes IS NULL THEN NULL
            ELSE COALESCE(s.span_minutes, 0) - d.deduction_minutes END AS net_minutes
FROM day_class c
LEFT JOIN v_day_span s      ON s.attendance_day = c.day
LEFT JOIN v_day_deduction d ON d.attendance_day = c.day;
COMMIT;
"""

MIGRATIONS = {"work": [(1, WORK_V1), (2, WORK_V2), (3, WORK_V3), (4, WORK_V4), (5, WORK_V5),
                       (6, WORK_V6)],
              "private": [(1, PRIVATE_V1), (2, PRIVATE_V2), (3, PRIVATE_V3), (4, PRIVATE_V4),
                          (5, PRIVATE_V5), (6, PRIVATE_V6), (7, PRIVATE_V7)]}


def live_counts(conn):
    """True once the live clock has been promoted into the headline (see WORK_V3)."""
    row = conn.execute("SELECT v FROM schema_meta WHERE k = 'live_counts'").fetchone()
    return bool(row) and row[0] == "1"


def _apply(conn, which):
    have = conn.execute("PRAGMA user_version").fetchone()[0]
    applied = []
    for version, sql in MIGRATIONS[which]:
        if version <= have:
            continue
        conn.executescript(sql)
        conn.execute(f"PRAGMA user_version = {version:d}")
        applied.append(version)
    conn.commit()
    return have, applied


def migrate():
    """Bring both databases up to date. Idempotent."""
    out = {}
    for which, opener in (("work", dbs.open_work), ("private", dbs.open_private)):
        with opener() as conn:
            out[which] = _apply(conn, which)
    return out
