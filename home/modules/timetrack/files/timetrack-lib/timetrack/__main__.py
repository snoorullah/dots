"""timetrack CLI: rollup | note | sync | all."""
import sys
from datetime import datetime, timedelta, time
from . import config, sources, categorize, db as dbmod, rollup, note, sync

def _today_window():
    now = datetime.now()
    day = config.logical_date(now)
    start = datetime.combine(day, time(config.DAY_BOUNDARY_HOUR))
    return day, start, start + timedelta(days=1)

def _web_bucket():
    """Resolve the aw-watcher-web bucket: config.WEB_BUCKET if set, else auto-detect
    via sources.list_aw_buckets() (first bucket whose name contains "web"); None if
    neither — the web rollup stays inert until the extension is installed."""
    if config.WEB_BUCKET:
        return config.WEB_BUCKET
    return next((b for b in sources.list_aw_buckets() if "web" in b.lower()), None)

def _do_rollup():
    day, start, end = _today_window()
    d = dbmod.open_db()
    rules = categorize.load_rules()
    si, ei = start.astimezone().isoformat(), end.astimezone().isoformat()
    rollup.rollup_raw(d, day,
        tasks=sources.read_tasks(), intervals_=sources.read_intervals(),
        window_events=sources.read_aw_events(sources.WINDOW_BUCKET, si, ei),
        afk_events=sources.read_aw_events(sources.AFK_BUCKET, si, ei),
        logind=sources.read_logind(), rules=rules)
    web_bucket = _web_bucket()
    if web_bucket:
        rollup.rollup_web(d, day, sources.read_aw_events(web_bucket, si, ei), rules)
    rollup.rollup_derived(d, day, rules)
    return d, day

def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv[0] if argv else "all"
    if cmd not in ("rollup", "note", "sync", "all"):
        print("usage: timetrack rollup|note|sync|all", file=sys.stderr)
        return 2
    if cmd in ("rollup", "all"):
        d, day = _do_rollup()
    if cmd in ("note", "all"):
        d = dbmod.open_db(); day = config.logical_date(datetime.now())
        note.write(d, day)
    if cmd in ("sync", "all"):
        sync.push()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
