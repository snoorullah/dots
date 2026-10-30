"""Sender authentication, in SHADOW: measured and logged, never enforced.

For every new message we ask what OUR receiving server (rules.toml `[alerts] authserv_id`)
wrote in the topmost Authentication-Results: did it record dmarc=pass aligned with the From
domain? The answer is one `auth_shadow` event: ref = sender class, detail = result. No
address, subject or message id is stored, so the table says how much mail is verifiable
without saying who wrote it. Nothing here changes a decision.

  result   meaning
  pass     our header is on top and records dmarc=pass for the From domain
  fail     our header is on top and does not (no dmarc, dmarc=fail, other domain)
  none     no header of ours on top: this kind of mail carries nothing we can use
  unknown  no authserv_id configured, so nothing was judged

Sender classes come from the user's rules (never hard-coded here): `[sender_class]` names
extra ones as `name = "address regex"` (full match on the parsed address), then the built-ins
alert, backup, internal (a `[people]` domain) and external.

`auth-report` prints the counts, so after a week the owner can see whether internal,
chat-relay and ERP-relay mail carries a usable result before any enforcement is switched on.
"""
import re
import time

from . import alerts, db


def result(m, cfg):
    serv = str((cfg.get("alerts") or {}).get("authserv_id") or "").strip()
    if not serv:
        return "unknown"
    if alerts._trusted_ar(m, serv) is None:
        return "none"
    return "pass" if alerts.authenticated(m, cfg) else "fail"


def sender_class(m, cfg):
    addr = alerts.sender(m)
    if not addr:
        return "multi-from" if m.get("from_count", 1) > 1 else "no-from"
    for name, pat in (cfg.get("sender_class") or {}).items():
        if isinstance(pat, str) and alerts._full(pat, addr):
            return re.sub(r"[^A-Za-z0-9_.-]", "", str(name))[:40] or "custom"
    a, b = cfg.get("alerts") or {}, cfg.get("backup") or {}
    if a.get("from") and alerts._full(a["from"], addr):
        return "alert"
    if b.get("from") and alerts._full(b["from"], addr):
        return "backup"
    doms = [str(x).lower() for x in (cfg.get("people") or {}).get("domains", [])]
    if any(addr.endswith("@" + d) for d in doms):
        return "internal"
    return "external"


def run(conn, new, cfg=None):
    from . import config
    cfg = config.rules() if cfg is None else cfg
    now = int(time.time())
    for m in new:
        db.log(conn, "auth_shadow", sender_class(m, cfg), result(m, cfg), ts=now)


def report(a):
    conn = db.open_db()
    since = int(time.time()) - a.days * 86400
    table = {}
    for r in conn.execute("SELECT ref, detail, COUNT(*) AS n FROM event WHERE kind='auth_shadow' "
                          "AND ts_unix >= ? GROUP BY ref, detail", (since,)):
        table.setdefault(r["ref"], dict.fromkeys(("pass", "fail", "none", "unknown"), 0))[r["detail"]] = r["n"]
    if not table:
        print(f"no auth_shadow events in the last {a.days} days")
        return 0
    print(f"auth in shadow, last {a.days} days (nothing is enforced)")
    print(f"{'class':16} {'pass':>6} {'fail':>6} {'none':>6} {'unknown':>8} {'total':>6} {'usable':>7}")
    tot = dict.fromkeys(("pass", "fail", "none", "unknown"), 0)
    for k, r in sorted(table.items(), key=lambda kv: -sum(kv[1].values())):
        n = sum(r.values())
        for f in tot:
            tot[f] += r[f]
        print(f"{k[:16]:16} {r['pass']:>6} {r['fail']:>6} {r['none']:>6} {r['unknown']:>8} {n:>6} "
              f"{(r['pass'] + r['fail']) * 100 // n:>6}%")
    n = sum(tot.values())
    print(f"{'total':16} {tot['pass']:>6} {tot['fail']:>6} {tot['none']:>6} {tot['unknown']:>8} {n:>6} "
          f"{(tot['pass'] + tot['fail']) * 100 // n:>6}%")
    print("usable = our server left a result (pass or fail). A class with a low usable share "
          "cannot be gated on authentication.")
    return 0


def add_parser(sub):
    p = sub.add_parser("auth-report", help="pass/fail counts per sender class (auth runs in shadow)")
    p.add_argument("--days", type=int, default=7)
    p.set_defaults(fn=report)
