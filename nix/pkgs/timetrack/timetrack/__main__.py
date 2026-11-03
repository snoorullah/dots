"""timetrack CLI.

Every subcommand opens its own connection through dbs.py and does one thing. There is no
`all` command on purpose: the old one chained rollup -> note -> sync and swallowed the
failure of each, which is how the predecessor recorded nothing for months while appearing
to work.

`export` is read-only against work.db. Nothing here can reach private.db, and nothing here
writes upstream -- the ERP integration is gated and does not exist yet.
"""
import argparse
import json
import sys
import time
from datetime import date
from pathlib import Path

from . import (attest, calendar_, config, dbs, derive, doctor, export_csv, hotkey,
               interactive, migrate, submission)


def _month(arg):
    if arg:
        return arg
    return date.today().strftime("%Y-%m")


def cmd_migrate(a):
    migrate.migrate()
    print("schema up to date")
    return 0


def cmd_seed(a):
    y, m = (int(x) for x in _month(a.month).split("-"))
    with dbs.open_work() as conn:
        n = calendar_.seed_month(conn, y, m)
        conn.commit()
    print(f"{_month(a.month)}: {n} day(s) classified")
    return 0


def cmd_import_sheet(a):
    from .backfill import sheet
    with dbs.open_work() as conn:
        n = sheet.write(conn, a.path)
        conn.commit()
    print(f"imported {n} row(s) from {a.path}")
    return 0


def cmd_backfill_git(a):
    from .backfill import git_
    with dbs.open_work() as conn:
        n = git_.write(conn, a.since, a.until)
        conn.commit()
    print(f"git backfill wrote {n} session(s) at confidence {git_.CONFIDENCE}")
    return 0


def cmd_ingest_aw(a):
    from .backfill import aw
    with dbs.open_work() as conn:
        day = None if a.no_refresh else aw.current_day(conn)
        rep = aw.write(conn, since=None, until=None, refresh_day=day)
    for w in rep["written"]:
        print(f"wrote {w['day']}: {w['gaps']} unconfirmed gap(s) recorded as breaks")
    if not rep["written"]:
        print("no new day to write")
    if rep["skipped_existing"]:
        # never silently overwrite a higher-confidence source
        print(f"skipped {len(rep['skipped_existing'])} day(s) that already have a session")
    return 0


def cmd_web(a):
    from . import web, webclass
    if a.all:
        start = web.first_day()
        days = list(web.days_since(start)) if start else []
    else:
        days = [date.fromisoformat(a.day) if a.day else date.today()]
    for d in days:
        by_dom, _ = web.write(d)
        rows = webclass.classify(d, use_llm=not a.no_llm)
        total = sum(by_dom.values())
        split = {}
        for r in rows:
            split[r[13]] = split.get(r[13], 0) + r[3]
        print(f"{d}  browser {derive.hhmm(round(total / 60))} focused and present  "
              + "  ".join(f"{k} {derive.hhmm(round(v / 60))}" for k, v in sorted(split.items())))
        for r in sorted(rows, key=lambda r: -r[3])[:a.top]:
            link = f"  {r[8]}" if r[8] else ""
            print(f"  {derive.hhmm(round(r[3] / 60)):>6}  {r[13]:<12} {r[11]:<14} {r[10][:60]}{link}")
    return 0


def cmd_term(a):
    from . import termclass
    if a.all:
        start = termclass.first_day()
        days = list(web_days(start)) if start else []
    else:
        days = [date.fromisoformat(a.day) if a.day else date.today()]
    for d in days:
        rows = termclass.classify(d, use_llm=not a.no_llm)
        total = sum(r[3] for r in rows)
        if not total and a.all:
            continue
        split, by = {}, {}
        for r in rows:
            split[r[12]] = split.get(r[12], 0) + r[3]
            by[r[13]] = by.get(r[13], 0) + r[3]
        print(f"{d}  terminal {derive.hhmm(round(total / 60))} focused and present  "
              + "  ".join(f"{k} {derive.hhmm(round(v / 60))}" for k, v in sorted(split.items())))
        if rows:
            print("  by evidence  " + "  ".join(f"{k} {derive.hhmm(round(v / 60))}"
                                               for k, v in sorted(by.items(), key=lambda kv: -kv[1])))
        groups = {}
        for r in rows:
            key = (r[9] or r[10] or "-", r[7] or "-", r[12])
            groups[key] = groups.get(key, 0) + r[3]
        for (what, agent, verdict), sec in sorted(groups.items(), key=lambda kv: -kv[1])[:a.top]:
            print(f"  {derive.hhmm(round(sec / 60)):>6}  {verdict:<12} {what[:40]:<40} {agent}")
    return 0


def web_days(start):
    from . import web
    return web.days_since(start)


def cmd_away(a):
    from . import away
    if a.prayer:
        print(away.prayer_now())
        return 0
    if a.declare:
        print(away.declare(a.declare))
        return 0
    away.watch()
    return 0


def cmd_compare_aw(a):
    from .backfill import aw
    month = _month(a.month)
    with dbs.open_work(readonly=True) as conn:
        rows = aw.compare(conn, month)
    hm = derive.hhmm
    print(f"{'day':12}{'recorded':10}{'aw':10}{'delta':10}{'ratio':8}source")
    ratios = []
    for r in rows:
        if r["ratio"]:
            ratios.append(r["ratio"])
        aw_s = hm(r["aw_minutes"]) if r["aw_minutes"] is not None else "-"
        delta = hm(r["delta_minutes"]) if r["delta_minutes"] is not None else "-"
        ratio = f"{r['ratio']:.2f}" if r["ratio"] else "-"
        print(f"{r['day']:12}{hm(r['recorded_minutes']):10}{aw_s:10}{delta:10}"
              f"{ratio:8}{r['recorded_source']}")
    if ratios:
        ratios.sort()
        mid = ratios[len(ratios) // 2]
        print(f"\n{len(ratios)} comparable day(s); median recorded/aw = {mid:.2f}")
        print("  that ratio is what a calibration factor would have to be derived FROM.")
    else:
        print("\nno day has both a recorded figure and AW presence; nothing to calibrate against")
    return 0


def cmd_backfill(a):
    from . import interactive as iv
    month = _month(a.month)
    with dbs.open_work() as conn:
        if not a.interactive:
            gaps = iv.pending_gaps(conn, month)
            days = iv.pending_days(conn, month)
            print(f"{len(gaps)} unclassified gap(s), {len(days)} unexplained working day(s)")
            for g in gaps:
                print(f"  gap  {g['attendance_day']}  {derive.hhmm(round(g['minutes']))}")
            for d in days:
                print(f"  day  {d['attendance_day']}  no session")
            if gaps or days:
                print("\nrun with --interactive to answer them")
            return 0
        rep = iv.run(conn, month)
    print(f"\n{rep['gaps_answered']} gap(s) and {rep['days_answered']} day(s) answered")
    return 0


def cmd_clockd(a):
    from . import clockd
    return clockd.main(stop_after=a.stop_after)


def cmd_clock(a):
    """Read the daemon's cache. Deliberately read-only: the cache is a view of the
    machine's state, and the figures still come from clock_event, never from here."""
    from . import clockd
    try:
        d = json.loads(clockd.CACHE.read_text())
    except (OSError, ValueError):
        print("clockd has not written a cache (not running?)", file=sys.stderr)
        return 1
    age = int(time.time()) - d.get("updated_unix", 0)
    print(f"{d['state']}  attributed to {d['attribution']}  (cache {age}s old)")
    p = d.get("presence") or {}
    print(f"  presence  {p.get('source','?')}"
          + ("  DEGRADED" if p.get("degraded") else "") + f"  {p.get('detail','')}")
    for pane, a in (d.get("agents") or {}).items():
        print(f"  {pane:10} {a['sub']:9} {a['status']:8} {a.get('ticket') or '-'}")
    return 0


def cmd_hotkey(a):
    """D4. `toggle` is what the keybind calls; the rest exist so a mistake is fixable."""
    with dbs.open_work() as conn:
        if a.action == "status":
            st = hotkey.state()
            if st["open"]:
                print(f"open {st['minutes']} min" + (f"  ({st['note']})" if st["note"] else ""))
            else:
                print("no manual interval open")
            return 0
        if a.action == "start":
            r = hotkey.start(a.note or "")
        elif a.action == "stop":
            r = hotkey.stop(conn, note=a.note or "")
        else:
            r = hotkey.toggle(conn, note=a.note or "")
    act = r["action"]
    if act == "started":
        print("started: the clock counts this interval whatever AW thinks")
    elif act == "already_open":
        print(f"already open {r['minutes']} min")
    elif act == "recorded":
        print(f"recorded {r['seconds'] // 60} min on {r['day']} "
              "(provenance hotkey, confidence 1.0)")
    elif act == "covered":
        # not a failure: the minutes were already counted once, and counting them twice
        # is the one thing v_day_span cannot survive -- it sums intervals, never merges
        print(f"covered: {r['why']}; {r['seconds'] // 60} min added nothing")
    elif act == "too_short":
        print(f"too_short: {r['seconds']}s is a mis-press, not an interval")
    else:
        print("not_open: nothing to stop")
    return 0


def cmd_attest(a):
    """The day the user signs off on, and the spool the enforcement layers write to."""
    month = _month(a.month)
    with dbs.open_work() as conn:
        rep = attest.drain(conn)
        if rep["written"] or rep["unattached"] or rep["bad"]:
            print(f"spool: {rep['written']} recorded, {rep['unattached']} unattachable, "
                  f"{rep['bad']} unreadable")
        if a.drain:
            return 0
        if a.day:
            days = [a.day]
        else:
            pend = attest.pending_days(conn, month)
            if not pend:
                print(f"{month}: every past working day with recorded time is signed off")
                return 0
            if not a.all:
                print(f"{len(pend)} day(s) awaiting sign-off:")
                for r in pend:
                    net = derive.hhmm(r["net_minutes"]) if r["net_minutes"] is not None else "-"
                    print(f"  {r['day']}  span {derive.hhmm(r['span_minutes'])}  net {net}"
                          f"  {r['provenance'] or '-'}")
                print("\nsign one off with --day YYYY-MM-DD, or review them all with --all")
                return 0
            days = [r["day"] for r in pend]
        for day in days:
            row = conn.execute(
                "SELECT span_minutes, deduction_minutes, net_minutes, target_minutes,"
                " unconfirmed, provenance FROM v_day_worked WHERE attendance_day=?",
                (day,)).fetchone()
            if not row:
                print(f"{day}: not classified; `timetrack seed` first", file=sys.stderr)
                return 1
            net = derive.hhmm(row["net_minutes"]) if row["net_minutes"] is not None else "-"
            print(f"\n{day}  span {derive.hhmm(row['span_minutes'])}  "
                  f"breaks {derive.hhmm(row['deduction_minutes'] or 0)}  net {net}  "
                  f"target {derive.hhmm(row['target_minutes'])}  [{row['provenance'] or '-'}]")
            if row["unconfirmed"]:
                print(f"  !! {row['unconfirmed']} unconfirmed gap(s): the net figure is a guess")
            verdict = a.verdict
            if not verdict:
                try:
                    reply = input("  sign off? [y]es / [n]o-dispute / [s]kip: ").strip().lower()
                except EOFError:
                    reply = "s"
                verdict = {"y": "confirmed", "n": "disputed"}.get(reply[:1] or "s")
            if not verdict:
                print("  skipped")
                continue
            attest.confirm(conn, day, verdict)
            print(f"  {day} {verdict}")
    return 0


def cmd_panic(a):
    """Layer 3. A convenience around `touch`; the file is the interface, not this."""
    if a.state == "status":
        print("PANIC engaged: enforcement off, collection continues" if config.panic()
              else "PANIC not set: enforcement active")
        return 0
    if a.state == "on":
        config.PANIC.parent.mkdir(parents=True, exist_ok=True)
        config.PANIC.touch()
        print(f"engaged {config.PANIC}\n  every enforcement path stands down; "
              "timetrack-deadman reaps any panel on screen within 30s")
    else:
        try:
            config.PANIC.unlink()
        except FileNotFoundError:
            pass
        print("released: enforcement active again")
    return 0


def cmd_journald(a):
    from .backfill import journald
    month = _month(a.month)
    with dbs.open_work(readonly=not a.clip) as conn:
        rows = journald.audit(conn, month)
        print(f"{'day':12}{'recorded':10}{'impossible':12}{'conf':6}source")
        bad = 0
        for r in rows:
            flag = ""
            if r["offline_minutes"] > 0:
                bad += 1
                flag = "  <-- machine was off"
            unk = f" ({r['unknowable']} unknowable)" if r["unknowable"] else ""
            print(f"{r['day']:12}{derive.hhmm(r['span_minutes']):10}"
                  f"{derive.hhmm(r['offline_minutes']):12}{r['confidence'] or '-':<6}"
                  f"{r['provenance']}{unk}{flag}")
        print(f"\n{len(rows)} day(s) checked, {bad} with time the machine was not running")
        if a.clip:
            done = journald.clip(conn, month)
            # confidence 1.0 is the user's own attestation; a contradiction there is a
            # question for them, not a subtraction to make quietly
            print(f"clipped {len(done)} interval(s) from reconstructed sources; "
                  "confidence 1.0 left untouched")
    return 0


def cmd_status(a):
    month = _month(a.month)
    with dbs.open_work(readonly=True) as conn:
        s = derive.month_summary(conn, month)
    hm = derive.hhmm
    print(f"{month}  ruleset {s['ruleset']}  as at {s['today']}  basis {s['basis']}")
    print(f"  target            {hm(s['target_minutes'])} over {s['working_days']} working days")
    print(f"  worked to date    {hm(s['worked_minutes_to_date'])} "
          f"against {hm(s['owed_to_date_minutes'])} owed over "
          f"{s['elapsed_working_days']} elapsed day(s)")
    print(f"  span (gross)      {hm(s['span_minutes'])} before breaks")
    if s["days_unconfirmed_breaks"]:
        print(f"  !! {s['days_unconfirmed_breaks']} day(s) have UNCONFIRMED breaks "
              f"({', '.join(s['unconfirmed_break_days'][:4])}); those gaps are guesses")
    if s["days_missing_breaks"]:
        # say it plainly rather than quietly reporting a span as if it were net
        print(f"  !! {s['days_missing_breaks']} day(s) have no break recorded; "
              f"their span is counted as-is and OVERSTATES the net figure")
    print(f"  shortfall to date {hm(s['shortfall_to_date_minutes'])}"
          + (f"  = {s['currency']} {s['money_shortfall_to_date']:,.0f}"
             if s["money_shortfall_to_date"] is not None else ""))
    if s["remaining_working_days"]:
        print(f"  still needed      {hm(s['still_needed_minutes'])} "
              f"= {hm(s['still_needed_per_day_minutes'])}/day over "
              f"{s['remaining_working_days']} day(s)")
    print(f"  projected         {hm(s['projected_minutes'])} "
          f"(short {hm(s['projected_shortfall_minutes'])})")
    if s["money_projected"] is not None:
        print(f"  value at risk     {s['currency']} {s['money_projected']:,.0f}")
    print(f"  sources           {' + '.join(s['provenance']) or 'none'}")
    return 0


def cmd_doctor(a):
    """Exit 1 on any fail. A warn alone exits 0 -- it is worth saying, not worth blocking."""
    results = doctor.run(month=a.month)
    mark = {"ok": "ok  ", "warn": "WARN", "fail": "FAIL"}
    for r in results:
        print(f"  {mark[r['status']]}  {r['check']:22} {r['detail']}")
        if r["fix"] and r["status"] != "ok":
            print(f"        -> {r['fix']}")
    bad = sum(1 for r in results if r["status"] == "fail")
    warn = sum(1 for r in results if r["status"] == "warn")
    print(f"\n{len(results)} checks, {bad} failed, {warn} warned")
    return 1 if bad else 0


def cmd_submit(a):
    """Freeze the month. Deliberately interactive unless --yes: this is a claim to an
    employer, and the one command here that cannot be undone."""
    month = _month(a.month)
    with dbs.open_work() as conn:
        prior = submission.existing(conn, month)
        if prior and not a.show:
            print(f"timetrack: {month} already submitted "
                  f"({derive.hhmm(prior['worked_minutes'])}, basis {prior['basis']}, "
                  f"digest {prior['input_digest'][:12]})", file=sys.stderr)
            return 1
        if a.show:
            if not prior:
                print(f"{month}: not submitted")
                return 0
            for k, v in prior.items():
                print(f"  {k:16} {v}")
            return 0
        try:
            results = submission.preflight(month)
        except submission.Refused as e:
            print(f"timetrack: refused\n  {e}", file=sys.stderr)
            return 1
        warns = [r for r in results if r["status"] == "warn"]
        s = derive.month_summary(conn, month)
        print(f"About to freeze {month}:")
        print(f"  worked   {derive.hhmm(s['worked_minutes'])} on basis {s['basis']}")
        print(f"  target   {derive.hhmm(s['target_minutes'])}")
        print(f"  delta    {derive.hhmm(s['worked_minutes'] - s['target_minutes'])}")
        for w in warns:
            print(f"  WARN     {w['check']}: {w['detail']}")
        if not a.yes:
            # a basis of net? means some deduction on some day is still a guess
            print("\nThis row is immutable and cannot be rewritten. Re-run with --yes.")
            return 1
        try:
            row, _s, _w = submission.freeze(conn, month)
        except submission.Refused as e:
            print(f"timetrack: refused\n  {e}", file=sys.stderr)
            return 1
    print(f"frozen {row['month']}: {derive.hhmm(row['worked_minutes'])} "
          f"basis {row['basis']} ruleset {row['ruleset']}")
    print(f"  digest {row['input_digest']}")
    print(f"  export {row['export_path']}")
    return 0


def cmd_verify(a):
    month = _month(a.month)
    with dbs.open_work(readonly=True) as conn:
        try:
            v = submission.verify(conn, month)
        except submission.Refused as e:
            print(f"timetrack: {e}", file=sys.stderr)
            return 1
    f, hm = v["frozen"], derive.hhmm
    print(f"{month} submitted {date.fromtimestamp(f['submitted_unix']).isoformat()}")
    print(f"  frozen    {hm(f['worked_minutes'])}  basis {f['basis']}  ruleset {f['ruleset']}")
    print(f"  today     {hm(v['current_worked'])}  basis {v['current_basis']}  "
          f"ruleset {v['current_ruleset']}")
    if not (v["inputs_changed"] or v["figure_changed"] or v["ruleset_changed"]):
        print("  unchanged since submission")
        return 0
    # drift is expected the moment a gap is classified; it must be visible, not fatal
    if v["inputs_changed"]:
        print(f"  INPUTS CHANGED  {f['input_digest'][:12]} -> {v['current_digest'][:12]}")
    if v["ruleset_changed"]:
        print(f"  RULESET CHANGED {f['ruleset']} -> {v['current_ruleset']}")
    if v["figure_changed"]:
        print(f"  FIGURE DRIFT    {hm(v['drift_minutes'])} against what was submitted")
    print("  the frozen row is what was handed over; this is the difference, not an error")
    return 0


def cmd_export(a):
    month = _month(a.month)
    with dbs.open_work(readonly=True) as conn:
        summary, days, s = export_csv.write(conn, month, out_dir=a.out)
    print(f"{summary}\n{days}")
    print(f"  {s['working_days']} working days, worked "
          f"{derive.hhmm(s['worked_minutes_to_date'])} ({s['basis']}), short "
          f"{derive.hhmm(s['shortfall_to_date_minutes'])} to date")
    return 0


def cmd_days(a):
    month = _month(a.month)
    with dbs.open_work(readonly=True) as conn:
        rows = export_csv.day_table(conn, month)
    wide = [r for r in rows if r["day_type"] == "working"]
    print(f"{'date':12}{'in':7}{'out':7}{'span':8}{'brk':7}{'net':8}{'src':16}conf")
    for r in wide:
        print(f"{r['date']:12}{r['login']:7}{r['logout']:7}{r['span_hhmm']:8}"
              f"{r['break_hhmm']:7}{r['net_hhmm']:8}{r['source'][:15]:16}{r['confidence']}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="timetrack", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("migrate", help="create or upgrade the databases").set_defaults(fn=cmd_migrate)

    s = sub.add_parser("seed", help="classify a month's days (working/weekend/holiday)")
    s.add_argument("--month", help="YYYY-MM, default this month")
    s.set_defaults(fn=cmd_seed)

    s = sub.add_parser("import-sheet", help="import the hand-kept timesheet CSV")
    s.add_argument("path")
    s.set_defaults(fn=cmd_import_sheet)

    s = sub.add_parser("backfill-git", help="reconstruct sessions from commit times")
    s.add_argument("--since", required=True)
    s.add_argument("--until", required=True)
    s.set_defaults(fn=cmd_backfill_git)

    s = sub.add_parser("ingest-aw", help="write AW-derived sessions for days with none")
    s.add_argument("--no-refresh", action="store_true",
                   help="do not replace today's own AW session (default is to refresh it)")
    s.set_defaults(fn=cmd_ingest_aw)

    s = sub.add_parser("web", help="browser time per site and ticket (local, private.db)")
    s.add_argument("--day", help="YYYY-MM-DD (default: today)")
    s.add_argument("--all", action="store_true", help="every day the web bucket covers")
    s.add_argument("--top", type=int, default=12, help="visits to print per day")
    s.add_argument("--no-llm", action="store_true", help="rules only; skip the local model")
    s.set_defaults(fn=cmd_web)

    s = sub.add_parser("term", help="what terminal time went on, by pane (local, private.db)")
    s.add_argument("--day", help="YYYY-MM-DD (default: today)")
    s.add_argument("--all", action="store_true", help="every day the focus log or window bucket covers")
    s.add_argument("--top", type=int, default=12, help="groups to print per day")
    s.add_argument("--no-llm", action="store_true", help="rules and cache only; skip the local model")
    s.set_defaults(fn=cmd_term)

    s = sub.add_parser("away", help="D7: declare or ask what an away gap was (watcher)")
    s.add_argument("--declare", metavar="REASON", help="Super+Esc: record why you are leaving")
    s.add_argument("--prayer", action="store_true", help="the prayer whose iqamah is near now")
    s.set_defaults(fn=cmd_away)

    s = sub.add_parser("compare-aw", help="cross-validate recorded days against AW presence")
    s.add_argument("--month")
    s.set_defaults(fn=cmd_compare_aw)

    s = sub.add_parser("backfill", help="list or answer the days that need a human")
    s.add_argument("--month")
    s.add_argument("--interactive", action="store_true", help="prompt for each one")
    s.set_defaults(fn=cmd_backfill)

    s = sub.add_parser("clockd", help="run the live clock daemon (foreground)")
    s.add_argument("--stop-after", type=int, help="exit after N seconds (testing)")
    s.set_defaults(fn=cmd_clockd)

    s = sub.add_parser("clock", help="show what the daemon currently believes")
    s.set_defaults(fn=cmd_clock)

    s = sub.add_parser("hotkey", help="open or close a manual work interval (D4)")
    s.add_argument("action", nargs="?", default="toggle",
                   choices=["toggle", "start", "stop", "status"])
    s.add_argument("--note", help="what it was; stored locally, never exported")
    s.set_defaults(fn=cmd_hotkey)

    s = sub.add_parser("attest", help="sign off a day's figure; drain the enforcement spool")
    s.add_argument("--month")
    s.add_argument("--day", help="YYYY-MM-DD to review")
    s.add_argument("--all", action="store_true", help="review every pending day")
    s.add_argument("--drain", action="store_true", help="only record spooled attestations")
    s.add_argument("--verdict", choices=["confirmed", "disputed"],
                   help="answer without prompting")
    s.set_defaults(fn=cmd_attest)

    s = sub.add_parser("panic", help="disable all enforcement (collection continues)")
    s.add_argument("state", nargs="?", default="status", choices=["on", "off", "status"])
    s.set_defaults(fn=cmd_panic)

    s = sub.add_parser("journald", help="check recorded time against boot windows")
    s.add_argument("--month")
    s.add_argument("--clip", action="store_true",
                   help="remove impossible intervals from reconstructed sources only")
    s.set_defaults(fn=cmd_journald)

    s = sub.add_parser("status", help="where the month stands")
    s.add_argument("--month")
    s.set_defaults(fn=cmd_status)

    s = sub.add_parser("days", help="per-day table for a month")
    s.add_argument("--month")
    s.set_defaults(fn=cmd_days)

    s = sub.add_parser("doctor", help="check every invariant; exit 1 on failure")
    s.add_argument("--month")
    s.set_defaults(fn=cmd_doctor)

    s = sub.add_parser("submit", help="freeze the month immutably (requires --yes)")
    s.add_argument("--month")
    s.add_argument("--yes", action="store_true", help="actually write the row")
    s.add_argument("--show", action="store_true", help="print the frozen row and exit")
    s.set_defaults(fn=cmd_submit)

    s = sub.add_parser("verify", help="compare a frozen figure against today's derivation")
    s.add_argument("--month")
    s.set_defaults(fn=cmd_verify)

    s = sub.add_parser("export", help="write the submission CSVs")
    s.add_argument("--month")
    s.add_argument("--out", type=Path,
                   help="output directory, default the vault's exports/")
    s.set_defaults(fn=cmd_export)

    from . import health, login, salah, vault
    salah.add_parser(sub)
    health.add_parser(sub)
    login.add_parser(sub)
    vault.add_parser(sub)

    a = p.parse_args(argv if argv is not None else sys.argv[1:])
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
