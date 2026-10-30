"""Sender authentication, in SHADOW: measured and logged, never enforced.

Real mail on a tenant like ours arrives through a gateway, so Microsoft's own `dmarc=` is
evaluated against the gateway and is `fail` for nearly every genuine outside sender: it says
nothing. The rule here asks four narrower questions, each answered only from headers OUR
server stamped (everything from the sender's side is a claim, never a fact):

  internal  exactly one X-MS-Exchange-Organization-AuthAs: Internal, a From domain that is one
            of `[auth] tenant_domains`, and a cross-tenant id that is absent or in `tenant_ids`
  gateway   AuthAs Anonymous + MessageDirectionality Incoming + the connecting IP (CIP: in
            X-Forefront-Antispam-Report) pinned to `gateway_ips`, and an ARC chain 1..N whose
            topmost seal is microsoft.com cv=pass, whose seal N-1 is `gateway_sealer` and whose
            ARC-Authentication-Results N-1 records dmarc=pass header.from=<the From domain>
  digest    CIP pinned to `digest_ips` and our own Authentication-Results records dmarc=pass
            for the From domain
  relay     CIP pinned to `relay_ips`: weak, a host that cannot authenticate; the hop is the
            only evidence. Never counts as authenticated.

NOT verified here: ARC cryptography. We rely on Microsoft's topmost seal saying cv=pass (it
validated the chain below it, the gateway's seal and the result it carries); a forged lower
chain makes that seal cv=fail. Never trusted: any X-<gateway>-* style header, a Received
line below ours, a second copy of a header we stamp once, anything inside a comment or quoted
value of an Authentication-Results.

One `auth_shadow` event per new message: ref = sender class, detail = verdict
(`internal`, `gateway`, `digest`, `relay`, `fail:<reason>`, `unknown` when no [auth] section
exists). No address, subject or message id is stored. `auth-report` prints the counts;
`auth-report --dry-run` replays the rule over existing mail files, headers only, and prints
counts per class, never a body or an address.

Sender classes come from the user's rules (never hard-coded here): `[sender_class]` names
extra ones as `name = "address regex"` (full match on the parsed address), then the built-ins
alert, backup, internal (a `[people]` domain) and external.
"""
import re
import time

from . import alerts, db

STRONG = ("internal", "gateway", "digest")        # relay is weak: a hop is not an identity
VERDICTS = ("internal", "gateway", "digest", "relay", "fail", "unknown")


def _all(m, name):
    h = m.get("headers") or {}
    v = h.get(name + "-all")
    if v is None:
        v = [h[name]] if h.get(name) else []
    return [str(x) for x in v]


def _lst(a, key):
    return [str(x).strip().lower() for x in (a.get(key) or []) if str(x).strip()]


def _from_domain(m):
    addr = alerts.sender(m)
    return addr.rsplit("@", 1)[1] if "@" in addr else ""


def _cip(m):
    """The connecting IP our server recorded. Exactly one X-Forefront-Antispam-Report (a sender's
    own copy is renamed -untrusted by Exchange; a second plain one is a forgery), exactly one CIP."""
    rep = _all(m, "x-forefront-antispam-report")
    if len(rep) != 1:
        return ""
    ips = re.findall(r"(?:^|;)\s*CIP:\s*([0-9a-fA-F:.]+)\s*(?=;|$)", rep[0])
    return ips[0].lower() if len(ips) == 1 else ""


def _tags(header):
    out = {}
    for part in alerts._strip(header).split(";"):
        k, _, v = part.partition("=")
        if k.strip() and k.strip().lower() not in out:
            out[k.strip().lower()] = v.strip()
    return out


def _arc(m):
    """({i: seal tags}, {i: cleaned ARC-AR text}, topmost seal i), or None when the chain is not
    a plain 1..N with one seal and one result per instance."""
    seals, ars, order = {}, {}, []
    for s in _all(m, "arc-seal"):
        t = _tags(s)
        try:
            i = int(t["i"])
        except (KeyError, ValueError):
            return None
        if i in seals:
            return None
        seals[i] = t
        order.append(i)
    for s in _all(m, "arc-authentication-results"):
        seg = alerts._segments(alerts._strip(s))
        try:
            i = int(seg[0].strip().lower().removeprefix("i="))
        except ValueError:
            return None
        if i in ars:
            return None
        ars[i] = seg
    n = len(seals)
    if n < 2 or sorted(seals) != list(range(1, n + 1)) or order[0] != n:
        return None
    return seals, ars, n


def _dmarc_pass(segments, domain):
    for seg in segments:
        toks = seg.split()
        if toks and toks[0].lower() == "dmarc=pass" and any(
                t.lower() == f"header.from={domain}" for t in toks[1:]):
            return True
    return False


def _gateway(m, a, domain, cip):
    if [v.strip() for v in _all(m, "x-ms-exchange-organization-authas")] != ["Anonymous"]:
        return "authas"
    if [v.strip() for v in _all(m, "x-ms-exchange-organization-messagedirectionality")] != ["Incoming"]:
        return "direction"
    if not cip or cip not in _lst(a, "gateway_ips"):
        return "cip"
    sealer = str(a.get("gateway_sealer") or "").strip().lower()
    arc = _arc(m)
    if not sealer or arc is None:
        return "arc-shape"
    seals, ars, n = arc
    top, gw = seals[n], seals[n - 1]
    if top.get("d", "").lower() != "microsoft.com" or top.get("cv", "").lower() != "pass":
        return "top-seal"
    if gw.get("d", "").lower() != sealer or gw.get("cv", "").lower() != ("none" if n - 1 == 1 else "pass"):
        return "sealer"
    if n - 1 not in ars or not _dmarc_pass(ars[n - 1][1:], domain):
        return "gw-dmarc"
    return None


def verdict(m, cfg):
    """(verdict, reason): verdict in VERDICTS; reason names the first check a failing mail missed."""
    a = cfg.get("auth") or {}
    if not a:
        return "unknown", ""
    domain = _from_domain(m)
    if not domain:
        return "fail", "from"
    cip = _cip(m)
    authas = [v.strip() for v in _all(m, "x-ms-exchange-organization-authas")]
    why = ""
    if authas == ["Internal"]:
        ids = _all(m, "x-ms-exchange-crosstenant-id")
        if domain not in _lst(a, "tenant_domains"):
            why = "internal-domain"
        elif len(ids) > 1 or (ids and ids[0].strip().lower() not in _lst(a, "tenant_ids")):
            why = "internal-tenant"
        else:
            return "internal", ""
    elif authas == ["Anonymous"]:
        why = _gateway(m, a, domain, cip)
        if why is None:
            return "gateway", ""
        serv = str((cfg.get("alerts") or {}).get("authserv_id") or "").strip()
        if cip and cip in _lst(a, "digest_ips") and serv:
            clean = alerts._trusted_ar(m, serv)
            if clean is not None and _dmarc_pass(alerts._segments(clean)[1:], domain):
                return "digest", ""
        if cip and cip in _lst(a, "relay_ips"):
            return "relay", ""
    else:
        why = "authas"
    return "fail", why


def authenticated(m, cfg):
    """True when the shadow rule says the sender is who the From says, by a strong path."""
    return verdict(m, cfg)[0] in STRONG


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


def _detail(m, cfg):
    v, why = verdict(m, cfg)
    return f"{v}:{why}" if why else v


def run(conn, new, cfg=None):
    from . import config
    cfg = config.rules() if cfg is None else cfg
    now = int(time.time())
    for m in new:
        db.log(conn, "auth_shadow", sender_class(m, cfg), _detail(m, cfg), ts=now)


def _bucket(detail):
    return detail.split(":", 1)[0] if detail.split(":", 1)[0] in VERDICTS else "fail"


def _table(rows):
    """rows: (class, detail, n) -> ({class: {verdict: n}}, {reason: n})."""
    table, reasons = {}, {}
    for k, d, n in rows:
        b = _bucket(d)
        table.setdefault(k, dict.fromkeys(VERDICTS, 0))[b] += n
        if b == "fail" and ":" in d:
            reasons[d.split(":", 1)[1]] = reasons.get(d.split(":", 1)[1], 0) + n
    return table, reasons


def _print(table, reasons, title):
    print(title)
    cols = VERDICTS
    print(f"{'class':16}" + "".join(f"{c:>10}" for c in cols) + f"{'total':>8}{'strong':>8}")
    tot = dict.fromkeys(cols, 0)
    for k, r in sorted(table.items(), key=lambda kv: -sum(kv[1].values())):
        n = sum(r.values())
        for f in tot:
            tot[f] += r[f]
        strong = sum(r[v] for v in STRONG)
        print(f"{k[:16]:16}" + "".join(f"{r[c]:>10}" for c in cols) + f"{n:>8}{strong * 100 // n:>7}%")
    n = sum(tot.values())
    if n:
        print(f"{'total':16}" + "".join(f"{tot[c]:>10}" for c in cols) + f"{n:>8}"
              f"{sum(tot[v] for v in STRONG) * 100 // n:>7}%")
    if reasons:
        print("fail reasons: " + ", ".join(f"{k} {v}" for k, v in sorted(reasons.items(), key=lambda kv: -kv[1])))
    print("strong = internal + gateway + digest. relay is weak (a hop, not an identity). ARC crypto is not "
          "verified here: we rely on Microsoft's top seal.")


def _survey(days, cfg):
    """Replay the rule over the mail files of the last `days` days. Read-only: headers only."""
    from . import config, mail
    out = mail._nm("search", "--output=files", f"date:{days}d..")
    rows = {}
    for path in out.splitlines():
        m = mail.from_file(path.strip())
        if m:
            key = (sender_class(m, cfg), _detail(m, cfg))
            rows[key] = rows.get(key, 0) + 1
    return [(k, d, n) for (k, d), n in rows.items()]


def report(a):
    from . import config
    if getattr(a, "dry_run", False):
        cfg = config.rules()
        if not cfg.get("auth"):
            print("no [auth] section in rules.toml: nothing to judge")
            return 1
        table, reasons = _table(_survey(a.days, cfg))
        if not table:
            print(f"no mail in the last {a.days} days")
            return 0
        _print(table, reasons, f"auth rule replayed over the last {a.days} days of mail files "
                               "(dry run: headers only, nothing stored)")
        return 0
    conn = db.open_db()
    since = int(time.time()) - a.days * 86400
    table, reasons = _table((r["ref"], r["detail"], r["n"]) for r in conn.execute(
        "SELECT ref, detail, COUNT(*) AS n FROM event WHERE kind='auth_shadow' AND ts_unix >= ? "
        "GROUP BY ref, detail", (since,)))
    if not table:
        print(f"no auth_shadow events in the last {a.days} days")
        return 0
    _print(table, reasons, f"auth in shadow, last {a.days} days (nothing is enforced)")
    return 0


def add_parser(sub):
    p = sub.add_parser("auth-report", help="verdict counts per sender class (auth runs in shadow)")
    p.add_argument("--days", type=int, default=7)
    p.add_argument("--dry-run", action="store_true", help="replay the rule over mail files, headers only")
    p.set_defaults(fn=report)
