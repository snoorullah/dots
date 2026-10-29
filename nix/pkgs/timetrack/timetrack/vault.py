"""An Obsidian-editable timesheet: a markdown table per month and a note per day.

The database stays the single source of truth. The vault holds two VIEWS of it that the
user may type into; `sync` reads the typing back into work.db and `render` rewrites both
views from the database, so they converge whichever side moved.

  VAULT/time/Timesheet/YYYY-MM.md        one table, one row a day, up to and including today
  VAULT/time/Timesheet/days/YYYY-MM-DD.md  properties + the measured shifts + free notes

What an edit means. A day the user types hours into gets a `day_edit` row (migrate.WORK_V6):
their own statement of login, logout and breaks, which supersedes the measured figures for
that day WITHOUT deleting them. Clearing Login and Logout deletes the row and the measured
figure comes back. A change of Kind rewrites day_class (and its target) and never touches the
hours -- an edit that only moves a non-hour cell must not freeze the measured hours into an
"edit" the user never made.

Why it is built around not clobbering the user:

  * QUIET. A file modified within QUIET seconds is neither read nor written: the user may
    be mid-sentence, and a half-typed time is not an edit.
  * What was last RENDERED is remembered per file (vault-rendered.json: content hash and each
    day's canonical values). An edit is "this cell differs from what we last showed", so a
    measured figure that moved underneath the user (hourly refresh) is not mistaken for an
    edit, and an unchanged row is never a write.
  * A file that fails validation is HELD: nothing in it is applied, it is never rewritten
    (the bad cell stays visible next to the toast), and it is looked at again only when
    its content changes.
  * Render refuses to overwrite a file whose content is not what it last wrote: that is an
    edit that has not been synced yet. Sync marks a file processed before rendering.
  * Everything below `## Notes` in a day note is the user's, and survives every render.

Nothing here opens a connection: it reads and writes local files and one database.
"""
import hashlib
import json
import os
import re
import time
from datetime import date, datetime, timedelta

from . import calendar_, config, derive, notify

QUIET = 20                  # seconds a file must sit untouched before it is read or replaced
WAIT_POLL = 5               # --wait-quiet: seconds between looks
WAIT_MAX = 300              # --wait-quiet: give up waiting after this long

KINDS = ("working", "weekend", "holiday", "leave_paid", "leave_unpaid", "absent",
         "worked_unlogged")
ZERO_TARGET = ("holiday", "leave_unpaid", "weekend")    # the mapping interactive.py uses
MINUTES = ("off", "salah", "lunch", "dinner", "washroom", "misc", "call", "unsure")
HOURS = ("login", "logout") + MINUTES
FIELDS = ("kind",) + HOURS
COLUMN = {"call": "call_personal", "off": "off_minutes"}                     # field name -> day_edit column
CATEGORY = {"call_personal": "call", "salah": "salah", "lunch": "lunch", "dinner": "dinner",
            "washroom": "washroom", "misc": "misc"}

HEADER = ["Date", "Day", "Kind", "Login", "Logout", "Off", "Salah", "Lunch", "Dinner",
          "Washroom", "Misc", "Call", "Unsure", "Net", "Target", "Source"]
NOTES_RE = re.compile(r"^## Notes[ \t]*$", re.M)
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
CELL_SPLIT = re.compile(r"(?<!\\)\|")


# --- parsing and formatting ----------------------------------------------------------

def parse_clock(text):
    """'19:23', '9:05', '1923' or '03:28+1' -> (minutes into the day, extra days)."""
    m = re.fullmatch(r"\s*(\d{1,2}):?(\d{2})\s*(?:\+\s*(\d))?\s*", text or "")
    if not m or int(m[1]) > 23 or int(m[2]) > 59:
        raise ValueError(f"'{(text or '').strip()}' is not a time (use HH:MM, or HH:MM+1 for next day)")
    return int(m[1]) * 60 + int(m[2]), int(m[3] or 0)


def parse_minutes(text):
    """'', '0', '45', '45m', '0:45', '1h05', '1h' -> minutes."""
    t = (text or "").strip().lower()
    if t == "":
        return 0
    if (m := re.fullmatch(r"(\d+)(?:\s*m(?:in)?)?", t)):
        return int(m[1])
    if (m := re.fullmatch(r"(\d+):(\d{1,2})", t)) and int(m[2]) < 60:
        return int(m[1]) * 60 + int(m[2])
    if (m := re.fullmatch(r"(\d+)\s*h(?:\s*(\d{1,2})\s*m?)?", t)) and int(m[2] or 0) < 60:
        return int(m[1]) * 60 + int(m[2] or 0)
    raise ValueError(f"'{(text or '').strip()}' is not a duration (use 45, 45m, 0:45 or 1h05)")


def fmt_min(n):
    return f"{n // 60}:{n % 60:02d}"


def fmt_signed(n):
    return ("-" if n < 0 else "+") + fmt_min(abs(int(n)))


def fmt_clock(minutes):
    """Minutes since the attendance day's midnight; past 24h carries '+N'."""
    extra, rem = divmod(minutes, 1440)
    return f"{rem // 60:02d}:{rem % 60:02d}" + (f"+{extra}" if extra else "")


def _clock_of(unix, day):
    dt = datetime.fromtimestamp(unix)
    return fmt_clock((dt.date() - date.fromisoformat(day)).days * 1440 + dt.hour * 60 + dt.minute)


def _unix(day, clock):
    mins, extra = parse_clock(clock)
    d = date.fromisoformat(day) + timedelta(days=extra)
    return int(datetime(d.year, d.month, d.day, mins // 60, mins % 60).timestamp())


def canon(raw, base):
    """Parse one day's raw cell text into canonical values.

    A field the file does not carry keeps its baseline value. Logout is resolved against
    login: 'HH:MM+1' is next day, and a logout at or before the login without '+1' is
    taken to be the next day too (a night shift typed the obvious way).
    """
    out = {}
    kind = str(raw.get("kind", base["kind"])).strip().lower()
    if kind not in KINDS:
        raise ValueError(f"kind '{kind}' is not one of {', '.join(KINDS)}")
    out["kind"] = kind
    login = str(raw.get("login", base["login"])).strip()
    logout = str(raw.get("logout", base["logout"])).strip()
    lin = None
    if login:
        lin, extra = parse_clock(login)
        lin += extra * 1440
        out["login"] = fmt_clock(lin)
    else:
        out["login"] = ""
    if logout:
        lo, extra = parse_clock(logout)
        lo += extra * 1440
        if not extra and lin is not None and lo <= lin:
            lo += 1440
        out["logout"] = fmt_clock(lo)
    else:
        out["logout"] = ""
    for k in MINUTES:
        v = raw.get(k)
        out[k] = base[k] if v is None else parse_minutes(str(v))
    return out


def _minutes_of(clock):
    mins, extra = parse_clock(clock)
    return mins + extra * 1440


def hours_changed(v, b):
    return any(v[k] != b[k] for k in HOURS)


def split_row(line):
    cells = CELL_SPLIT.split(line.strip())
    if cells and cells[0].strip() == "":
        cells = cells[1:]
    if cells and cells[-1].strip() == "":
        cells = cells[:-1]
    return [c.strip() for c in cells]


def parse_sheet(text, month):
    """{day: {field: cell text}} from a month table. Computed columns are ignored, a row
    whose first cell carries no date is ignored, and columns are found by header name so a
    reordered table still reads."""
    cols = {name.lower(): i for i, name in enumerate(HEADER)}
    out = {}
    for line in text.replace("\r\n", "\n").split("\n"):
        if not line.lstrip().startswith("|"):
            continue
        cells = split_row(line)
        if not cells:
            continue
        m = DATE_RE.search(cells[0])
        if not m:
            if cells[0].lower() == "date":
                cols = {c.lower(): i for i, c in enumerate(cells)}
            continue
        day = m[1]
        if not day.startswith(month + "-"):
            continue
        raw = {}
        for f in FIELDS:
            i = cols.get(f)
            if i is not None and i < len(cells):
                raw[f] = cells[i]
        out[day] = raw
    return out


def parse_frontmatter(text):
    text = text.replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end < 0:
        return {}
    out = {}
    for line in text[4:end].split("\n"):
        m = re.fullmatch(r"\s*([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*", line)
        if not m:
            continue
        v = m[2]
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        out[m[1].lower()] = v
    return out


def parse_day_note(text, day):
    fm = parse_frontmatter(text)
    return {day: {f: fm[f] for f in FIELDS if f in fm}}


# --- reading the database ------------------------------------------------------------

def load_days(conn, month, upto=None):
    """Every day_class day of `month` (to `upto` if given), with the values the user is
    shown: the day_edit row if there is one, else what was measured."""
    pat = month + "-%"
    edits = {r["day"]: r for r in conn.execute("SELECT * FROM day_edit WHERE day LIKE ?", (pat,))}
    brk, unsure = {}, {}
    for r in conn.execute(
            "SELECT attendance_day, category, minutes, confirmed FROM deduction"
            " WHERE attendance_day LIKE ? AND end_unix IS NOT NULL", (pat,)):
        if r["confirmed"]:
            d = brk.setdefault(r["attendance_day"], {})
            f = CATEGORY.get(r["category"])
            if f:
                d[f] = d.get(f, 0) + (r["minutes"] or 0)
        else:
            unsure[r["attendance_day"]] = unsure.get(r["attendance_day"], 0) + (r["minutes"] or 0)
    recs = []
    for r in conn.execute("SELECT * FROM v_day_worked WHERE attendance_day LIKE ?"
                          " ORDER BY attendance_day", (pat,)):
        day = r["attendance_day"]
        if upto is not None and date.fromisoformat(day) > upto:
            continue
        v = {"kind": r["kind"], "login": "", "logout": "", **{k: 0 for k in MINUTES}}
        e = edits.get(day)
        if e:
            for k in MINUTES:
                v[k] = e[COLUMN.get(k, k)]
        else:
            for k, n in brk.get(day, {}).items():
                v[k] = int(round(n))
            v["unsure"] = int(round(unsure.get(day, 0)))
            if r["first_unix"] and r["last_unix"]:
                v["off"] = max(0, round((r["last_unix"] - r["first_unix"]) / 60)
                               - (r["span_minutes"] or 0))
        if r["first_unix"] and r["last_unix"]:
            v["login"] = _clock_of(r["first_unix"], day)
            v["logout"] = _clock_of(r["last_unix"], day)
        net = r["net_minutes"]
        if net is None and (r["span_minutes"] or 0) > 0:
            net = derive.basis(r)[0]
        recs.append({"day": day, "v": v, "row": r, "has_edit": e is not None, "net": net,
                     "source": "edited" if r["provenance"] == "vault" else (r["provenance"] or "")})
    return recs


def _rec(conn, day):
    for r in load_days(conn, day[:7]):
        if r["day"] == day:
            return r
    return None


# --- rendering -----------------------------------------------------------------------

def _cell(v, k):
    n = v[k]
    if n == 0 and not (v["login"] and v["logout"]):
        return ""
    return fmt_min(n)


def _row_cells(rec):
    v = rec["v"]
    r = rec["row"]
    d = date.fromisoformat(rec["day"])
    return [f"[[days/{rec['day']}\\|{rec['day']}]]", d.strftime("%a"), v["kind"], v["login"],
            v["logout"]] + [_cell(v, k) for k in MINUTES] + [
        "" if rec["net"] is None else fmt_min(rec["net"]),
        fmt_min(r["target_minutes"]) if r["target_minutes"] else "", rec["source"]]


def month_text(conn, month, recs, today):
    y, m = (int(x) for x in month.split("-"))
    s = derive.month_summary(conn, month, today=today)
    lines = [
        "---", f"month: {month}", "---",
        f"# Timesheet · {date(y, m, 1):%B %Y}", "",
        "Edit Kind, Login, Logout and the break cells. Net, Target and Source recompute within ~30 s.",
        "Clear Login and Logout to go back to the measured figure. A submitted month is read-only.",
        "",
        "| " + " | ".join(HEADER) + " |",
        "|" + "---|" * len(HEADER),
    ]
    for rec in recs:
        lines.append("| " + " | ".join(_row_cells(rec)) + " |")
    lines += ["", f"**Worked** {fmt_min(s['worked_minutes'])} · **Target** "
                  f"{fmt_min(s['target_minutes'])} · **Delta** "
                  f"{fmt_signed(s['worked_minutes'] - s['target_minutes'])}", ""]
    return "\n".join(lines)


def _day_head(conn, rec, month):
    day, v, r = rec["day"], rec["v"], rec["row"]
    d = date.fromisoformat(day)
    fm = ["---", f'date: "{day}"', f'kind: "{v["kind"]}"', f'login: "{v["login"]}"',
          f'logout: "{v["logout"]}"']
    for k in MINUTES:
        fm.append(f'{k}: "{_cell(v, k)}"')
    fm.append("---")
    shifts = [f"- {derive.clock(x['start_unix'])} to {derive.clock(x['end_unix'])}"
              f" ({fmt_min(round(x['seconds'] / 60))})"
              for x in conn.execute(
                  "SELECT start_unix, end_unix, seconds FROM v_run_interval"
                  " WHERE attendance_day = ? ORDER BY start_unix", (day,))] or ["- none measured"]
    breaks = [f"- {derive.clock(x['start_unix'])} to {derive.clock(x['end_unix'])}  {x['category']}"
              f" {fmt_min(round(x['minutes'] or 0))}" + ("" if x["confirmed"] else "  (unconfirmed)")
              for x in conn.execute(
                  "SELECT start_unix, end_unix, category, minutes, confirmed FROM deduction"
                  " WHERE attendance_day = ? AND end_unix IS NOT NULL ORDER BY start_unix", (day,))
              ] or ["- none recorded"]
    out = fm + [
        f"# {d:%a} {d.day} {d:%b %Y}", "",
        "| Net | Target | Source |", "|---|---|---|",
        f"| {'' if rec['net'] is None else fmt_min(rec['net'])} | "
        f"{fmt_min(r['target_minutes']) if r['target_minutes'] else ''} | {rec['source']} |", "",
        "Measured shifts" + (" (replaced by your edit)" if rec["has_edit"] else "") + ":",
        *shifts, "", "Measured breaks:", *breaks, "",
        f"[[time/Timesheet/{month}|Back to the {month} sheet]]", "",
        "Edit the properties above; Net, Target and Source recompute within ~30 s.",
        "Clear Login and Logout to go back to the measured figure. Write below as you like.", "",
        "## Notes"]
    return "\n".join(out)


def day_text(conn, rec, month, existing):
    """The note with the user's text below `## Notes` carried over verbatim."""
    tail = "\n"
    if existing is not None and (m := NOTES_RE.search(existing)):
        tail = existing[m.end():]
    return _day_head(conn, rec, month) + tail


# --- state ---------------------------------------------------------------------------

def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def load_state():
    try:
        st = json.loads(config.VAULT_STATE.read_text())
    except (OSError, ValueError):
        st = {}
    st.setdefault("files", {})
    st.setdefault("held", {})
    return st


def _atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(data) if isinstance(data, str) else tmp.write_bytes(data)
    os.replace(tmp, path)


def save_state(st):
    _atomic(config.VAULT_STATE, json.dumps(st, indent=1, sort_keys=True) + "\n")


def _norm(text):
    """Whitespace Obsidian adds when it tidies a table or rewrites a property is not a
    change, so a file that differs from ours only that way is left alone."""
    out = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.lstrip().startswith("|"):
            cells = [("---" if re.fullmatch(r":?-+:?", c) else c) for c in split_row(line)]
            out.append("|" + "|".join(cells) + "|")
        else:
            out.append(re.sub(r'^([A-Za-z_][\w-]*):\s*"(.*)"\s*$', r"\1: \2", line.rstrip()))
    return "\n".join(out)


def _put(path, text, days, now, st, report):
    """Write `text` if it differs, unless the user may be in it. Records what was shown."""
    key = str(path)
    rec = {"hash": None, "days": days}
    if path.exists():
        cur = path.read_bytes()
        if cur == text.encode() or _norm(cur.decode(errors="replace")) == _norm(text):
            st["files"][key] = {"hash": sha(cur), "days": days}
            return
        if now - path.stat().st_mtime < QUIET:
            report["skipped"][key] = "quiet"
            return
        if st["held"].get(key) == sha(cur):
            report["skipped"][key] = "held"
            return
        if st["files"].get(key, {}).get("hash") != sha(cur):
            report["skipped"][key] = "unsynced"      # an edit sync has not read yet
            return
    _atomic(path, text)
    rec["hash"] = sha(text)
    st["files"][key] = rec
    st["held"].pop(key, None)
    report["written"].append(key)


def _render(conn, month, now, st, report):
    today = date.fromtimestamp(now)
    recs = load_days(conn, month, upto=today)
    if not recs or not config.VAULT.is_dir():
        return                  # nothing to show, or no vault on this machine to put it in
    sheet = config.TIMESHEET / f"{month}.md"
    _put(sheet, month_text(conn, month, recs, today), {r["day"]: r["v"] for r in recs},
         now, st, report)
    for rec in recs:
        path = config.TIMESHEET_DAYS / f"{rec['day']}.md"
        existing = path.read_text(errors="replace") if path.exists() else None
        _put(path, day_text(conn, rec, month, existing), {rec["day"]: rec["v"]}, now, st, report)


def render(conn, month, now=None):
    """Rewrite one month's sheet and day notes from the database. Returns what was
    written and what was skipped (and why)."""
    now = time.time() if now is None else now
    st, report = load_state(), {"written": [], "skipped": {}}
    _render(conn, month, now, st, report)
    save_state(st)
    return report


# --- sync ----------------------------------------------------------------------------

def vault_files():
    out = sorted(config.TIMESHEET.glob("????-??.md")) if config.TIMESHEET.is_dir() else []
    if config.TIMESHEET_DAYS.is_dir():
        out += sorted(config.TIMESHEET_DAYS.glob("????-??-??.md"))
    return out


def _log(conn, day, now, surface, action, before=None, after=None, reason=None):
    conn.execute(
        "INSERT INTO day_edit_log(day, ts_unix, surface, action, before_json, after_json, reason)"
        " VALUES (?,?,?,?,?,?,?)",
        (day, int(now), surface, action,
         None if before is None else json.dumps(before, sort_keys=True),
         None if after is None else json.dumps(after, sort_keys=True), reason))


def _reject(conn, now, surface, day, before, after, reason):
    _log(conn, day, now, surface, "rejected", before, after, reason)
    notify.toast("timetrack", "Timesheet edit not saved", f"{day}: {reason}")


def _check(v, b):
    """Raise ValueError if the hours in `v` cannot be a day."""
    if not hours_changed(v, b):
        return "none"
    has_in, has_out = bool(v["login"]), bool(v["logout"])
    if has_in != has_out:
        raise ValueError("fill both Login and Logout (or clear both to use the measured figure)")
    if not has_in:
        if not (b["login"] or b["logout"]):
            raise ValueError("fill Login and Logout to record hours for this day")
        return "clear"
    span = _minutes_of(v["logout"]) - _minutes_of(v["login"])
    used = sum(v[k] for k in MINUTES)
    if used > span:
        raise ValueError(f"breaks and off add up to {fmt_min(used)}, more than the "
                         f"{fmt_min(span)} between login and logout")
    return "set"


def _set(conn, day, v, cur, surface, now):
    login_u, logout_u = None, None
    row = cur["row"]
    if row["first_unix"] and _clock_of(row["first_unix"], day) == v["login"]:
        login_u = row["first_unix"]              # keep the measured seconds when untouched
    if row["last_unix"] and _clock_of(row["last_unix"], day) == v["logout"]:
        logout_u = row["last_unix"]
    login_u = login_u or _unix(day, v["login"])
    logout_u = logout_u or _unix(day, v["logout"])
    cols = {COLUMN.get(k, k): v[k] for k in MINUTES}
    names = ["day", "login_unix", "logout_unix", "edited_unix", "surface"] + list(cols)
    conn.execute(
        f"INSERT OR REPLACE INTO day_edit({', '.join(names)})"
        f" VALUES ({', '.join('?' * len(names))})",
        [day, login_u, logout_u, int(now), surface] + list(cols.values()))


def _target(kind):
    return 0 if kind in ZERO_TARGET else config.hours_per_day() * 60


def _submitted(conn, month):
    return conn.execute("SELECT 1 FROM monthly_submission WHERE month = ?", (month,)).fetchone()


def sync(conn, now=None):
    """Read the user's edits back into work.db, then re-render. Returns a small report."""
    now = time.time() if now is None else now
    today = date.fromtimestamp(now)
    st = load_state()
    report = {"applied": 0, "rejected": 0, "held": 0, "files": 0, "written": [], "skipped": {}}
    cache = {}

    def baseline(day):
        mo = cache.get(day[:7])
        if mo is None:
            mo = cache[day[:7]] = {r["day"]: r["v"] for r in load_days(conn, day[:7])}
        return mo.get(day)

    changed = []
    for path in vault_files():
        key, data = str(path), path.read_bytes()
        h = sha(data)
        if now - path.stat().st_mtime < QUIET or st["held"].get(key) == h:
            continue
        if st["files"].get(key, {}).get("hash") == h:
            st["held"].pop(key, None)        # put back exactly as rendered: the mistake is gone
            continue
        changed.append((path, h, data))

    months = {date.fromtimestamp(now).strftime("%Y-%m")}
    winners = {}                     # day -> (mtime, surface, v, b, key)
    for path, h, data in changed:
        key, surface = str(path), ("month" if path.parent == config.TIMESHEET else "day")
        text = data.decode(errors="replace")
        report["files"] += 1
        parsed = (parse_sheet(text, path.stem) if surface == "month"
                  else parse_day_note(text, path.stem))
        edits, bad = [], None
        for day, raw in parsed.items():
            b = st["files"].get(key, {}).get("days", {}).get(day) or baseline(day)
            if b is None:
                continue                                   # a day class has not seeded
            try:
                v = canon(raw, b)
            except ValueError as e:
                bad = (day, b, raw, str(e))
                break
            if v != b:
                edits.append((day, v, b))
        if not bad:
            keep = []
            for day, v, b in edits:
                if _submitted(conn, day[:7]):
                    _reject(conn, now, surface, day, b, v, "submitted")
                    report["rejected"] += 1
                    months.add(day[:7])
                    continue
                if date.fromisoformat(day) > today and hours_changed(v, b):
                    _reject(conn, now, surface, day, b, v,
                            "future day: only Kind can change before the day has happened")
                    report["rejected"] += 1
                    v = {**v, **{k: b[k] for k in HOURS}}   # keep a Kind edit, drop the hours
                    if v == b:
                        continue
                try:
                    _check(v, b)
                except ValueError as e:
                    bad = (day, b, v, str(e))
                    break
                keep.append((day, v, b))
            edits = keep
        if bad:
            day, b, v, reason = bad
            st["held"][key] = h
            _reject(conn, now, surface, day, b, v, reason)
            report["rejected"] += 1
            report["held"] += 1
            continue
        mtime = path.stat().st_mtime
        for day, v, b in edits:
            old = winners.get(day)
            if old is None or mtime > old[0]:
                winners[day] = (mtime, surface, v, b)
        # processed: whatever the file says now is what render may replace
        st["held"].pop(key, None)
        st["files"][key] = {"hash": h, "days": {**st["files"].get(key, {}).get("days", {}),
                                                **{d: v for d, v, _ in edits}}}

    for day, (_, surface, v, b) in sorted(winners.items()):
        cur = _rec(conn, day)
        if cur is None:
            continue
        before = cur["v"]
        months.add(day[:7])
        if v["kind"] != b["kind"]:
            conn.execute("UPDATE day_class SET kind = ?, target_minutes = ? WHERE day = ?",
                         (v["kind"], _target(v["kind"]), day))
            _log(conn, day, now, surface, "kind", {"kind": before["kind"]}, {"kind": v["kind"]})
            report["applied"] += 1
        if hours_changed(v, b):
            act = _check(v, b)
            if act == "set":
                _set(conn, day, v, cur, surface, now)
                _log(conn, day, now, surface, "set", before, v)
                report["applied"] += 1
            elif act == "clear" and cur["has_edit"]:
                conn.execute("DELETE FROM day_edit WHERE day = ?", (day,))
                _log(conn, day, now, surface, "clear", before, _rec(conn, day)["v"])
                report["applied"] += 1
    conn.commit()

    for month in sorted(months):
        _render(conn, month, now, st, report)
    save_state(st)
    return report


def wait_quiet(now=time.time, sleep=time.sleep):
    """Block until no timesheet file has been touched for QUIET seconds (at most WAIT_MAX)."""
    waited = 0
    while waited < WAIT_MAX:
        newest = max((p.stat().st_mtime for p in vault_files()), default=0)
        if now() - newest >= QUIET:
            return True
        sleep(WAIT_POLL)
        waited += WAIT_POLL
    return False


# --- CLI -----------------------------------------------------------------------------

def _locked():
    """One render/sync at a time: the path unit and the hourly job can both fire."""
    import fcntl
    config.STATE_DIR.mkdir(parents=True, exist_ok=True)
    fh = open(config.STATE_DIR / "vault.lock", "w")
    fcntl.flock(fh, fcntl.LOCK_EX)
    return fh


def _month(m):
    return m or date.today().strftime("%Y-%m")


def cmd_render(a):
    from . import dbs
    with _locked(), dbs.open_work() as conn:
        rep = render(conn, _month(a.month))
    print(f"wrote {len(rep['written'])} file(s); skipped {len(rep['skipped'])}")
    for p, why in sorted(rep["skipped"].items()):
        print(f"  {why}: {p}")
    return 0


def cmd_sync(a):
    from . import dbs
    with _locked():
        if a.wait_quiet:
            wait_quiet()
        with dbs.open_work() as conn:
            rep = sync(conn)
    print(f"{rep['applied']} edit(s) applied, {rep['rejected']} rejected, "
          f"{len(rep['written'])} file(s) written")
    return 0


def cmd_log(a):
    from . import dbs
    with dbs.open_work(readonly=True) as conn:
        q, args = "SELECT * FROM day_edit_log", []
        if a.month:
            q += " WHERE day LIKE ?"
            args.append(a.month + "-%")
        for r in conn.execute(q + " ORDER BY id", args):
            ts = datetime.fromtimestamp(r["ts_unix"]).strftime("%Y-%m-%d %H:%M")
            line = f"{ts}  {r['day']}  {r['surface']:5} {r['action']:8}"
            if r["reason"]:
                line += f" {r['reason']}"
            print(line)
            if r["action"] in ("set", "clear", "kind"):
                print(f"    {r['before_json']} -> {r['after_json']}")
    return 0


def add_parser(sub):
    v = sub.add_parser("vault", help="the Obsidian-editable timesheet (month table + day notes)")
    vs = v.add_subparsers(dest="vault_cmd", required=True)

    s = vs.add_parser("render", help="rewrite the sheet and day notes from the database")
    s.add_argument("--month", metavar="YYYY-MM", help="default this month")
    s.set_defaults(fn=cmd_render)

    s = vs.add_parser("sync", help="read edits back into work.db, then re-render")
    s.add_argument("--wait-quiet", action="store_true",
                   help="first wait (up to 5 min) until nothing has been typed for 20 s")
    s.set_defaults(fn=cmd_sync)

    s = vs.add_parser("log", help="print the edit log")
    s.add_argument("--month", metavar="YYYY-MM")
    s.set_defaults(fn=cmd_log)
