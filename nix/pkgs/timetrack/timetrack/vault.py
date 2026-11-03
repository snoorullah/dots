"""An Obsidian-editable timesheet: a markdown table per month and a note per day.

The database stays the single source of truth. The vault holds two VIEWS of it that the
user may type into; `sync` reads the typing back into work.db and `render` rewrites both
views from the database, so they converge whichever side moved.

  VAULT/time/Timesheet/YYYY-MM.md        one table, one row a day, up to and including today
  VAULT/time/Timesheet/days/YYYY-MM-DD.md  properties + the measured shifts + free notes

What an edit means. Every editable cell is an OVERRIDE of the measured value, one field at
a time (migrate.WORK_V6): a day_edit row holds only the fields the user typed, and every
other field stays measured, so typing a lunch figure does not freeze the day's logout. A
cell the user empties goes back to the measured value, and a row with nothing left in it is
deleted. A change of Kind rewrites day_class (and its target). Overrides are marked in the
files (`*` in the table, an `edited:` property in the note) and that mark is ignored on read.

Why it is built around not clobbering the user:

  * QUIET. A file modified within QUIET seconds is neither read nor written: the user may
    be mid-sentence, and a half-typed time is not an edit.
  * What was last RENDERED is remembered per file (vault-rendered.json: content hash, the
    cells shown, the generated text). An edit is "this cell differs from what THIS FILE last
    showed", so a measured figure that moved underneath the user (hourly refresh) is not
    mistaken for an edit. A file with no such record has no edits: it is re-rendered, never
    diffed against the database.
  * A file that fails validation is HELD: nothing in it is applied, it is never rewritten
    (the bad cell stays visible next to the toast), and it is looked at again only when
    its content changes.
  * Render refuses to overwrite a file whose content is not what it last wrote (an edit not
    synced yet), a file whose `## Notes` heading is gone, or one with text above the heading
    that the generator did not write. Those are held, and the user's text is never lost.
  * Everything below `## Notes` is the user's, and survives every render.

Nothing here opens a connection: it reads and writes local files and one database.
"""
import hashlib
import json
import os
import re
import time
from datetime import date, datetime, timedelta

from . import breaklabel, calendar_, config, derive, notify

QUIET = 20                  # seconds a file must sit untouched before it is read or replaced
WAIT_POLL = 5               # --wait-quiet: seconds between looks
WAIT_MAX = 300              # --wait-quiet: give up waiting after this long

KINDS = ("working", "weekend", "holiday", "leave_paid", "leave_unpaid", "absent",
         "worked_unlogged")
ZERO_TARGET = ("holiday", "leave_unpaid", "weekend")    # the mapping interactive.py uses
MINUTES = ("off", "salah", "lunch", "dinner", "washroom", "misc", "call", "unsure")
HOURS = ("login", "logout") + MINUTES
FIELDS = ("kind",) + HOURS

HEADER = ["Date", "Day", "Kind", "Login", "Logout", "Off", "Salah", "Lunch", "Dinner",
          "Washroom", "Misc", "Call", "Unsure", "Net", "Target", "Source"]
MARKER = "## Notes"
NOTES_RE = re.compile(r"^## Notes[ \t]*$", re.M)
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
CELL_SPLIT = re.compile(r"(?<!\\)\|")


# --- parsing and formatting ----------------------------------------------------------

def parse_clock(text):
    """'19:23', '9:05', '1923', '03:28+1' or '23:30-1' -> (minutes into the day, day offset,
    whether the offset was written)."""
    m = re.fullmatch(r"\s*(\d{1,2}):?(\d{2})\s*(?:([+-])\s*(\d))?\s*", text or "")
    if not m or int(m[1]) > 23 or int(m[2]) > 59:
        raise ValueError(f"'{(text or '').strip()}' is not a time (use HH:MM, or HH:MM+1 for next day)")
    extra = int(m[4] or 0) * (-1 if m[3] == "-" else 1)
    return int(m[1]) * 60 + int(m[2]), extra, m[3] is not None


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


def rmin(seconds):
    """Whole minutes, halves up: what SQLite's ROUND does in the views, so Python and the views
    can never disagree on a day's off time or span."""
    return int(seconds / 60 + 0.5)


def fmt_min(n):
    return f"{n // 60}:{n % 60:02d}"


def fmt_signed(n):
    return ("-" if n < 0 else "+") + fmt_min(abs(int(n)))


def fmt_clock(minutes):
    """Minutes since the attendance day's midnight; another day carries '+N' or '-N'."""
    extra, rem = divmod(minutes, 1440)
    suffix = f"+{extra}" if extra > 0 else f"-{-extra}" if extra < 0 else ""
    return f"{rem // 60:02d}:{rem % 60:02d}" + suffix


def _clock_of(unix, day):
    dt = datetime.fromtimestamp(unix)
    return fmt_clock((dt.date() - date.fromisoformat(day)).days * 1440 + dt.hour * 60 + dt.minute)


def _minutes_of(clock):
    mins, extra, _ = parse_clock(clock)
    return mins + extra * 1440


def _unix(day, clock):
    mins, extra, _ = parse_clock(clock)
    d = date.fromisoformat(day) + timedelta(days=extra)
    return int(datetime(d.year, d.month, d.day, mins // 60, mins % 60).timestamp())


def _clean(text):
    """A cell as the user left it: the '*' that marks an override is not part of the value."""
    return str(text).strip().rstrip("*").strip()


def canon(raw, base):
    """Parse one day's raw cell text into canonical values, as the cells show them.

    login/logout are 'HH:MM[+N]' or None; minutes are ints or None; None is an EMPTY cell,
    which on read means "go back to the measured value". A field the file does not carry
    keeps its baseline value. Logout is resolved against login: a logout at or before the
    login without an explicit '+1' is taken to be the next day (a night shift typed the
    obvious way).
    """
    out = {}
    kind = _clean(raw.get("kind", base["kind"])).lower()
    if kind not in KINDS:
        raise ValueError(f"kind '{kind}' is not one of {', '.join(KINDS)}")
    out["kind"] = kind
    lin = None
    if "login" in raw:
        s = _clean(raw["login"])
        if s:
            lin = parse_clock(s)
            lin = lin[0] + lin[1] * 1440
        out["login"] = fmt_clock(lin) if s else None
    else:
        out["login"] = base["login"]
        lin = _minutes_of(base["login"]) if base["login"] else None
    if "logout" in raw:
        s = _clean(raw["logout"])
        if s:
            lo, extra, explicit = parse_clock(s)
            lo += extra * 1440
            if not explicit and lin is not None and lo <= lin:
                lo += 1440
            out["logout"] = fmt_clock(lo)
        else:
            out["logout"] = None
    else:
        out["logout"] = base["logout"]
    for k in MINUTES:
        if k in raw:
            s = _clean(raw[k])
            out[k] = parse_minutes(s) if s else None
        else:
            out[k] = base[k]
    return out


def split_row(line):
    cells = CELL_SPLIT.split(line.strip())
    if cells and cells[0].strip() == "":
        cells = cells[1:]
    if cells and cells[-1].strip() == "":
        cells = cells[:-1]
    return [c.strip() for c in cells]


def above_notes(text):
    """The part of a file the generator owns: everything before the `## Notes` heading."""
    m = NOTES_RE.search(text)
    return text[:m.start()] if m else text


def parse_sheet(text, month):
    """{day: {field: cell text}} from a month table. Computed columns are ignored, a row
    whose first cell carries no date is ignored, and columns are found by header name so a
    reordered table still reads. Only the part above `## Notes` is read: a table the user
    keeps in their notes is theirs."""
    cols = {name.lower(): i for i, name in enumerate(HEADER)}
    out = {}
    for line in above_notes(text).replace("\r\n", "\n").split("\n"):
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
    lines, _ = _split_front(text)
    out = {}
    for line in lines or []:
        m = re.fullmatch(r"\s*([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*", line)
        if not m:
            continue                    # list items, comments, anything we do not own
        v = m[2]
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        out[m[1].lower()] = v
    return out


def parse_day_note(text, day):
    fm = parse_frontmatter(text)
    return {day: {f: fm[f] for f in FIELDS if f in fm}}


# --- reading the database ------------------------------------------------------------

OVERRIDE = {"login": "login_unix", "logout": "logout_unix", "off": "off_minutes",
            "call": "call_personal"}


def load_days(conn, month, upto=None):
    """Every day_class day of `month` (to `upto` if given), as the user is shown it.

    rec["meas"]  what was measured (login/logout as unix, minutes as ints)
    rec["ov"]    the fields the user has overridden (a day_edit row's non-NULL columns)
    rec["v"]     the cells: login/logout 'HH:MM[+N]' or None, minutes int or None. A zero
                 on a day with no hours is None (an empty cell); an override is always shown
    """
    pat = month + "-%"
    edits = {r["day"]: r for r in conn.execute("SELECT * FROM day_edit WHERE day LIKE ?", (pat,))}
    span = {r["attendance_day"]: r for r in conn.execute(
        "SELECT * FROM v_day_span_measured WHERE attendance_day LIKE ?", (pat,))}
    brk = {r["attendance_day"]: r for r in conn.execute(
        "SELECT * FROM v_day_break_measured WHERE attendance_day LIKE ?", (pat,))}
    recs = []
    for r in conn.execute("SELECT * FROM v_day_worked WHERE attendance_day LIKE ?"
                          " ORDER BY attendance_day", (pat,)):
        day = r["attendance_day"]
        if upto is not None and date.fromisoformat(day) > upto:
            continue
        s, b, e = span.get(day), brk.get(day), edits.get(day)
        meas = {"login": s["first_unix"] if s else None, "logout": s["last_unix"] if s else None,
                "off": 0, **{k: 0 for k in MINUTES if k != "off"}}
        if s:
            meas["off"] = max(0, rmin(s["last_unix"] - s["first_unix"]) - s["span_minutes"])
        if b:
            for k in MINUTES:
                if k != "off":
                    meas[k] = int(round(b[OVERRIDE.get(k, k)] or 0))
        ov = {}
        if e:
            for k in HOURS:
                if e[OVERRIDE.get(k, k)] is not None:
                    ov[k] = e[OVERRIDE.get(k, k)]
        eff = {**meas, **ov}
        hours = eff["login"] is not None and eff["logout"] is not None
        v = {"kind": r["kind"],
             "login": _clock_of(eff["login"], day) if eff["login"] else None,
             "logout": _clock_of(eff["logout"], day) if eff["logout"] else None}
        for k in MINUTES:
            v[k] = eff[k] if (k in ov or eff[k] or hours) else None
        net = r["net_minutes"]
        if net is None and (r["span_minutes"] or 0) > 0:
            net = derive.basis(r)[0]
        recs.append({"day": day, "v": v, "row": r, "meas": meas, "ov": ov, "net": net,
                     "has_edit": bool(ov),
                     "source": "edited" if r["provenance"] == "vault" else (r["provenance"] or "")})
    return recs


def _rec(conn, day):
    for r in load_days(conn, day[:7]):
        if r["day"] == day:
            return r
    return None


# --- rendering -----------------------------------------------------------------------

def _cell(rec, k, mark=True):
    n = rec["v"][k]
    if n is None:
        return ""
    s = n if k in ("login", "logout") else fmt_min(n)
    return s + ("*" if mark and k in rec["ov"] else "")


def _row_cells(rec):
    v = rec["v"]
    r = rec["row"]
    d = date.fromisoformat(rec["day"])
    return [f"[[days/{rec['day']}\\|{rec['day']}]]", d.strftime("%a"), v["kind"]] + [
        _cell(rec, k) for k in HOURS] + [
        "" if rec["net"] is None else fmt_min(rec["net"]),
        fmt_min(r["target_minutes"]) if r["target_minutes"] else "", rec["source"]]


def month_head(conn, month, recs, today):
    y, m = (int(x) for x in month.split("-"))
    s = derive.month_summary(conn, month, today=today)
    lines = [
        "---", f"month: {month}", "---",
        f"# Timesheet · {date(y, m, 1):%B %Y}", "",
        "Edit Kind, Login, Logout and the break cells; a * marks a value you set. Net, Target and Source",
        "recompute within ~30 s. Empty a cell to go back to the measured value. A submitted month is read-only.",
        "",
        "| " + " | ".join(HEADER) + " |",
        "|" + "---|" * len(HEADER),
    ]
    for rec in recs:
        lines.append("| " + " | ".join(_row_cells(rec)) + " |")
    lines += ["", f"**Worked** {fmt_min(s['worked_minutes'])} · **Target** "
                  f"{fmt_min(s['target_minutes'])} · **Delta** "
                  f"{fmt_signed(s['worked_minutes'] - s['target_minutes'])}", "", ""]
    return "\n".join(lines)


def day_head(conn, rec, month):
    day, v, r = rec["day"], rec["v"], rec["row"]
    d = date.fromisoformat(day)
    fm = ["---", f'date: "{day}"', f'kind: "{v["kind"]}"']
    fm += [f'{k}: "{_cell(rec, k, mark=False)}"' for k in HOURS]
    fm += [f'edited: "{", ".join(k for k in HOURS if k in rec["ov"])}"', "---"]
    shifts = [f"- {derive.clock(x['start_unix'])} to {derive.clock(x['end_unix'])}"
              f" ({fmt_min(round(x['seconds'] / 60))})"
              for x in conn.execute(
                  "SELECT start_unix, end_unix, seconds FROM v_run_interval"
                  " WHERE attendance_day = ? ORDER BY start_unix", (day,))] or ["- none measured"]
    names = breaklabel.for_day(day)
    breaks = [f"- {derive.clock(x['start_unix'])} to {derive.clock(x['end_unix'])}  "
              + (f"{names[x['start_unix']]} ({x['category']})" if x["confirmed"] and x["start_unix"] in names
                 else x["category"])
              + f" {fmt_min(round(x['minutes'] or 0))}" + ("" if x["confirmed"] else "  (unconfirmed)")
              for x in conn.execute(
                  "SELECT start_unix, end_unix, category, minutes, confirmed FROM deduction"
                  " WHERE attendance_day = ? AND end_unix IS NOT NULL ORDER BY start_unix", (day,))
              ] or ["- none recorded"]
    out = fm + [
        f"# {d:%a} {d.day} {d:%b %Y}", "",
        "| Net | Target | Source |", "|---|---|---|",
        f"| {'' if rec['net'] is None else fmt_min(rec['net'])} | "
        f"{fmt_min(r['target_minutes']) if r['target_minutes'] else ''} | {rec['source']} |", "",
        "Measured shifts" + (" (some replaced by your edit)" if rec["has_edit"] else "") + ":",
        *shifts, "", "Measured breaks:", *breaks, "",
        f"[[time/Timesheet/{month}|Back to the {month} sheet]]", "",
        "Edit the properties above; Net, Target and Source recompute within ~30 s.",
        "Empty a property to go back to the measured value. Write below as you like.", "", ""]
    return "\n".join(out)


# --- state ---------------------------------------------------------------------------

def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def load_state():
    """The record of what was last rendered. A missing file is a fresh start; a corrupt one
    is kept aside as .corrupt and reported once, because without it nothing can be told
    apart from an edit (sync treats a file with no baseline as having none)."""
    try:
        raw = config.VAULT_STATE.read_text()
    except OSError:
        raw = None
    st = {}
    if raw is None and vault_files():
        # files exist but the record of what they showed does not: nothing in them can be read
        notify.toast("timetrack", "Timesheet state was reset",
                     "Timesheet state was reset; edits made since the last sync were not read")
    if raw is not None:
        try:
            st = json.loads(raw)
            if not isinstance(st, dict):
                raise ValueError("not an object")
        except ValueError:
            st = {}
            try:
                config.VAULT_STATE.replace(config.VAULT_STATE.with_name(
                    config.VAULT_STATE.name + ".corrupt"))
            except OSError:
                pass
            notify.toast("timetrack", "Timesheet state was reset",
                         "Timesheet state was reset; edits made since the last sync were not read")
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


def _split_front(text):
    """(frontmatter lines without the fences, the rest) -- or (None, text) if there is none."""
    t = text.replace("\r\n", "\n")
    m = re.match(r"---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)", t, re.S)
    if not m:
        return None, t
    return m[1].split("\n"), t[m.end():]


def _body(text):
    return _split_front(text)[1]


def _blocks(lines):
    """Property blocks: a `key:` line plus the indented / list lines that continue it."""
    out = []
    for line in lines:
        m = re.match(r"([A-Za-z_][\w-]*)\s*:", line)
        if m or not out:
            out.append([m[1].lower() if m else "", [line]])
        else:
            out[-1][1].append(line)
    return out


def _keep_properties(head, existing):
    """`head` with the properties the user added to the existing note (tags, aliases ...)
    carried over: they are theirs, and Obsidian may also have rewritten the ones we own."""
    mine, rest = _split_front(head)
    theirs, _ = _split_front(existing)
    if mine is None or theirs is None:
        return head
    known = {k for k, _ in _blocks(mine)}
    extra = [ln for k, lines in _blocks(theirs) if k and k not in known for ln in lines]
    if not extra:
        return head
    return "---\n" + "\n".join(mine + extra) + "\n---\n" + rest


def _mask(head):
    """The generated region with the user's editable values blanked: what is left is text
    only a person could have typed. Table data rows keep their date, properties keep their
    key, and the computed Net/Target/Source row goes."""
    out = []
    for line in _norm(_body(head)).split("\n"):
        if line.startswith("|"):
            cells = line.strip("|").split("|")
            if cells[0].lower() in ("date", "net") or re.fullmatch(r"-+", cells[0]):
                out.append(line)
            else:
                m = DATE_RE.search(cells[0])
                out.append("|" + (m[1] if m else "*") + "|")
        else:
            out.append(line)
    return "\n".join(l for l in out if l.strip())      # blank lines are not text


def _hold(path, cur, st, report, body):
    st["held"][str(path)] = sha(cur)
    report["skipped"][str(path)] = "held"
    notify.toast("timetrack", "Timesheet not updated", f"{path.stem}: {body}")


def _put(path, head, days, now, st, report):
    """Write `head` + the user's notes if that differs, unless the user may be in it, has
    text here that is not ours, or has removed the `## Notes` marker (then the file is held
    and never overwritten). Records what was shown."""
    key = str(path)
    if not path.exists():
        text = head + MARKER + "\n"
    else:
        cur_b = path.read_bytes()
        cur = cur_b.decode(errors="replace")
        head = _keep_properties(head, cur)
        m = NOTES_RE.search(cur)
        text = head + MARKER + (cur[m.end():] if m else "\n")
        if cur_b == text.encode() or _norm(cur) == _norm(text):
            st["files"][key] = {"hash": sha(cur_b), "days": days, "head": head}
            return
        if now - path.stat().st_mtime < QUIET:
            report["skipped"][key] = "quiet"
            return
        if st["held"].get(key) == sha(cur_b):
            report["skipped"][key] = "held"
            return
        if st["files"].get(key, {}).get("hash") != sha(cur_b):
            report["skipped"][key] = "unsynced"      # an edit sync has not read yet
            return
        if m is None:
            _hold(path, cur_b, st, report, "Keep the ## Notes heading; your text is safe")
            return
        last = st["files"].get(key, {}).get("head")
        if last is not None and _mask(cur[:m.start()]) != _mask(last):
            _hold(path, cur_b, st, report,
                  "there is text here outside the table/properties; move it below ## Notes")
            return
    _atomic(path, text)
    st["files"][key] = {"hash": sha(text), "days": days, "head": head}
    st["held"].pop(key, None)
    report["written"].append(key)


def _render(conn, month, now, st, report):
    today = date.fromtimestamp(now)
    recs = load_days(conn, month, upto=today)
    if not recs or not config.VAULT.is_dir():
        return                  # nothing to show, or no vault on this machine to put it in
    _put(config.TIMESHEET / f"{month}.md", month_head(conn, month, recs, today),
         {r["day"]: r["v"] for r in recs}, now, st, report)
    for rec in recs:
        _put(config.TIMESHEET_DAYS / f"{rec['day']}.md", day_head(conn, rec, month),
             {rec["day"]: rec["v"]}, now, st, report)


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


def _overrides(rec, day, changes):
    """The day's overrides after applying `changes` ({field: cell value or None}).

    A cell equal to the measured clock keeps the measured seconds (no needless drift)."""
    ov = dict(rec["ov"])
    for f, val in changes.items():
        if f == "kind":
            continue
        if val is None:
            ov.pop(f, None)
        elif f in ("login", "logout"):
            m = rec["meas"][f]
            ov[f] = m if (m and _clock_of(m, day) == val) else _unix(day, val)
        else:
            ov[f] = val
    return ov


def _validate(rec, ov):
    """Raise ValueError if the EFFECTIVE day (measured, overlaid by `ov`) cannot be a day."""
    eff = {**rec["meas"], **ov}
    if eff["login"] is None or eff["logout"] is None:
        if ov:
            raise ValueError("fill both Login and Logout to record hours for this day")
        return
    if eff["logout"] <= eff["login"]:
        raise ValueError("Logout must be after Login")
    span = rmin(eff["logout"] - eff["login"])
    used = sum(eff[k] for k in MINUTES)
    if used > span:
        raise ValueError(f"breaks and off add up to {fmt_min(used)}, more than the "
                         f"{fmt_min(span)} between login and logout")


def _target(kind):
    return 0 if kind in ZERO_TARGET else config.hours_per_day() * 60


def _submitted(conn, month):
    return conn.execute("SELECT 1 FROM monthly_submission WHERE month = ?", (month,)).fetchone()


def _running(conn, day, today):
    """Is the live clock open on this day right now? Only today can be: a past day's session
    that was never closed (a hotkey interval, a crashed daemon) must stay editable."""
    return day == today.isoformat() and conn.execute(
        "SELECT 1 FROM work_session WHERE attendance_day = ? AND provenance = 'live'"
        " AND closed_unix IS NULL", (day,)).fetchone()


def _store(conn, day, ov, now, surface):
    """Write the overrides as a day_edit row; no overrides, no row."""
    if not ov:
        conn.execute("DELETE FROM day_edit WHERE day = ?", (day,))
        return
    conn.execute("INSERT OR IGNORE INTO day_edit(day, edited_unix, surface) VALUES (?,?,?)",
                 (day, int(now), surface))
    sets = {OVERRIDE.get(f, f): ov.get(f) for f in HOURS}
    conn.execute(
        "UPDATE day_edit SET " + ", ".join(f"{c} = ?" for c in sets) + ", edited_unix = ?,"
        " surface = ? WHERE day = ?", [*sets.values(), int(now), surface, day])


def sync(conn, now=None):
    """Read the user's edits back into work.db, then re-render. Returns a small report.

    An edit is one FIELD that differs from the baseline of the file it is in (what that file
    last showed). Only edited fields are written, so everything else stays measured."""
    now = time.time() if now is None else now
    today = date.fromtimestamp(now)
    st = load_state()
    report = {"applied": 0, "rejected": 0, "held": 0, "files": 0, "written": [], "skipped": {}}
    months = {today.strftime("%Y-%m")}

    changed = []
    for path in vault_files():
        key, data = str(path), path.read_bytes()
        h = sha(data)
        if now - path.stat().st_mtime < QUIET or st["held"].get(key) == h:
            continue
        ent = st["files"].get(key)
        if ent is None:
            # No record of what this file last showed (state lost, or a file we never wrote):
            # nothing in it can be told from an edit, so none is read. It is re-rendered.
            st["files"][key] = {"hash": h, "days": {}}
            months.add(path.stem[:7])
            continue
        if ent.get("hash") == h:
            st["held"].pop(key, None)        # put back exactly as rendered: the mistake is gone
            continue
        changed.append((path, h, data, ent))

    pending = {}                      # (day, field) -> [(mtime, surface, value, path key)]
    for path, h, data, ent in changed:
        key, surface = str(path), ("month" if path.parent == config.TIMESHEET else "day")
        text = data.decode(errors="replace")
        report["files"] += 1
        parsed = (parse_sheet(text, path.stem) if surface == "month"
                  else parse_day_note(text, path.stem))
        edits, bad = {}, None             # day -> {field: value}
        accepted = {}
        for day, raw in parsed.items():
            b = ent["days"].get(day)
            rec = _rec(conn, day) if b is not None else None
            if rec is None:
                continue
            try:
                v = canon(raw, b)
            except ValueError as e:
                bad = (day, b, raw, str(e))
                break
            d = {f: v[f] for f in FIELDS if v[f] != b[f]}
            if not d:
                continue
            if _submitted(conn, day[:7]):
                _reject(conn, now, surface, day, b, v, "submitted")
                report["rejected"] += 1
                continue
            if date.fromisoformat(day) > today:
                dropped = {f: x for f, x in d.items() if f != "kind"}
                if dropped:
                    _reject(conn, now, surface, day, b, dropped,
                            "future day: only Kind can change before the day has happened")
                    report["rejected"] += 1
                d = {f: x for f, x in d.items() if f == "kind"}
            if d.get("logout") and _running(conn, day, today):
                _reject(conn, now, surface, day, b, {"logout": d.pop("logout")},
                        "Today is still running; set Logout after you log out")
                report["rejected"] += 1
            if not d:
                continue
            try:
                _validate(rec, _overrides(rec, day, d))
            except ValueError as e:
                bad = (day, b, d, str(e))
                break
            edits[day] = d
            accepted[day] = v
        if bad:
            day, b, v, reason = bad
            st["held"][key] = h
            _reject(conn, now, surface, day, b, v, reason)
            report["rejected"] += 1
            report["held"] += 1
            continue
        mtime = path.stat().st_mtime
        for day, d in edits.items():
            for f, val in d.items():
                pending.setdefault((day, f), []).append((mtime, surface, val, key))
        # processed: whatever the file says now is what render may replace
        st["held"].pop(key, None)
        ent["hash"] = h
        ent["days"] = {**ent["days"], **accepted}

    # merge field by field; only the SAME field changed to different values in both files is a
    # conflict, and then the newer file wins
    final = {}                        # day -> (surface, {field: value})
    for (day, f), items in sorted(pending.items()):
        items.sort(key=lambda x: x[0])
        mtime, surface, val, _ = items[-1]
        for om, osurf, oval, _k in items[:-1]:
            if oval != val:
                _reject(conn, now, osurf, day, None, {f: oval},
                        f"{f} was also changed in the {surface}, which is newer")
                report["rejected"] += 1
        final.setdefault(day, (surface, {}))[1][f] = val
        final[day] = (surface, final[day][1])

    for day, (surface, d) in sorted(final.items()):
        rec = _rec(conn, day)
        if rec is None:
            continue
        months.add(day[:7])
        ov = _overrides(rec, day, d)
        try:
            _validate(rec, ov)
        except ValueError as e:
            _reject(conn, now, surface, day, rec["v"], d, str(e))
            report["rejected"] += 1
            continue
        if "kind" in d and d["kind"] != rec["v"]["kind"]:
            conn.execute("UPDATE day_class SET kind = ?, target_minutes = ? WHERE day = ?",
                         (d["kind"], _target(d["kind"]), day))
            _log(conn, day, now, surface, "kind", {"kind": rec["v"]["kind"]},
                 {"kind": d["kind"],
                  "pinned": d["kind"] != calendar_.classify(date.fromisoformat(day))[0]})
            report["applied"] += 1
        fields = {f: x for f, x in d.items() if f != "kind"}
        if not fields:
            continue
        sets = {f: x for f, x in fields.items() if x is not None}
        clears = {f: None for f, x in fields.items() if x is None and f in rec["ov"]}
        _store(conn, day, ov, now, surface)
        if sets:
            _log(conn, day, now, surface, "set", {f: rec["v"][f] for f in sets}, sets)
            report["applied"] += 1
        if clears:
            _log(conn, day, now, surface, "clear", {f: rec["v"][f] for f in clears}, clears)
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
