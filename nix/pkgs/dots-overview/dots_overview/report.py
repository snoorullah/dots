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
UNAVAILABLE = "unavailable (gh offline or not signed in)"


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
    if src is None:
        src = "gh" if (ref or "").startswith("gh:") else ("erp" if ref and not ref.startswith("local:") else None)
    return cfg.is_work_task({"ref": ref, "project": project, "src": src})


def attention(day, cfg, tasks):
    """{key: [you, agent, browser]} of terminal and browser seconds, company only.

    key is a ticket ref, or "No ticket: <project>" for work-project time with no ticket.
    Agent time is a pane an agent ran in or a delegated verdict; unproductive time is not an outcome."""
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
    """{'opened': [...], 'merged': [...], 'reviewed': [...]} of company PRs, or None when gh fails."""
    d = day.isoformat()
    try:
        if not sources_gh.quota_ok():
            return None
        me = sources_gh.whoami()
        queries = [("opened", ["--author=@me", f"--created={d}"]),
                   ("merged", ["--author=@me", f"--merged-at={d}"]),
                   ("reviewed", ["--reviewed-by=@me", f"--updated={d}"])]
        out = {}
        for i, (kind, flt) in enumerate(queries):
            if i:
                sleep(sources_gh.SLEEP)
            rows = json.loads(sources_gh.run(["search", "prs", "--limit", "30", *flt, "--json", PR_FIELDS], 15))
            items = []
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


def pr_section(day, cfg, prior=""):
    """The PRs section. On failure keep the section an earlier run already wrote for this day."""
    prs = _prs(day, cfg)
    if prs is None:
        m = re.search(r"^## PRs\n.*?(?=^## |\Z)", prior or "", re.S | re.M)
        if m and UNAVAILABLE not in m.group(0):
            return m.group(0).rstrip("\n").split("\n") + [""]
        return ["## PRs", UNAVAILABLE, ""]
    out = ["## PRs"]
    for kind in ("opened", "merged", "reviewed"):
        rows = prs[kind][:MAX_PRS]
        out.append(f"{kind.capitalize()}:" + (" none" if not rows else ""))
        out += [f"{i}. `{scrub(p['ref'], cfg)}` {scrub(p['title'], cfg)[:100]}" for i, p in enumerate(rows, 1)]
    return out + [""]


def build(day, cfg, now=None, prior=""):
    now = int(now or time.time())
    t0, t1 = local_tt.day_bounds(day, now)      # the day is its session: login -> logout (or now)
    times = dict(local_tt.ref_seconds(t0, t1))
    worked = local_tt.worked_sec(t0, t1, now)
    net = local_tt.day_net_minutes(day)
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
             f"Worked {dur(worked) or '0m'}" + (f" (timesheet {dur(net * 60) or '0m'})" if net is not None else "")
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
        lines += ["Terminal and browser attention (you / agent / browser):",
                  "| item | title | you | agent | browser |", "|---|---|---|---|---|"]
        for k, v in sorted(att.items(), key=lambda kv: (kv[0].startswith("No ticket"), -sum(kv[1])))[:15]:
            name = scrub(k, cfg) if k.startswith("No ticket") else f"`{scrub(k, cfg)}`"
            lines += [f"| {name} | {scrub(titles.get(k, ''), cfg)[:60]} | " + " | ".join(dur(x) or "-" for x in v) + " |"]
        lines += [""]
    lines += pr_section(day, cfg, prior)
    return "\n".join(lines).rstrip("\n") + "\n"


def write(day, cfg, reason=None, now=None):
    """Write the brief. Returns 'created', 'unchanged', 'updated' or 'skipped'."""
    path = cfg.report_dir / f"{day.isoformat()}.md"
    exists = path.exists()
    if reason == "nightly" and exists:
        return "skipped"             # the logout brief already ran; the fallback must not redo it
    prior = path.read_text(encoding="utf-8") if exists else ""
    text = build(day, cfg, now, prior)
    if exists and prior == text:
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
