"""What is ready for the user when they sit down.

Two outputs, deliberately different in sensitivity:

* `counts` writes NUMBERS ONLY to the dashboard's state dir. That file is outside the
  encrypted mail store, so it never carries a subject, sender or body.
* `brief` writes markdown INSIDE the store (BRIEF). Sections run in priority order, so
  the user can stop reading at any point: prepared analyses, replies they waited for,
  what needs them, what they still wait on, alerts, HR/ERP notices.

`brief --login` runs when a work session starts (timetrack's on_login hook). It is silent
when the store is locked or the panic switch is on: a locked store means no login yet,
and panic means no prompt of any kind.
"""
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time

from . import config, db, mail, notify

ALERT_STALE = 12 * 3600          # a "firing" alert with no mail for this long is stale
DEFAULT_SINCE = 16 * 3600
MAX_MAIL = 15

popen = subprocess.Popen         # seams for tests
ask = notify.ask


def _scalar(conn, sql, *args):
    return conn.execute(sql, args).fetchone()[0]


def counts(conn, now=None):
    now = int(now or time.time())
    doc = {
        "updated": now,
        "people_unread": mail.count("tag:inbox and tag:unread and (tag:people or tag:vip)"),
        "pr": mail.count("tag:inbox and tag:unread and tag:pr"),
        "alerts_firing": _scalar(conn, "SELECT COUNT(*) FROM alert_state WHERE state='firing' AND last_unix > ?",
                                 now - ALERT_STALE),
        "waiting_them": _scalar(conn, "SELECT COUNT(*) FROM item WHERE direction='them' AND state='open'"),
        "replied": _scalar(conn, "SELECT COUNT(*) FROM item WHERE direction='them' AND state='replied'"),
        "waiting_me": _scalar(conn, "SELECT COUNT(*) FROM item WHERE direction='me' AND state='open'"),
        "prepared_unseen": _scalar(conn, "SELECT COUNT(*) FROM prep WHERE status='done' AND seen_unix IS NULL"),
        "critical": mail.count("tag:inbox and tag:critical"),
    }
    path = config.OVERVIEW_COUNTS
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    with os.fdopen(fd, "w") as fh:
        json.dump(doc, fh)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return doc


# the markdown -------------------------------------------------------------------------

def _t(ts):
    return time.strftime("%a %H:%M", time.localtime(ts)) if ts else "?"


def _age(sec):
    sec = max(0, int(sec))
    if sec >= 86400:
        return f"{sec // 86400}d"
    return f"{sec // 3600}h" if sec >= 3600 else f"{sec // 60}m"


def _safe(fn, *args):
    """A section that cannot be built says so; it never takes the whole brief down."""
    try:
        return fn(*args)
    except Exception as e:
        return [f"(unavailable: {str(e)[:100]})"]


def _prepared(conn, since, now):
    rows = conn.execute("SELECT * FROM prep WHERE status='done' AND (seen_unix IS NULL OR finished_unix >= ?) "
                        "ORDER BY finished_unix DESC", (since,)).fetchall()
    out = []
    for r in rows:
        out += [f"1. **{r['title']}**", f"   {r['summary'] or ''}", f"   `{r['path']}`"]
    bad = _scalar(conn, "SELECT COUNT(*) FROM prep WHERE status IN ('failed','skipped') AND created_unix >= ?", since)
    if bad:
        out.append(f"*{bad} not prepared (failed or over the daily cap).*")
    return out, len(rows)


def _replies(conn, since, now):
    rows = conn.execute("SELECT * FROM item WHERE direction='them' AND state='replied' AND reply_unix >= ? "
                        "ORDER BY reply_unix DESC", (since,)).fetchall()
    out = []
    for r in rows:
        out += [f"1. **{r['counterpart'] or '?'}** replied {_t(r['reply_unix'])}",
                f"   asked: {r['purpose'] or r['subject'] or ''}",
                f"   said: {r['reply_summary'] or '(no summary)'}"]
    return out, len(rows)


def _needs(conn, since, now):
    out, n = [], 0
    for r in conn.execute("SELECT * FROM item WHERE direction='me' AND state='open' ORDER BY created_unix"):
        out.append(f"- **{r['counterpart'] or '?'}** is waiting: {r['subject'] or r['purpose'] or ''} "
                   f"({_age(now - r['created_unix'])})")
        n += 1
    for m in mail.messages("tag:inbox and not tag:replied and not tag:sent and "
                           "(tag:vip or tag:people or tag:ticket)", limit=MAX_MAIL):
        who = "vip" if "vip" in m["tags"] else "ticket" if "ticket" in m["tags"] else "people"
        out.append(f"- [{who}] **{m['from'].split('<')[0].strip() or m['from_addr']}**: {m['subject']}")
        n += 1
    for m in mail.messages("tag:inbox and tag:unread and tag:pr", limit=10):
        out.append(f"- [pr] {m['subject']}")
        n += 1
    return out, n


def _waiting(conn, since, now):
    nudged = {r[0] for r in conn.execute("SELECT ref FROM event WHERE kind='nudge'")}
    out = []
    for r in conn.execute("SELECT * FROM item WHERE direction='them' AND state='open' ORDER BY created_unix"):
        flag = " **nudged**" if (r["key"] in nudged or str(r["id"]) in nudged) else ""
        out.append(f"- **{r['counterpart'] or '?'}**: {r['purpose'] or r['subject'] or ''} "
                   f"({_age(now - r['created_unix'])}){flag}")
    return out, len(out)


def _alerts(conn, since, now):
    out = []
    for r in conn.execute("SELECT * FROM alert_state WHERE state='firing' AND last_unix > ? "
                          "ORDER BY since_unix", (now - ALERT_STALE,)):
        out.append(f"- `{r['name']}` {r['scope']} [{r['severity'] or '-'}] since {_t(r['since_unix'])} "
                   f"({_age(now - r['since_unix'])}, {r['repeats']}x)")
    moves = conn.execute("SELECT * FROM event WHERE kind IN ('alert_firing','alert_resolved') AND ts_unix >= ? "
                         "ORDER BY ts_unix", (since,)).fetchall()
    if moves:
        out += ["", "Since the last brief:"]
        out += [f"  {_t(e['ts_unix'])} {'fired' if e['kind'] == 'alert_firing' else 'resolved'} `{e['ref']}`"
                for e in moves[-MAX_MAIL:]]
    return out, len([1 for _ in out if _.startswith("- ")])


def _notices(conn, since, now):
    seen, out = set(), []
    for m in mail.messages("tag:inbox and (tag:hr or tag:erp)", limit=40):
        if m["date"] >= since and m["subject"] not in seen:
            seen.add(m["subject"])
            out.append(f"- {m['subject']}")
    return out[:MAX_MAIL], len(out)


SECTIONS = (("Prepared for you", _prepared), ("Replies you were waiting for", _replies),
            ("Needs you", _needs), ("Still waiting on", _waiting), ("Alerts", _alerts),
            ("HR / ERP notices", _notices))


def build(conn, since, now=None):
    """(markdown, {section: count})."""
    now = int(now or time.time())
    body, n = [], {}
    for title, fn in SECTIONS:
        try:
            lines, count = fn(conn, since, now)
        except Exception as e:
            lines, count = [f"(unavailable: {str(e)[:100]})"], 0
        n[title] = count
        body += ["---", "", f"**{title}**", ""] + (lines or ["Nothing."]) + [""]
    head = [f"# Ready for you, {_t(now)}", "",
            f"**{n['Replies you were waiting for']}** replies, **{n['Prepared for you']}** prepared, "
            f"**{n['Needs you']}** need you, **{n['Alerts']}** alerts firing.",
            f"*Since {_t(since)}.*", ""]
    return "\n".join(head + body), n


def _last_brief(conn):
    return conn.execute("SELECT MAX(ts_unix) FROM event WHERE kind='brief'").fetchone()[0]


def write(md):
    config.STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(config.BRIEF, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(md)


def popup():
    """The brief in a floating terminal. Detached; never raises."""
    cmd = f"glow -p {shlex.quote(str(config.BRIEF))}"
    try:
        popen(["ghostty", "--class=dots.brief", "--gtk-single-instance=false", "-e", "sh", "-c", cmd],
              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              start_new_session=True)
    except OSError:
        pass


def run(a):
    if not config.mounted():
        return 0                                   # locked: not logged in yet, say nothing
    if a.login and config.panic():
        return 0
    conn = db.open_db()
    now = int(time.time())
    if a.show and not a.login and config.BRIEF.exists():
        popup()
        return 0
    since = a.since if a.since is not None else (_last_brief(conn) or now - DEFAULT_SINCE)
    md, n = build(conn, since, now)
    write(md)
    if not a.login and not a.show:
        print(md)
        return 0
    if a.login:
        db.log(conn, "brief", None, f"since {since}", ts=now)
        conn.execute("UPDATE prep SET seen_unix=? WHERE status='done' AND seen_unix IS NULL", (now,))
        conn.commit()
        try:
            counts(conn, now)
        except Exception as e:
            print(f"dots-inbox: counts: {e}", file=sys.stderr)
        r, p, d = n["Replies you were waiting for"], n["Prepared for you"], n["Needs you"]
        if r or p or d:
            if ask("dots-inbox", f"Ready for you: {r} replies, {p} prepared, {d} need you",
                   "Open the brief", [("open", "Open")], 120) == "open":
                popup()
        return 0
    popup()
    return 0


def add_parser(sub):
    p = sub.add_parser("brief", help="write the brief (what is ready for you)")
    p.add_argument("--login", action="store_true", help="at session start: toast, mark prepared seen")
    p.add_argument("--show", action="store_true", help="open the brief in a popup")
    p.add_argument("--since", type=int, metavar="UNIX", help="default: the last brief, else 16 h")
    p.set_defaults(fn=run)
