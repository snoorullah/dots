"""Render + write the Obsidian daily note (never-guilt, scannable)."""
import json
import html
from collections import defaultdict
from datetime import date, timedelta
from . import config
from .rollup import streak, PRAYERS, day_counts, _rows, _logday, _parse, _iso, _iv_logday

def _hm(seconds) -> str:
    m = round(seconds / 60); return f"{m//60}h{m%60:02d}" if m >= 60 else f"{m}m"

def _bars(seconds, top) -> str:
    return "▓" * max(1, round(8 * seconds / top)) if top else ""

def _clocked_line(adh, tracked_seconds, coverage_pct) -> str:
    parts = []
    ci, co = adh.get("clock_in"), adh.get("clock_out")
    if ci or co:
        parts.append(f"{ci or '—'} → {co or '—'}")
    parts.append(f"{_hm(tracked_seconds)} tracked")
    if coverage_pct is not None:
        parts.append(f"coverage {coverage_pct}%")
    return "Clocked  " + "   ·   ".join(parts)

def _breaks_line(db, ds) -> str:
    day_breaks = [b for b in _rows(db, "breaks") if b.get("start") and _logday(b["start"]) == ds]
    n = len(day_breaks)
    total_s = sum(b.get("duration") or 0 for b in day_breaks)
    auto = sum(1 for b in day_breaks if b.get("source") == "auto")
    labeled = sum(1 for b in day_breaks if b.get("label"))
    return f"Breaks   {n} · {_hm(total_s)}   ({auto} auto · {labeled} labeled)"

def _salah_line(salah, adh) -> str:
    tick = "".join("✅" if salah.get(p) and salah[p] != "missed" else ("◻" if salah.get(p) == "missed" else "·")
                   for p in PRAYERS)
    detail_items = [f"{p} {salah[p]}" for p in PRAYERS if salah.get(p)]
    detail = f"   ({' · '.join(detail_items)})" if detail_items else ""
    return f"Salah    {tick}  logged {adh.get('salah_logged',0)}/5{detail}"

def _top_tasks_line(db, day) -> str | None:
    """Top-3 tracked tasks by duration for the logical day, excluding salah intervals
    (project=='salah') — salah gets its own line above."""
    task_seconds = defaultdict(float)
    for iv in _rows(db, "intervals"):
        if not iv.get("start") or not iv.get("end") or iv.get("project") == "salah":
            continue
        if _iv_logday(iv["start"]) != day:
            continue
        s, e = _parse(_iso(iv["start"])), _parse(_iso(iv["end"]))
        task_seconds[iv.get("description") or "(untitled)"] += (e - s).total_seconds()
    top = sorted(task_seconds.items(), key=lambda kv: -kv[1])[:3]
    if not top:
        return None
    return "Top      " + " · ".join(f"{name} {_hm(sec)}" for name, sec in top)

def _web_line(db, ds) -> str | None:
    """Top-3 web domains by seconds for the day. Omitted entirely when the `web` table
    is empty/absent (no rows until aw-watcher-web is installed)."""
    web_seconds = defaultdict(float)
    for w in _rows(db, "web"):
        if w.get("date") == ds:
            web_seconds[w["domain"]] += w.get("seconds", 0)
    if not web_seconds:
        return None
    top = sorted(web_seconds.items(), key=lambda kv: -kv[1])[:3]
    return "Web      " + " · ".join(f"{name} {_hm(sec)}" for name, sec in top)

def _habit_bar(db, day) -> str:
    adh_rows = {r["date"]: r for r in _rows(db, "adherence")}
    bar, cnt = "", 0
    for i in range(13, -1, -1):
        d = day - timedelta(days=i)
        if day_counts(adh_rows.get(str(d))):
            bar += "▰"; cnt += 1
        else:
            bar += "▱"
    return f"14-day habit:  {bar}   {cnt}/14"

def render(db, day: date) -> str:
    ds = str(day)
    summ = next((r for r in db["daily_summary"].rows if r["date"] == ds), {})
    adh = next((r for r in db["adherence"].rows if r["date"] == ds), {})
    rec = next((r for r in db["reconciliation"].rows if r["date"] == ds), {})
    salah = {r["prayer"]: r.get("status") for r in db["salah"].rows if r["date"] == ds}
    cats_raw = summ.get("categories", {}) or {}
    # sqlite-utils stores nested dicts as JSON strings; parse if needed
    cats = json.loads(cats_raw) if isinstance(cats_raw, str) else cats_raw
    top = max(cats.values()) if cats else 0
    n = streak(db, day)
    where = "  ".join(f"{c} {_hm(s)} {_bars(s, top)}" for c, s in sorted(cats.items(), key=lambda kv:-kv[1]))

    tracked_seconds = summ.get("tracked_seconds", 0)
    coverage_pct = adh.get("coverage_pct")

    header = f"## ⏱ {ds}   ·   🔥 {n}-day streak"
    if config.HABIT_SPRINT_START:
        x = max(1, (day - config.HABIT_SPRINT_START).days + 1)
        header += f"   ·   day {x} of 14"

    # frontmatter (Dataview properties) + the H2 heading stay as markdown — rendered as a real title.
    front = [
        "---", f"date: {ds}", f"tracked_seconds: {tracked_seconds}",
        f"salah_logged: {adh.get('salah_logged',0)}", f"streak: {n}",
        f"counts: {str(day_counts(adh)).lower()}",
    ]
    if coverage_pct is not None:
        front.append(f"coverage_pct: {coverage_pct}")
    front += ["---", "", header]

    # The body's aligned columns rely on monospace + preserved spaces, which Obsidian's Reading
    # view would otherwise collapse (proportional font). Wrap it in <pre> so it stays aligned in
    # every mode. Escape &<> so a task/domain containing them can't break the block.
    body = [
        _clocked_line(adh, tracked_seconds, coverage_pct),
        f"Where    {where}",
    ]
    web_line = _web_line(db, ds)
    if web_line:
        body.append(web_line)
    body.append(_breaks_line(db, ds))
    body.append(_salah_line(salah, adh))
    top_line = _top_tasks_line(db, day)
    if top_line:
        body.append(top_line)

    au = rec.get("active_untracked_min", 0)
    if au:
        body += ["", f"Review (optional)  ~{au}m active with no task"]
    body += ["", _habit_bar(db, day)]

    pre = "<pre>\n" + html.escape("\n".join(body), quote=False) + "\n</pre>"
    return "\n".join(front) + "\n\n" + pre + "\n"

def write(db, day: date):
    config.VAULT_DAILY.mkdir(parents=True, exist_ok=True)
    p = config.VAULT_DAILY / f"{day}.md"
    p.write_text(render(db, day), encoding="utf-8")
    return p
