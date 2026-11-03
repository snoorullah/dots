"""dots-overview: the command line.

Fast cycle (60 s, local only):  ingest / local / attention, or all three as `fast`.
Slow cycle (hourly, network):   sync + detect, run by the dots-ops job `overview-sync`.

Each stage is wrapped on its own, so a failing source degrades ONE file's contents (and
adds a line to meta.json) instead of stopping the other five from being written.
"""
import argparse
import sys
import time

from . import (activity, atomic, attention, breakdown, config, detect, doctor, gate, heatmap, herdr, ingest, jump,
               local_tt, names, nowstate, report, sync, task, tw)

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


def cmd_alert_task(args):
    from . import alertpr
    print(alertpr.create(args.name, args.project, args.prep, args.repo, args.test)["ref"])
    return 0


def _alert_dir(ref):
    from . import alertrun
    d = alertrun.run_dir(ref)
    if not (d / "meta.json").exists():
        raise SystemExit(f"no alert run for {ref}; click Fix first")
    return d


def _say(summary, body=""):
    """A desktop note: these commands run detached from a button, so stderr is invisible."""
    import subprocess
    try:
        subprocess.Popen(["notify-send", "-a", "Overview", "--", summary, body[:300]], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def cmd_alert_review(args, herdr_run=None, say=None):
    """Stop the agent, extract its patch from a host-made copy (host code, refuses anything
    forbidden), then open a read-only view in a pane. Marks the patch reviewed ONLY once that view
    is open. Pushes nothing."""
    from . import alertpush, alertrun, herdr, launch
    herdr_run, say = herdr_run or herdr.run, say or _say
    d = _alert_dir(args.ref)
    if not alertrun.stop_agent(d, herdr_run):
        say(f"Review {args.ref}: agent still running", "Could not confirm the agent exited; nothing was extracted.")
        print("the agent is still running; not extracting", file=sys.stderr)
        return 1
    try:
        r = alertrun.extract(d)
    except alertrun.Refused as e:
        text = "PATCH REFUSED\n" + "\n".join(f"- {alertrun.plain(why, 300)}" for why in e.args[0]) + \
            "\n\nNothing can be pushed from this run until the cause is gone and review is run again.\n"
        (d / "review.txt").write_text(text, encoding="utf-8")
        say(f"Patch refused for {args.ref}", "; ".join(e.args[0])[:250])
        launch.open_review(d)
        print(text, file=sys.stderr)
        return 1
    if r.get("empty"):
        say(f"{args.ref}: the agent changed nothing", "")
        print("the agent changed nothing")
        return 0
    m = alertrun.meta(d)
    body = alertpush.body_for(m, alertrun.read_snapshot(d, m["proposal_sha256"]))
    (d / "review.txt").write_text(alertrun.review_text(d, body), encoding="utf-8")
    status = launch.open_review(d)
    if not status.startswith("review open"):
        say(f"Review {args.ref}: no pane opened", status[:200])
        print(status, file=sys.stderr)
        return 1                              # not marked reviewed: Push stays hidden
    alertrun.mark_reviewed(d)
    print(status)
    return 0


def _confirm(summary, body):
    """One notification with a Push button; True only if it was clicked."""
    import subprocess
    try:
        p = subprocess.run(["notify-send", "-a", "Overview", "-t", "60000", "-A", "push=Push", "--wait", "--", summary, body],
                           capture_output=True, text=True, timeout=75, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return False
    return p.stdout.strip() == "push"


def cmd_alert_push(args, confirm=None):
    """The separate, explicit click: confirm the reviewed sha, push, open a DRAFT PR."""
    from . import alertpush, alertrun
    d = _alert_dir(args.ref)
    m = alertrun.meta(d)
    if not (confirm or _confirm)(f"Push {args.ref} and open a draft PR?",
                                 f"patch {str(m.get('patch_sha256'))[:12]}  files: {', '.join(m.get('files') or [])}"):
        print("not confirmed; nothing pushed", file=sys.stderr)
        return 1
    try:
        print(alertpush.push(d, confirmed=True))
    except alertpush.PushError as e:
        _say(f"Not pushed: {args.ref}", str(e))
        print(f"not pushed: {e}", file=sys.stderr)
        return 1
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
    # the bar reads now.json, which the fast cycle rewrites only once a minute: rewrite it here
    # so a keypress shows on the bar at once, not up to 60 s later
    errors = []
    live = _stage(errors, "herdr", herdr.snapshot)
    pend = _stage(errors, "task", tw.pending, [])
    _put("now", nowstate.build(pend, live, local_tt.clock_state()))
    print(st["state"])
    return 0


def cmd_notifylog(args):
    from . import notifylog
    return notifylog.main()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv[:1] == ["task"]:             # dots-task has its own parser; keep --help and flags out of this one
        return task.main(argv[1:])
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
    p = add("alert-task", cmd_alert_task, "local task for an alert (dots-inbox Create ticket); prints its ref")
    p.add_argument("--name", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--prep", required=True, help="the prepared analysis (markdown)")
    p.add_argument("--repo", help="local checkout the fix is made from; without it nothing is prepared")
    p.add_argument("--test", help="the one command the agent runs to check its fix")
    p = add("alert-review", cmd_alert_review, "extract the agent's patch and open it read-only; pushes nothing")
    p.add_argument("ref")
    p = add("alert-push", cmd_alert_push, "push the reviewed patch and open a DRAFT PR (a separate click)")
    p.add_argument("ref")
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
    p = add("task", lambda a: task.main(a.rest), "dots-task: declare the task this Claude session works on")
    p.add_argument("rest", nargs=argparse.REMAINDER)
    p = add("task-hook", lambda a: gate.main(a.event), "Claude Code hook: the task gate (see dots-task-hook)")
    p.add_argument("event", choices=["session", "prompt", "pretool", "stop"])
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
