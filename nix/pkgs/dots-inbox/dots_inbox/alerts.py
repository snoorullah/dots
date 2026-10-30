"""Alert mail is a stream, not a set of messages: the same ~16 alerts re-sent every few
hours. Reading it one mail at a time is how an inbox gets buried, so this module keeps the
STATE (alert_state) and notifies only on a transition.

  FIRING when not firing        state firing, one `alert_firing` event, may notify
  FIRING again                  repeats += 1, nothing else
  RESOLVED when firing          state resolved, one `alert_resolved` event, may notify
  firing with no mail for 6 h   stale: counted as resolved on screen, never notified

What notifies, once per post-new run, in ONE toast:
  - a new firing, unless that alert fired (or flapped) within the last 6 h
  - a resolution of an alert that had been firing for at least 30 min
Backup mail is the exception that proves the rule: success is silent and leaves the
inbox; a failure is an alert the user must see, so it gets the inbox and a toast
(triage.notify sends it: the decision says notify = now).

What an alert mail looks like is the user's business (rules.toml `[alerts]` and
`[backup]`); nothing here knows a sender, a cluster or a product.
"""
import hashlib
import json
import re
import sys
import time

from . import config, db, mail
from . import notify as _nt

STALE_S = 6 * 3600
DEFAULT_SUBJECT = (r"^\[(?P<severity>\w+)\]\s+(?P<name>\S+)\s+\((?P<state>FIRING|RESOLVED)\)"
                   r"\s*[—–-]\s*(?P<scope>.+?)\s*$")


def _re(pat, text):
    return re.search(pat, text or "", re.I) if pat else None


def _full(pat, text):
    return re.fullmatch(pat, text or "", re.I) if pat else None


def sender(m):
    """The parsed address only: a display name like "alerts@corp <x@evil>" must not match.
    A From with several addresses matches nothing."""
    return (m.get("from_addr") or "").lower() if m.get("from_count", 1) == 1 else ""


def _strip(value):
    """Authentication-Results text with comments (nested parens) and quoted values removed, so
    `dkim=fail (dkim=pass)` and `smtp.mailfrom="dmarc=pass@evil"` carry no result of theirs."""
    out, depth, quote, esc = [], 0, False, False
    for ch in value or "":
        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                quote = False
            continue
        if ch == '"' and depth == 0:
            quote = True
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return re.sub(r"\s*=\s*", "=", "".join(out))


def _segments(clean):
    """Split on ';' only where whitespace follows (or the text ends): a ';' glued to a value, as in
    `smtp.mailfrom=a;dmarc=pass`, stays inside that value and cannot start a result of its own."""
    return re.split(r";(?=\s|$)", clean)


def _trusted_ar(m, authserv):
    """The Authentication-Results to trust, as cleaned text, or None. Our receiving server stamps
    its header on top of whatever arrived, so the TOPMOST header overall must carry our authserv-id;
    anything else on top means the mail did not come in the way we expect, and an identical-looking
    header further down is just a claim the sender made."""
    h = m.get("headers") or {}
    allv = h.get("authentication-results-all")
    if allv is None:
        allv = [h["authentication-results"]] if h.get("authentication-results") else []
    if not allv:
        return None
    clean = _strip(allv[0])
    head = _segments(clean)[0].split()
    return clean if head and head[0].lower() == authserv.lower() else None


def authenticated(m, cfg):
    """True when OUR receiving server (rules.toml [alerts] authserv_id) recorded dmarc=pass
    for a header.from equal to this mail's From domain. No configured id = never."""
    authserv = str((cfg.get("alerts") or {}).get("authserv_id") or "").strip()
    addr = sender(m)
    if not authserv or "@" not in addr:
        return False
    clean = _trusted_ar(m, authserv)
    if clean is None:
        return False
    domain = addr.rsplit("@", 1)[1]
    for seg in _segments(clean)[1:]:
        toks = seg.split()
        if toks and toks[0].lower() == "dmarc=pass" and any(
                t.lower() == f"header.from={domain}" for t in toks[1:]):
            return True
    return False


def fingerprint(m):
    """Identity of this physical message: its file bytes, else the fields the gate reads."""
    try:
        with open(m["file"], "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except (KeyError, TypeError, OSError):
        h = m.get("headers") or {}
        blob = json.dumps([m.get("from_addr"), m.get("subject"), m.get("date"),
                           h.get("authentication-results-all"), h.get("authentication-results")], default=str)
        return hashlib.sha256(blob.encode()).hexdigest()


def all_copies_pass(m, cfg):
    """The mail AND every other file notmuch merged under its Message-ID must pass the gate and
    agree on subject and sender; one failing copy fails the id."""
    if not authenticated(m, cfg):
        return False
    return all(authenticated(c, cfg) and c.get("subject") == m.get("subject")
               and c.get("from_addr") == m.get("from_addr") for c in m.get("copies") or [])


def classify(m, cfg):
    """None, or {'kind': 'alert'|'backup_ok'|'backup_fail', ...parsed fields}."""
    a, b = cfg.get("alerts", {}), cfg.get("backup", {})
    subj = m.get("subject", "")
    if a.get("from") and _full(a["from"], sender(m)):
        mt = re.search(a.get("subject", DEFAULT_SUBJECT), subj, re.S)
        if mt:
            g = mt.groupdict()
            return {"kind": "alert", "severity": (g.get("severity") or "").upper(),
                    "name": g.get("name") or subj, "state": (g.get("state") or "FIRING").upper(),
                    "scope": g.get("scope") or ""}
    if b.get("from") and _full(b["from"], sender(m)):
        if _re(b.get("fail"), subj):
            return {"kind": "backup_fail"}
        if _re(b.get("ok"), subj):
            return {"kind": "backup_ok"}
    return None


def decide(m, cfg):
    c = classify(m, cfg) or {"kind": "alert"}
    d = {"kind": c["kind"], "handler": "alerts", "add": {"alert"}, "remove": set(),
         "inbox": False, "notify": "none", "critical": None}
    if c["kind"] == "backup_ok":
        d["add"], d["remove"] = {"backup"}, {"alert"}
    elif c["kind"] == "backup_fail":
        d["inbox"], d["notify"] = True, "now"
    return d


def run(conn, new, now=None):
    from . import triage
    cfg = config.rules()
    stale = int(float(cfg.get("alerts", {}).get("stale_hours", 6)) * 3600)
    minfire = int(float(cfg.get("alerts", {}).get("min_firing_minutes", 30)) * 60)
    wall = now or time.time()
    gate_on = bool(str(cfg.get("alerts", {}).get("authserv_id") or "").strip())
    fired, resolved = [], []
    mine = [(m, classify(m, cfg)) for m in new]
    mine = sorted((x for x in mine if x[1]), key=lambda x: x[0].get("date", 0))
    for m, c in mine:
        d = decide(m, cfg)
        m["_triage"] = d
        try:
            ch = triage._changes(d, m)
            if ch:
                mail.tag(m["id"], *ch)
        except RuntimeError as e:
            print(f"dots-inbox: tag {m['id']}: {e}", file=sys.stderr)
        if c["kind"] != "alert":
            continue
        t = int(m.get("date") or wall)
        ok = all_copies_pass(m, cfg)
        if gate_on and not ok:
            # tagging above is unchanged; but an unauthenticated mail must not move alert state, fire
            # a toast, take the prep slot or feed the analysis. Recorded by Message-ID for the gate.
            _msg(conn, m, c["name"], c["scope"], False, int(m.get("date") or wall), None)
            db.log(conn, "alert_unauth", m.get("id"), c["name"], ts=int(m.get("date") or wall))
            continue
        fresh = wall - t < stale                         # an old mail is backlog, never a toast
        name, scope = c["name"], c["scope"]
        row = conn.execute("SELECT * FROM alert_state WHERE name=? AND scope=?",
                           (name, scope)).fetchone()
        was_firing = bool(row and row["state"] == "firing" and t - row["last_unix"] < stale)
        _msg(conn, m, name, scope, ok, t, None)
        if c["state"] == "FIRING":
            if was_firing:
                conn.execute("UPDATE alert_state SET repeats=repeats+1, last_unix=max(last_unix,?)"
                             " WHERE name=? AND scope=?", (t, name, scope))
                continue
            recent = bool(row and t - row["last_unix"] < stale)      # fired or flapped lately
            tell = fresh and not recent
            conn.execute("INSERT OR REPLACE INTO alert_state(name,scope,severity,state,since_unix,"
                         "last_unix,repeats,notified_unix) VALUES(?,?,?,'firing',?,?,1,?)",
                         (name, scope, c["severity"], t, t, t if tell else None))
            db.log(conn, "alert_firing", f"{name}|{scope}", m.get("subject"), ts=t)
            _msg(conn, m, name, scope, ok, t, conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            if tell:
                fired.append((name, scope))
        elif row and row["state"] == "firing":
            long_enough = t - row["since_unix"] >= minfire
            conn.execute("UPDATE alert_state SET state='resolved', since_unix=?, last_unix=? "
                         "WHERE name=? AND scope=?", (t, t, name, scope))
            db.log(conn, "alert_resolved", f"{name}|{scope}", m.get("subject"), ts=t)
            if fresh and was_firing and long_enough:
                resolved.append((name, scope))
        elif row:
            conn.execute("UPDATE alert_state SET last_unix=? WHERE name=? AND scope=?",
                         (t, name, scope))
    if (fired or resolved) and not config.panic():
        lines = [f"FIRING   {n} - {s}" for n, s in fired] + \
                [f"resolved {n} - {s}" for n, s in resolved]
        more = len(lines) - 6
        _nt.toast("Mail", f"Alerts: {len(fired)} firing, {len(resolved)} resolved",
                  "\n".join(lines[:6] + ([f"+{more} more"] if more > 0 else [])))


def _msg(conn, m, name, scope, ok, t, rowid):
    """Record this physical mail (Message-ID + fingerprint) with its gate result and the firing
    event it caused. A second mail with the same id but other content gets its OWN row."""
    if not m.get("id"):
        return
    conn.execute("INSERT INTO alert_msg(msgid,fp,name,scope,authed,ts_unix,event_rowid) VALUES(?,?,?,?,?,?,?) "
                 "ON CONFLICT(msgid,fp) DO UPDATE SET event_rowid=COALESCE(excluded.event_rowid,event_rowid)",
                 (m["id"], fingerprint(m), name, scope, int(ok), t, rowid))


def firing(conn, now=None):
    """Rows still firing; a firing alert with no mail for 6 h is stale and not listed."""
    wall = now or time.time()
    return [r for r in conn.execute("SELECT * FROM alert_state WHERE state='firing' "
                                    "ORDER BY since_unix") if wall - r["last_unix"] < STALE_S]


def _age(s):
    s = int(s)
    if s >= 86400:
        return f"{s // 86400}d"
    return f"{s // 3600}h{s % 3600 // 60:02d}m" if s >= 3600 else f"{s // 60}m"


def show(a):
    conn = db.open_db()
    rows = firing(conn)
    if not rows:
        print("nothing firing")
        return 0
    print(f"{'ALERT':40} {'SCOPE':28} {'SINCE':>8} {'REPEATS':>8}")
    for r in rows:
        print(f"{r['name'][:40]:40} {r['scope'][:28]:28} "
              f"{_age(time.time() - r['since_unix']):>8} {r['repeats']:>8}")
    return 0


def add_parser(sub):
    sub.add_parser("alerts", help="print what is firing now").set_defaults(fn=show)
