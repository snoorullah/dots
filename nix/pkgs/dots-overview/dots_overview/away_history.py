"""away.json: the last 7 days of away gaps, read from timetrack.

Sources, both opened read-only (`mode=ro`), nothing written back:
  * work.db  clock_event kind away_start / away_stop (when a build records them) and the
             `deduction` table (category + start/end + confirmed)
  * private.db  away_label (what the user said the gap was; source declared / asked / auto)

Gap = {startTs, endTs, minutes, day, category, label, answered, source}.
`answered` is true when a person put a label on it (declared or asked, or a confirmed deduction);
an `auto` label or a bare unconfirmed deduction is a guess nobody has confirmed.
No free text beyond the short label strings timetrack already stores.
"""
import sqlite3
import time
from datetime import datetime, timedelta
from pathlib import Path

from . import atomic, config

VERSION = 1
SPAN_DAYS = 7
MIN_GAP_SEC = 60


def _ro(path):
    path = Path(path)
    if not path.exists():
        return None
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)


def _rows(conn, sql, args=()):
    if conn is None:
        return []
    try:
        return conn.execute(sql, args).fetchall()
    except sqlite3.Error:
        return []


def _events(conn, since):
    """away_start/away_stop pairs from clock_event, if this schema allows those kinds."""
    rows = _rows(conn, "SELECT kind, ts_unix FROM clock_event WHERE kind IN ('away_start','away_stop') "
                       "AND ts_unix >= ? ORDER BY ts_unix", (since,))
    out, start = [], None
    for kind, ts in rows:
        if kind == "away_start":
            start = ts
        elif start is not None:
            out.append((start, ts))
            start = None
    return out


def _overlap(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def build(work_conn, private_conn, now=None):
    now = int(now or time.time())
    since = int((datetime.fromtimestamp(now) - timedelta(days=SPAN_DAYS)).replace(hour=0, minute=0, second=0).timestamp())
    labels = [dict(start=r[0], end=r[1] if r[1] is not None else now, day=r[2], key=r[3], label=r[4], source=r[5])
              for r in _rows(private_conn, "SELECT start_unix, end_unix, day, key, label, source FROM away_label "
                                           "WHERE start_unix >= ? ORDER BY start_unix", (since,))]
    deds = [dict(start=r[0], end=r[1] if r[1] is not None else now, day=r[2], cat=r[3], conf=bool(r[4]))
            for r in _rows(work_conn, "SELECT start_unix, end_unix, attendance_day, category, confirmed FROM deduction "
                                      "WHERE start_unix >= ? ORDER BY start_unix", (since,))]
    evs = _events(work_conn, since)

    gaps, used_ded = [], set()
    for lb in labels:
        cat = None
        for i, d in enumerate(deds):
            if _overlap(lb["start"], lb["end"], d["start"], d["end"]) > 0:
                cat = d["cat"]
                used_ded.add(i)
        answered = lb["source"] in ("declared", "asked")
        gaps.append({"startTs": lb["start"], "endTs": lb["end"], "day": lb["day"],
                     "category": cat or lb["key"], "label": lb["label"], "answered": answered,
                     "source": lb["source"]})
    for i, d in enumerate(deds):
        if i in used_ded:
            continue
        gaps.append({"startTs": d["start"], "endTs": d["end"], "day": d["day"], "category": d["cat"],
                     "label": d["cat"], "answered": d["conf"], "source": "deduction"})
    for a, b in evs:
        if any(_overlap(a, b, g["startTs"], g["endTs"]) > 0 for g in gaps):
            continue
        gaps.append({"startTs": a, "endTs": b, "day": datetime.fromtimestamp(a).strftime("%Y-%m-%d"),
                     "category": "away", "label": "Away", "answered": False, "source": "clock"})
    gaps = [g for g in gaps if g["endTs"] - g["startTs"] >= MIN_GAP_SEC]
    gaps.sort(key=lambda g: g["startTs"])
    for g in gaps:
        g["minutes"] = round((g["endTs"] - g["startTs"]) / 60, 1)
    by_cat = {}
    for g in gaps:
        c = by_cat.setdefault(g["category"], {"count": 0, "minutes": 0.0})
        c["count"] += 1
        c["minutes"] = round(c["minutes"] + g["minutes"], 1)
    return {"v": VERSION, "ts": now, "spanDays": SPAN_DAYS, "count": len(gaps),
            "answered": sum(1 for g in gaps if g["answered"]),
            "unanswered": sum(1 for g in gaps if not g["answered"]),
            "totalMin": round(sum(g["minutes"] for g in gaps), 1),
            "byCategory": by_cat, "gaps": gaps}


def output_path():
    return config.STATE_DIR / "away.json"


def run(now=None):
    work = _ro(config.TT_DIR / "work.db")
    priv = _ro(config.TT_DIR / "private.db")
    try:
        doc = build(work, priv, now)
    finally:
        for c in (work, priv):
            if c is not None:
                c.close()
    atomic.write_json(output_path(), doc)
    return doc


def main():
    d = run()
    print(f"away: {d['count']} gaps in {d['spanDays']}d, {d['answered']} answered, {d['totalMin']} min")


if __name__ == "__main__":
    main()
