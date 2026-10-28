"""dots-overview: the command line.

Fast cycle (60 s, local only):  ingest / local / attention, or all three as `fast`.
Slow cycle (hourly, network):   sync + detect, run by the dots-ops job `overview-sync`.

Each stage is wrapped on its own, so a failing source degrades ONE file's contents (and
adds a line to meta.json) instead of stopping the other five from being written.
"""
import argparse
import sys
import time

from . import (activity, atomic, attention, breakdown, config, detect, doctor, heatmap, herdr, ingest, jump,
               local_tt, names, nowstate, report, sync, tw)

OUT = {"now": "now.json", "activity": "activity.json", "attention": "attention.json",
       "heatmap": "heatmap.json", "mirror": "mirror.json", "meta": "meta.json"}


def _put(name, doc):
    atomic.write_json(config.STATE_DIR / OUT[name], doc)


def _stage(errors, source, fn, default=None):
    try:
        return fn()
    except (tw.TwError, OSError, ValueError, KeyError, SystemExit) as e:
        errors.append({"source": source, "msg": f"{type(e).__name__}: {e}"[:140]})
        return default


def write_meta(cycle, errors, started):
    now = int(time.time())
    _put("meta", {"v": 1, "generatedAt": now, "generationMs": int((time.monotonic() - started) * 1000),
                  "writer": config.WRITER, "schema": config.VERSION, "cycle": cycle, "errors": errors})


def cmd_fast(args, stages=("ingest", "local", "attention")):
    started, errors = time.monotonic(), []
    live = _stage(errors, "herdr", herdr.snapshot)
    pend = _stage(errors, "task", tw.pending, [])
    if "ingest" in stages:
        r = _stage(errors, "ingest", lambda: ingest.run(live=live), {"created": 0, "updated": 0})
        if r and (r["created"] or r["updated"]):
            pend = _stage(errors, "task", tw.pending, pend)
        _put("now", nowstate.build(pend, live, local_tt.clock_state()))
    if "local" in stages:
        done = _stage(errors, "task", activity.completed, [])
        _put("activity", activity.build(done, pend, apps=getattr(args, "apps", "today")))
        _put("heatmap", heatmap.build(done))
    if "attention" in stages:
        _put("attention", attention.build(pend, live))
    write_meta("fast", errors, started)
    return 0


def cmd_sync(args):
    cfg = config.Work()
    started, errors = time.monotonic(), []
    out = _stage(errors, "sync", lambda: sync.run(cfg, erp_mcp=args.erp_mcp))
    if out:
        errors += out[2]
        print(f"sync: {out[0]} new mirror task(s); " + ", ".join(f"{k}={v['state']}" for k, v in out[1].items()))
    _put("mirror", _stage(errors, "mirror", lambda: sync.mirror_doc(int(time.time())), {"v": 1, "ts": int(time.time()), "refs": []}))
    write_meta("slow", errors, started)
    return 1 if any(e["source"] in ("sync", "task") for e in errors) else 0


def cmd_detect(args):
    cfg = config.Work()
    started, errors = time.monotonic(), []
    out = _stage(errors, "detect", lambda: detect.run(cfg))
    if out:
        closed, status = out
        for name, st in status.items():
            if st["state"] == "stale":
                errors.append({"source": name, "msg": st["detail"] or "unreachable"})
        print(f"detect: {len(closed)} closed")
        merged = sync.last_status()
        merged.update(status)
        atomic.write_json(config.STATE_DIR / sync.STATUS, {"v": 1, "ts": int(time.time()), "sources": merged})
    # order matters: srcstate and `task done` (inside detect.run) are already written
    _put("mirror", _stage(errors, "mirror", lambda: sync.mirror_doc(int(time.time())), {"v": 1, "ts": int(time.time()), "refs": []}))
    write_meta("slow", errors, started)
    return 0


def cmd_report(args):
    cfg = config.Work()
    day = report.parse_day(args.date)
    res = report.write(day, cfg, reason=args.reason)
    print(f"report {day.isoformat()}: {res}")
    return 0


def cmd_breakdown(args):
    r = breakdown.run(args.ref, start=args.start)
    print(f"breakdown {args.ref}: {len(r['steps'])} step(s)" + (" (fallback)" if r["fallback"] else "") +
          (f", started {r['started'][:8]}" if r["started"] else ""))
    return 0


def cmd_jump(args):
    tasks = jump.load_tasks()
    t = jump.last_session(tasks) if args.last else jump.resolve(args.target, tasks)
    if t is None:
        print("dots-jump: nothing matches", file=sys.stderr)
        return 1
    mode = "resume" if args.resume else "open" if args.open else None
    out = jump.go(t, mode, dry=args.dry_run)
    if out:
        print(out)
    return 0


def cmd_doctor(args):
    res = doctor.check()
    for lvl, msg in res:
        print(f"{lvl:4} {msg}")
    lvl, summary = doctor.summarize(res)
    print(f"{lvl}: {summary}")
    return 0 if lvl == "ok" else 1


def cmd_focus(args):
    st = nowstate.focus_cmd(args.action, args.minutes, args.zone)
    print(st["state"])
    return 0


def cmd_notifylog(args):
    from . import notifylog
    return notifylog.main()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="dots-overview", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, help_):
        p = sub.add_parser(name, help=help_)
        p.set_defaults(fn=fn)
        return p

    add("fast", cmd_fast, "ingest + local + attention in one process (the 60 s timer)").add_argument(
        "--apps", choices=["today", "all"], default="today", help="'all' also refreshes week/month/quarter app totals")
    add("ingest", lambda a: cmd_fast(a, ("ingest",)), "sessions + herdr + taskwarrior -> tasks, now.json")
    add("local", lambda a: cmd_fast(a, ("local",)), "timetrack/AW/taskwarrior -> activity.json, heatmap.json")
    add("attention", lambda a: cmd_fast(a, ("attention",)), "all sources -> attention.json")
    p = add("sync", cmd_sync, "GitHub + ERP -> mirror tasks, mirror.json (slow, network)")
    p.add_argument("--erp-mcp", action="store_true", help="allow ERP_MODE=mcp (spends tokens)")
    add("detect", cmd_detect, "completion detectors -> task done, srcstate (slow, network)")
    p = add("report", cmd_report, "write the daily brief")
    p.add_argument("--date", help="YYYY-MM-DD, today or yesterday (default today)")
    p.add_argument("--reason", choices=["logout", "nightly"], help="nightly is a no-op when the brief exists")
    p = add("breakdown", cmd_breakdown, "local llm -> subtasks, optionally start the first")
    p.add_argument("ref")
    p.add_argument("--start", action="store_true")
    p = add("jump", cmd_jump, "focus the pane / open the url for a ref, agent or task id")
    p.add_argument("target", nargs="?")
    p.add_argument("--last", action="store_true")
    p.add_argument("--resume", action="store_true")
    p.add_argument("--open", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    add("doctor", cmd_doctor, "check invariants; non-zero exit means look")
    p = add("focus", cmd_focus, "persist the focus timer state")
    p.add_argument("action", choices=["start", "stop", "break"])
    p.add_argument("--minutes", type=int)
    p.add_argument("--zone")
    add("notifylog", cmd_notifylog, "eavesdrop on notifications into notifications.jsonl (foreground)")
    p = add("name", lambda a: print(names.for_session(a.sess)) or 0, "the agent name for a session id")
    p.add_argument("sess")

    args = ap.parse_args(argv)
    if args.cmd == "jump" and not (args.target or args.last):
        ap.error("jump needs a target or --last")
    try:
        return args.fn(args)
    except (tw.TwError, SystemExit) as e:
        if isinstance(e, SystemExit) and not isinstance(e.code, str):
            raise
        print(f"dots-overview {args.cmd}: {e}", file=sys.stderr)
        return 1
