"""Invariant checks over the whole timetrack installation.

This module exists because the predecessor's defining failure was SILENT SUCCESS: it
asked ActivityWatch for a bucket name that did not exist, took the 404 as an empty list,
and reported zero hours for months without ever erroring. Nothing about its output
distinguished "you did not work" from "I am broken".

So every check here is written to fail LOUDLY and to say what to do about it. A check that
cannot decide returns `warn`, never `ok` -- an unknown must never read as healthy.

Severity decides the exit code: any `fail` exits 1, warnings alone exit 0.
"""
import json
import os
import shutil
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request
from datetime import date

from . import attest, config, dbs, derive

OK, WARN, FAIL = "ok", "warn", "fail"


def _r(name, status, detail, fix=""):
    return {"check": name, "status": status, "detail": detail, "fix": fix}


def _schema(results):
    for which, path, want in (("work", config.WORK_DB, 5), ("private", config.PRIVATE_DB, 2)):
        if not path.exists():
            results.append(_r(f"db:{which}", FAIL, "database file does not exist",
                              "timetrack migrate"))
            continue
        try:
            conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            uv = conn.execute("PRAGMA user_version").fetchone()[0]
            integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
            conn.close()
        except sqlite3.Error as e:
            results.append(_r(f"db:{which}", FAIL, f"unreadable: {e}"))
            continue
        if integrity != "ok":
            results.append(_r(f"db:{which}", FAIL, f"integrity_check: {integrity}",
                              "restore from the vault snapshot"))
        elif uv != want:
            results.append(_r(f"db:{which}", FAIL, f"schema v{uv}, expected v{want}",
                              "timetrack migrate"))
        else:
            results.append(_r(f"db:{which}", OK, f"schema v{uv}, integrity ok"))


def _config(results):
    for label, path in (("payroll", config.PAYROLL_TOML), ("holidays", config.HOLIDAYS_TOML)):
        if not path.exists():
            results.append(_r(f"config:{label}", FAIL, f"{path} missing",
                              "hand-write it; it is deliberately unmanaged"))
            continue
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            # salary is in here and the repo is public; group/other readable is a leak
            results.append(_r(f"config:{label}", FAIL, f"mode {mode:04o} is group/other readable",
                              f"chmod 600 {path}"))
        else:
            results.append(_r(f"config:{label}", OK, f"present, mode {mode:04o}"))

    try:
        gross, hpd = config.gross_monthly(), config.hours_per_day()
    except SystemExit as e:
        results.append(_r("config:payroll-values", FAIL, str(e)))
        return
    if not gross or gross <= 0:
        results.append(_r("config:payroll-values", FAIL, "gross_monthly is unset or <= 0",
                          "every money figure is None without it"))
    elif not hpd or hpd <= 0:
        results.append(_r("config:payroll-values", FAIL, f"hours_per_day={hpd}"))
    else:
        results.append(_r("config:payroll-values", OK, f"{config.currency()} {gross:,.0f}/mo, {hpd}h/day"))


def _calibration(results, conn):
    """The bug this check exists for.

    calibration() corrects GIT-derived spans against measured ones. It was being applied
    to every span, including the hand-kept sheet -- inflating the user's own authoritative
    record by 18% and turning a real shortfall into an apparent surplus. A factor set
    while no git-derived rows exist has nothing to correct and can only distort.
    """
    calib = config.calibration()
    if calib == 1.0:
        results.append(_r("calibration", OK, "1.0 (uncalibrated, honest)"))
        return
    n = conn.execute(
        "SELECT COUNT(*) FROM work_session WHERE provenance LIKE '%git%'").fetchone()[0]
    if n == 0:
        # WARN not FAIL: derive now applies the factor only to git-derived spans, so with
        # no such rows it is inert. It is still unvalidated -- nothing has been measured
        # against anything -- and it would start biasing the figure the moment a git
        # backfill lands, which is precisely when nobody would be looking at this check.
        results.append(_r("calibration", WARN,
                          f"factor {calib} set but no git-derived sessions exist to justify it",
                          "inert today; it starts biasing the figure as soon as one lands"))
    else:
        results.append(_r("calibration", OK, f"{calib} over {n} git-derived session(s)"))


def _month(results, conn, month):
    rows = derive.day_rows(conn, month)
    if not rows:
        results.append(_r(f"day_class:{month}", FAIL, "month not classified",
                          f"timetrack seed --month {month}"))
        return
    results.append(_r(f"day_class:{month}", OK, f"{len(rows)} day(s) classified"))

    bad = [r["attendance_day"] for r in rows
           if r["target_minutes"] == 0 and (r["span_minutes"] or 0) > 0]
    if bad:
        # worked time on a day the calendar calls off: either the classification is wrong
        # or the work is genuinely uncompensated, and the two need different answers
        results.append(_r("classification", WARN,
                          f"{len(bad)} non-working day(s) carry activity: {', '.join(bad[:4])}",
                          "reclassify, or accept it as unpaid"))
    else:
        results.append(_r("classification", OK, "no activity on non-working days"))

    s = derive.month_summary(conn, month)
    if s["days_unconfirmed_breaks"]:
        results.append(_r("breaks:unclassified", WARN,
                          f"{s['days_unconfirmed_breaks']} day(s) carry UNCONFIRMED gaps "
                          f"({', '.join(s['unconfirmed_break_days'][:4])}); basis reads net?",
                          "classify them -- a gap that was a meeting is worked time"))
    else:
        results.append(_r("breaks:unclassified", OK, "every recorded break is confirmed"))

    # The invariant that makes an AW day defensible: its net must not exceed the presence
    # ActivityWatch actually measured. Comparing net against span - deductions would be
    # tautological -- that IS the view's arithmetic -- so this re-derives presence from the
    # live source and compares against it. If aw-server cannot be reached the check WARNS:
    # it has not passed, it simply could not be decided, and saying ok would be a lie.
    aw_days = [r["attendance_day"] for r in conn.execute(
        "SELECT DISTINCT attendance_day FROM v_day_worked"
        " WHERE attendance_day LIKE ? AND provenance LIKE '%aw%'", (month + "-%",))]
    if not aw_days:
        results.append(_r("aw:lower-bound", OK, "no AW-sourced day this month"))
    else:
        try:
            from .backfill import aw as awmod
            present = {d["day"]: round(d["present_seconds"] / 60)
                       for d in awmod.workdays(awmod.not_afk())}
        except SystemExit as e:
            results.append(_r("aw:lower-bound", WARN, f"cannot re-derive presence: {e}",
                              "undecided, not healthy"))
        else:
            over = []
            for day in aw_days:
                net = conn.execute(
                    "SELECT net_minutes FROM v_day_worked WHERE attendance_day=?",
                    (day,)).fetchone()[0]
                # Compare AW's SHARE only. Time the user recorded by hand is by definition
                # time AW could not see -- a meeting before the PC booted, a call away from
                # the desk -- so leaving it in made this check fail on exactly the days the
                # hotkey was used correctly. Hand minutes come out; the overlap deductions
                # (hand time AW ALSO saw, already subtracted once) go back in.
                hand = conn.execute(
                    "SELECT COALESCE(SUM(seconds), 0) / 60.0 FROM v_run_interval"
                    " WHERE attendance_day=? AND provenance='hotkey'", (day,)).fetchone()[0]
                overlap = conn.execute(
                    "SELECT COALESCE(SUM(minutes), 0) FROM deduction"
                    " WHERE attendance_day=? AND provenance='hotkey:overlap'", (day,)).fetchone()[0]
                p_min = present.get(day)
                if net is not None:
                    net = round(net - hand + overlap)
                if net is not None and p_min is not None and net > p_min + 1:
                    over.append(f"{day} AW-sourced net {net} > measured {p_min}")
            if over:
                results.append(_r("aw:lower-bound", FAIL, "; ".join(over),
                                  "a gap escaped deduction; the figure is inflated"))
            else:
                results.append(_r("aw:lower-bound", OK,
                                  f"{len(aw_days)} AW day(s) within measured presence"))

    if s["days_missing_breaks"]:
        results.append(_r("basis", WARN,
                          f"{s['days_missing_breaks']} working day(s) have no break recorded; "
                          "their span is counted as-is and OVERSTATES net",
                          "record the breaks before submitting"))
    else:
        results.append(_r("basis", OK, f"basis {s['basis']} across every working day"))


def _dangling(results, conn):
    # Counted from clock_event, NOT from v_run_interval: that view requires the next
    # event to be a run_stop, so it silently drops an unpaired run_start and this check
    # could never fire. It reported 0 dangling runs while one was open.
    open_runs = conn.execute(
        "SELECT COUNT(*) FROM (" + "SELECT e.id, e.session_id, e.attendance_day, e.ts_unix FROM clock_event e"
            " WHERE e.kind='run_start' AND NOT EXISTS ("
            "   SELECT 1 FROM clock_event s WHERE s.session_id = e.session_id"
            "   AND s.kind='run_stop' AND s.ts_unix >= e.ts_unix)"
            " ORDER BY e.ts_unix DESC" + ")").fetchone()[0]
    if open_runs > 1:
        results.append(_r("clock", FAIL, f"{open_runs} run intervals never closed",
                          "a crash left the clock running; reconcile before trusting totals"))
    elif open_runs == 1:
        results.append(_r("clock", OK, "1 run interval open (the clock is running)"))
    else:
        results.append(_r("clock", OK, "no dangling run intervals"))


def _unit(name):
    """is-active / is-enabled for a user unit, or None when systemd cannot be asked."""
    if not shutil.which("systemctl"):
        return None, None
    def ask(verb):
        try:
            return subprocess.run(["systemctl", "--user", verb, name], capture_output=True,
                                  text=True, timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return None
    return ask("is-active"), ask("is-enabled")


def _enforcement(results):
    """The dead-man's switch, and whether the live clock is actually alive.

    These are checked here because `timetrack doctor` is wired into the hourly capture job,
    so a failure turns the ops module amber on the bar. A blocking panel whose reaper is
    not running is the single most dangerous state this system can be in -- it is the one
    where a bug takes the keyboard away -- and it must not be discoverable only by
    experiencing it.
    """
    if config.panic():
        results.append(_r("panic", WARN, f"{config.PANIC} exists: enforcement is OFF",
                          "timetrack panic off -- collection was never affected"))
    else:
        results.append(_r("panic", OK, "not set; enforcement active"))

    active, enabled = _unit("timetrack-deadman.timer")
    panels = config.STATE_DIR / "panels"
    live = sorted(panels.glob("*.hb")) if panels.exists() else []
    if active is None:
        results.append(_r("deadman", WARN, "cannot query systemd --user"))
    elif active == "active":
        results.append(_r("deadman", OK, f"reaper armed, {len(live)} panel(s) on screen"))
    elif live:
        # the exact state the refusal in timetrack-panel exists to prevent, reached anyway
        results.append(_r("deadman", FAIL,
                          f"{len(live)} panel(s) live with NO reaper ({active})",
                          "systemctl --user start timetrack-deadman.timer, "
                          "or touch ~/.config/timetrack/PANIC"))
    elif enabled in ("enabled", "static"):
        results.append(_r("deadman", FAIL, f"timer is {active} but enabled",
                          "systemctl --user start timetrack-deadman.timer"))
    else:
        results.append(_r("deadman", OK, "not installed; nothing creates blocking panels"))

    active, enabled = _unit("timetrack-clockd.service")
    cache = config.STATE_DIR / "clock.json"
    if enabled not in ("enabled", "static"):
        results.append(_r("clockd", OK,
                          "not enabled; AW capture is the only live source"))
    elif active != "active":
        results.append(_r("clockd", FAIL, f"enabled but {active}",
                          "systemctl --user status timetrack-clockd"))
    else:
        try:
            age = time.time() - json.loads(cache.read_text())["updated_unix"]
        except (OSError, ValueError, KeyError):
            results.append(_r("clockd", FAIL, "running but has never written its cache",
                              "the loop is wedged; WatchdogSec should have restarted it"))
        else:
            if age > 120:
                results.append(_r("clockd", FAIL, f"cache is {age / 60:.0f} min stale",
                                  "the loop stopped ticking while the process lives"))
            else:
                results.append(_r("clockd", OK, f"running, cache {age:.0f}s old"))

    stuck, age = attest.pending_spool(), attest.spool_age()
    if not stuck:
        results.append(_r("attest:spool", OK, "spool empty"))
    elif age is not None and age > 2 * 3600:
        # Undrained is normal for an hour; undrained for two means the drain itself is not
        # running, and a reap or a timeout is then recorded NOWHERE while the reaper, the
        # panel and the daemon all look healthy. That is the shape of the original bug.
        results.append(_r("attest:spool", WARN,
                          f"{len(stuck)} attestation(s) undrained for {age / 3600:.0f}h",
                          "timetrack attest --drain; the capture job should do this hourly"))
    else:
        results.append(_r("attest:spool", OK,
                          f"{len(stuck)} entry(s) awaiting the next drain"))


def _attestation(results, conn, month):
    """Unsigned days. A figure nobody reviewed is a measurement, not a claim."""
    try:
        pend = attest.pending_days(conn, month)
    except sqlite3.Error as e:
        results.append(_r("attest:days", WARN, f"{e}"))
        return
    if pend:
        results.append(_r("attest:days", WARN,
                          f"{len(pend)} past working day(s) never signed off: "
                          f"{', '.join(r['day'] for r in pend[:4])}",
                          "timetrack attest --all"))
    else:
        results.append(_r("attest:days", OK, "every past working day with time is signed off"))


def _activitywatch(results):
    """Resolve buckets by TYPE, never by name.

    sources.py asked for aw-watcher-window_devsupreme on a host called desktop-snoorullah,
    got a 404, and returned []. Resolving by type is why that cannot recur.
    """
    try:
        with urllib.request.urlopen("http://localhost:5600/api/0/buckets/", timeout=3) as fh:
            buckets = __import__("json").loads(fh.read())
    except (urllib.error.URLError, OSError, ValueError) as e:
        results.append(_r("activitywatch", WARN, f"aw-server unreachable: {e}",
                          "systemctl --user status aw-server; live capture is blind without it"))
        return
    types = {b.get("type") for b in buckets.values()}
    missing = {"currentwindow", "afkstatus"} - types
    if missing:
        results.append(_r("activitywatch", FAIL,
                          f"{len(buckets)} bucket(s) but no {', '.join(sorted(missing))}",
                          "awatcher is not reporting; this is the original silent-zero bug"))
    else:
        results.append(_r("activitywatch", OK, f"{len(buckets)} bucket(s), window + afk present"))
    _web(results, types)


def _web(results, types):
    """Browser time (web.py). Attribution only, so a gap here is a warning, never a fail."""
    if "web.tab.current" not in types:
        results.append(_r("aw:web", WARN, "no browser bucket",
                          "install the ActivityWatch extension in the browser"))
        return
    try:
        conn = sqlite3.connect(f"file:{config.PRIVATE_DB}?mode=ro", uri=True)
        last = conn.execute("SELECT MAX(day) FROM web_domain_day").fetchone()[0]
        conn.close()
    except sqlite3.Error as e:
        results.append(_r("aw:web", WARN, f"web tables unreadable: {e}", "timetrack migrate"))
        return
    age = (date.today() - date.fromisoformat(last)).days if last else None
    if age is None or age > 2:
        results.append(_r("aw:web", WARN, f"browser time last ingested {last or 'never'}",
                          "timetrack web --all"))
    else:
        results.append(_r("aw:web", OK, f"browser time ingested through {last}"))


def _backup(results):
    latest = config.HOME / ".local/state/dots-ops/state/vault-backup.json"
    if not latest.exists():
        results.append(_r("backup", WARN, "vault-backup has never run",
                          "the databases that determine pay are unprotected"))
        return
    age_h = (time.time() - latest.stat().st_mtime) / 3600
    if age_h > 36:
        results.append(_r("backup", FAIL, f"last vault backup {age_h:.0f}h ago",
                          "systemctl --user start dots-ops@vault-backup"))
    else:
        results.append(_r("backup", OK, f"last vault backup {age_h:.0f}h ago"))


def run(month=None):
    month = month or date.today().strftime("%Y-%m")
    results = []
    _schema(results)
    _config(results)
    if config.WORK_DB.exists():
        try:
            conn = dbs.open_work(readonly=True)
            dbs.assert_single_database(conn)
            _calibration(results, conn)
            _month(results, conn, month)
            _dangling(results, conn)
            _attestation(results, conn, month)
            conn.close()
        except sqlite3.Error as e:
            results.append(_r("queries", FAIL, f"{e}"))
    _activitywatch(results)
    _enforcement(results)
    _backup(results)
    return results
