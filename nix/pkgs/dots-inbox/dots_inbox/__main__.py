"""dots-inbox CLI.

`post-new` is the pipeline notmuch runs after every sync (its post-new hook): triage the
new mail, update alert state, update the ledger, notify, queue preparation. Each stage is
isolated: one failing stage is logged and the rest still run, and the last stage always
clears tag:new so a broken stage never re-processes the same mail forever.
"""
import argparse
import sys
import time

from . import config, db, mail


def post_new(a):
    if not config.mounted():
        return 0
    new = mail.messages("tag:new")
    if not new:
        return 0
    from . import alerts, brief, ledger, prep, triage
    conn = db.open_db()
    stages = [("triage", lambda: triage.run(conn, new)),
              ("alerts", lambda: alerts.run(conn, new)),
              ("ledger", lambda: ledger.on_mail(conn, new)),
              ("notify", lambda: triage.notify(conn, new)),
              ("prep", lambda: prep.queue(conn, new)),
              ("counts", lambda: brief.counts(conn))]
    for name, fn in stages:
        try:
            fn()
            conn.commit()
        except Exception as e:                     # one stage must not stop the rest
            conn.rollback()
            print(f"dots-inbox: {name}: {e}", file=sys.stderr)
    for m in new:
        try:
            mail.tag(m["id"], "-new")
        except RuntimeError as e:
            print(f"dots-inbox: untag: {e}", file=sys.stderr)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="dots-inbox", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("post-new", help="the notmuch post-new pipeline").set_defaults(fn=post_new)
    from . import alerts, brief, ledger, prep, slack, triage
    for mod in (triage, alerts, ledger, slack, prep, brief):
        mod.add_parser(sub)
    a = p.parse_args(argv if argv is not None else sys.argv[1:])
    return a.fn(a) or 0


if __name__ == "__main__":
    raise SystemExit(main())
