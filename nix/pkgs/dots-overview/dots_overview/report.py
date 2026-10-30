"""The daily brief: COMPANY work only, written once a day to REPORT_DIR/YYYY-MM-DD.md.

What goes in: tasks whose project is in WORK_PROJECTS, or src erp, or src gh inside
WORK_GH_ORG / WORK_GH_REPOS, plus the total worked time and the per-ticket clock.
What never goes in: personal items, app-level activity, idle or away time.

The only network is the PRs section: read-only `gh search prs` / `gh api user` (sources_gh.run,
the same seam the sync uses). Offline or no gh, that section says "unavailable" and the rest renders.
Everything else reads Taskwarrior and timetrack's databases (mode=ro) and nothing else. The
Timesheet day notes are never touched: this is its own file.
"""
import json
import re
import time
from datetime import date, datetime, timedelta

from . import atomic, local_tt, sources_gh, task, tw

EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
MAX_OPEN = 10
MAX_PRS = 15
PR_FIELDS = "number,title,url,repository,state,author"
PR_LIMIT = 30
UNAVAILABLE = "unavailable (gh offline or not signed in)"
PENDING = "pending (asking gh)"
TICKET = re.compile(r"^[A-Za-z][A-Za-z0-9]*(?:-\d+)+$")     # HD-123, TASK-2026-00561


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


def _work(ref, project, src, cfg):
    if src is None:       # only a ticket-shaped ref is ERP; a stray ref falls back to the project alone
        src = "gh" if (ref or "").startswith("gh:") else ("erp" if TICKET.match(ref or "") else None)
    return cfg.is_work_task({"ref": ref, "project": project, "src": src})


def attention(day, cfg, tasks):
    """{key: [you, in agent pane, browser]} of terminal and browser seconds, company only.

    key is a ticket ref, or "No ticket: <project>" for work-project time with no ticket.
    'In agent pane' is the human focused on a pane an agent ran in, or a delegated verdict; unproductive time is not an outcome."""
    by_uuid = {t["uuid"]: t for t in tasks if t.get("uuid")}
    acc = {}

    def add(ref, project, src, col, sec):
        if not _work(ref, project, src, cfg):
            return
        key = ref or f"No ticket: {project}"
        acc.setdefault(key, [0, 0, 0])[col] += sec

    for g in local_tt.term_day(day):
        if g["verdict"] == "unproductive":
            continue
        t = by_uuid.get(g["task_uuid"]) or {}
        add(g["ref"] or t.get("ref") or "", g["project"] or t.get("project") or "", t.get("src"),
            1 if g["agent"] or g["verdict"] == "delegated" else 0, g["sec"])
    for ticket, sec in local_tt.web_ticket_day(day).items():
        add(ticket, "", None, 2, sec)
    return {k: v for k, v in acc.items() if sum(v) >= 60}


def _prs(day, cfg, sleep=time.sleep):
    """{'opened': [...], 'merged': [...], 'reviewed': [...], 'truncated': set} of company PRs, or None when gh fails."""
    d = day.isoformat()
    try:
        if not sources_gh.quota_ok():
            return None
        me = sources_gh.whoami()
        queries = [("opened", ["--author=@me", f"--created={d}"]),
                   ("merged", ["--author=@me", f"--merged-at={d}"]),
                   ("reviewed", ["--reviewed-by=@me", f"--updated={d}"])]
        out = {"truncated": set()}
        for i, (kind, flt) in enumerate(queries):
            if i:
                sleep(sources_gh.SLEEP)
            rows = json.loads(sources_gh.run(["search", "prs", "--limit", str(PR_LIMIT), *flt, "--json", PR_FIELDS], 15))
            items = []
            if len(rows) >= PR_LIMIT:
                out["truncated"].add(kind)
            for r in rows:
                repo = (r.get("repository") or {}).get("nameWithOwner")
                if not repo or not r.get("number") or not cfg.is_work_repo(repo):
                    continue
                if kind == "reviewed" and (r.get("author") or {}).get("login") == me:
                    continue
                items.append({"ref": sources_gh.ref_of(repo, r["number"]), "title": r.get("title") or ""})
            out[kind] = items
        return out
    except (sources_gh.GhError, ValueError, TypeError, AttributeError):
        return None


def _prior_prs(prior):
    m = re.search(r"^## PRs\n.*?(?=^## |\Z)", prior or "", re.S | re.M)
    return m.group(0).rstrip("\n").split("\n") + [""] if m else None


def prs_settled(prior):
    """True when an earlier brief holds a real PRs section (not pending, not unavailable)."""
    sec = _prior_prs(prior)
    return bool(sec) and not any(UNAVAILABLE in x or PENDING in x for x in sec[:2])


def pr_section(day, cfg, prior="", fetch=True):
    """The PRs section. fetch=False is the write-first pass: keep what the prior brief had, else pending.
    On gh failure keep a settled earlier section (re-scrubbed), else say unavailable."""
    old = _prior_prs(prior)
    prs = _prs(day, cfg) if fetch else None
    if prs is None:
        if old and (not fetch or prs_settled(prior)):
            return [scrub(x, cfg) for x in old]
        return ["## PRs", UNAVAILABLE if fetch else PENDING, ""]
    out = ["## PRs"]
    for kind, label in (("opened", "Opened"), ("merged", "Merged"),
                        ("reviewed", "Reviewed, touched today (any PR you ever reviewed that changed today)")):
        rows = prs[kind]
        out.append(f"{label}:" + (" none" if not rows else ""))
        out += [f"{i}. `{scrub(p['ref'], cfg)}` {scrub(p['title'], cfg)[:100]}" for i, p in enumerate(rows[:MAX_PRS], 1)]
        if len(rows) > MAX_PRS:
            out.append(f"(first {MAX_PRS} of {len(rows)} company PRs shown)")
        if kind in prs["truncated"]:
            out.append(f"(gh returned its limit of {PR_LIMIT}; there may be more)")
    return out + [""]


def _sheet(ts):
    """The header's timesheet part, worded as the timesheet's own basis column is."""
    if ts is None:
        return ""                    # the day is not on the sheet (or work.db is absent): say nothing
    mins, note = ts
    d = dur(mins * 60) or "0m"
    return {"": f" (timesheet {d})", "net?": f" (timesheet {d} net?, a break is unconfirmed)",
            "span": f" (timesheet: no breaks yet, span {d})"}[note]


def build(day, cfg, now=None, prior="", fetch=True):
    now = int(now or time.time())
    t0, t1 = local_tt.day_bounds(day, now)      # the day is its session: login -> logout (or now)
    times = dict(local_tt.ref_seconds(t0, t1))
    worked = local_tt.worked_sec(t0, t1, now)
    ts = local_tt.day_timesheet(day)
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
             f"Worked {dur(worked) or '0m'}" + _sheet(ts)
             + f" · {len(done)} items closed · {len(still)} still open", "", "---", ""]
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
    att = attention(day, cfg, pend + done)
    if rows or att:                       # an empty table is noise
        lines += ["## Time by item"]
    if rows:
        lines += ["| ref | title | time |", "|---|---|---|"] + rows + [""]
    if att:
        lines += ["Terminal and browser attention (you / in agent pane / browser):",
                  "This is where you looked; the clock above is when work ran. They differ by design.",
                  "| item | title | you | in agent pane | browser |", "|---|---|---|---|---|"]
        for k, v in sorted(att.items(), key=lambda kv: (kv[0].startswith("No ticket"), -sum(kv[1])))[:15]:
            name = scrub(k, cfg) if k.startswith("No ticket") else f"`{scrub(k, cfg)}`"
            lines += [f"| {name} | {scrub(titles.get(k, ''), cfg)[:60]} | " + " | ".join(dur(x) or "-" for x in v) + " |"]
        lines += [""]
    lines += pr_section(day, cfg, prior, fetch)
    return "\n".join(lines).rstrip("\n") + "\n"


def _put(path, cfg, text, exists):
    cfg.report_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    atomic.write_text(path, text, 0o600)
    return "updated" if exists else "created"


def write(day, cfg, reason=None, now=None):
    """Write the brief. Returns 'created', 'unchanged', 'updated' or 'skipped'.

    Written twice: first without waiting on gh (PRs kept from before, else pending), so a suspend right
    after logout still leaves a file; then again once gh answers. Nightly skips only a brief whose PRs
    are settled; a pending or unavailable one is rebuilt (header included)."""
    path = cfg.report_dir / f"{day.isoformat()}.md"
    exists = path.exists()
    prior = path.read_text(encoding="utf-8") if exists else ""
    if reason == "nightly" and exists and prs_settled(prior):
        return "skipped"             # the logout brief already ran; the fallback must not redo it
    res = "unchanged"
    first = build(day, cfg, now, prior, fetch=False)
    if not exists or first != prior:
        res = _put(path, cfg, first, exists)
    final = build(day, cfg, now, first, fetch=True)
    if final != first:
        _put(path, cfg, final, True)
        res = res if res == "created" else "updated"
    return res


def parse_day(s):
    today = local_tt.workday(time.time())   # the session's day: a logout at 01:00 briefs that evening
    if not s or s == "today":
        return today
    if s == "yesterday":
        return today - timedelta(days=1)
    return datetime.strptime(s, "%Y-%m-%d").date()
