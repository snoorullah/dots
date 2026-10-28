"""The daily brief: COMPANY work only, written once a day to REPORT_DIR/YYYY-MM-DD.md.

What goes in: tasks whose project is in WORK_PROJECTS, or src erp, or src gh inside
WORK_GH_ORG / WORK_GH_REPOS, plus the total worked time and the per-ticket clock.
What never goes in: personal items, app-level activity, idle or away time.

No network, by construction: this module reads Taskwarrior and work.db and nothing else.
tests/report.sh runs it with HTTP_PROXY pointing at a dead port and GH_TOKEN unset.
"""
import re
import time
from datetime import date, datetime, timedelta

from . import atomic, local_tt, task, tw

EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
MAX_OPEN = 10


def scrub(s, cfg=None):
    """Titles are free text. The floor is the EMAIL scrub, which nothing can switch off.

    work.conf REDACT_WORDS adds words on top (case-insensitive, with the rest of the token);
    no word is written in this public repo.
    """
    s = EMAIL.sub("[email]", s or "")
    for w in getattr(cfg, "redact_words", None) or []:
        s = re.sub(re.escape(w) + r"\S*", "[redacted]", s, flags=re.I)
    return s


def dur(sec):
    sec = int(sec)
    h, m = sec // 3600, sec % 3600 // 60
    if h and m:
        return f"{h}h {m:02d}m"
    return f"{h}h" if h else (f"{m}m" if m else "")


def _line(i, t, secs, cfg=None):
    ref = f"`{t['ref']}` " if t.get("ref") else ""
    tail = f" — {dur(secs)}" if secs else ""
    return ref, f"{i}. {ref}{scrub(t.get('desc', ''), cfg)[:100]}{tail}"


def build(day, cfg, now=None):
    now = int(now or time.time())
    t0, t1 = local_tt.day_bounds(day, now)      # the day is its session: login -> logout (or now)
    times = dict(local_tt.ref_seconds(t0, t1))
    worked = local_tt.worked_sec(t0, t1, now)
    pend = [t for t in tw.pending() if cfg.is_work_task(t)]
    done = [t for t in tw.completed_since(t0 - 1) if cfg.is_work_task(t) and t0 <= (t.get("end_ts") or 0) <= t1]
    done.sort(key=lambda t: t.get("end_ts") or 0)
    still = [t for t in pend if t.get("start_ts") or t.get("ref") in times or "attn" in (t.get("tags") or [])][:MAX_OPEN]

    def section(title, rows):
        out = [f"## {title}"]
        if not rows:
            return out + ["Nothing.", ""]
        for i, t in enumerate(rows, 1):
            line = _line(i, t, times.get(t.get("ref")), cfg)[1]
            if (t.get("srcstate") or "").endswith(":reviewed"):
                line += " — review submitted"
            elif t in still and "attn" in (t.get("tags") or []) and t.get("src") in ("gh", "erp"):
                line += ", waiting on me"
            out.append(line)
        return out + [""]

    lines = [f"# {day.isoformat()}", "",
             f"Worked {dur(worked) or '0m'} · {len(done)} items closed · {len(still)} still open", "", "---", ""]
    lines += section("Closed today", done) + section("Still open", still)
    # Work an agent started with no ticket (dots-task new): local tasks the user promotes later.
    # Only company-project tasks, like every other section; the exemption count is a bare number.
    logged = [t for t in pend if cfg.is_work_task(t) and t.get("src") == "claude" and "claude" in (t.get("tags") or [])
              and (t.get("ref") or "").startswith("local:")][:MAX_OPEN]
    exempt = sum(1 for r in task.read_log(t0, t1) if r.get("kind") == "none")
    if logged or exempt:
        lines += ["## Agent work logged as new local tasks"]
        lines += [f"{i}. `{t['ref']}` {scrub(t.get('desc', ''), cfg)[:100]}" for i, t in enumerate(logged, 1)] or ["Nothing."]
        if logged:
            lines += ["Promote with `dots-task promote <local-ref> <ref>`."]
        if exempt:
            lines += [f"Exemptions: {exempt} session(s) declared no task."]
        lines += [""]
    titles = {t["ref"]: t.get("desc", "") for t in pend + done if t.get("ref")}
    rows = [f"| `{scrub(ref, cfg)}` | {scrub(titles.get(ref, ''), cfg)[:60]} | {dur(sec)} |"
            for ref, sec in sorted(times.items(), key=lambda kv: -kv[1])[:15] if dur(sec)]
    if rows:                              # an empty table is noise
        lines += ["## Time by item", "| ref | title | time |", "|---|---|---|"] + rows
    return "\n".join(lines) + "\n"


def write(day, cfg, reason=None, now=None):
    """Write the brief. Returns 'created', 'unchanged', 'updated' or 'skipped'."""
    path = cfg.report_dir / f"{day.isoformat()}.md"
    exists = path.exists()
    if reason == "nightly" and exists:
        return "skipped"             # the logout brief already ran; the fallback must not redo it
    text = build(day, cfg, now)
    if exists and path.read_text(encoding="utf-8") == text:
        return "unchanged"
    cfg.report_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    atomic.write_text(path, text, 0o600)
    return "updated" if exists else "created"


def parse_day(s):
    today = local_tt.workday(time.time())   # the session's day: a logout at 01:00 briefs that evening
    if not s or s == "today":
        return today
    if s == "yesterday":
        return today - timedelta(days=1)
    return datetime.strptime(s, "%Y-%m-%d").date()
