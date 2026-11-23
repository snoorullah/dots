"""agent-metrics.json: what the agents did and what it cost, per day / agent / ticket / model.

Read-only and local. Inputs:
  * Claude Code transcripts  ~/.claude/projects/*/<session>.jsonl and <session>/subagents/*.jsonl
    (only `message.usage`, `message.model`, `message.id` and the timestamp are read)
  * the herdr session ledger  STATE_DIR/sessions.jsonl  (names, tickets, prompt/stop times)
  * timetrack work.db work_session (day = a work session, never midnight), optional
  * `herdr agent list` for a live status count, optional

NEVER stored: prompt text, message content, cwd, paths. Numbers and ids only.

Incremental: STATE_DIR/agent-metrics-cache/tokens.json keeps, per transcript, the byte offset
already read plus per-day per-model token sums. A later run reads only the appended bytes.

Cost figures use Anthropic's list prices in PRICES below (USD per million tokens), so they are list-price
estimates, not a bill; token counts are always reported alongside.
Edit the table; an unknown model keeps its tokens and gets cost null.
"""
import bisect
import json
import os
import sqlite3
import subprocess
import time
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

from . import atomic, config

VERSION = 1
KEEP_DAYS = 62            # two 30-day periods, so month-over-month deltas exist
SHOW_DAYS = 30
TOP_N = 25
ACTIVE_CAP_SEC = 3 * 3600  # a prompt with no stop is never counted longer than this
WAIT_CAP_SEC = 3600        # a stop with no follow-up prompt counts at most this as "waiting on you"
KINDS = ("in", "out", "cw", "cr")

# Anthropic list prices, USD per million tokens: input, output, 5-minute cache write, cache read.
# Source: platform.claude.com/docs/en/about-claude/pricing (checked 2026-11-23). Matched on the model id
# prefix, most specific first. Cache writes use the 5-minute rate (1-hour writes cost more); Haiku 5.5
# uses its up-to-100k-prompt rates; fast mode, batch and US-only inference multipliers are not applied.
# Still an estimate of list price, not a bill. Unknown model -> tokens kept, cost null.
PRICES = [
    ("claude-fable-5-2",  (8.00, 40.00, 10.00, 0.20)),
    ("claude-mythos-5-2", (8.00, 40.00, 10.00, 0.20)),
    ("claude-fable-5-1",  (10.00, 50.00, 12.50, 0.25)),
    ("claude-mythos-5-1", (10.00, 50.00, 12.50, 0.25)),
    ("claude-fable-5",    (10.00, 50.00, 12.50, 1.00)),
    ("claude-mythos-5",   (10.00, 50.00, 12.50, 1.00)),
    ("claude-opus-5-5",   (4.00, 20.00, 5.00, 0.20)),
    ("claude-opus-5",     (5.00, 25.00, 6.25, 0.50)),
    ("claude-opus-4-8",   (5.00, 25.00, 6.25, 0.50)),
    ("claude-opus-4-7",   (5.00, 25.00, 6.25, 0.50)),
    ("claude-opus-4-6",   (5.00, 25.00, 6.25, 0.50)),
    ("claude-opus-4-5",   (5.00, 25.00, 6.25, 0.50)),
    ("claude-opus-4",     (15.00, 75.00, 18.75, 1.50)),   # Opus 4 and 4.1
    ("claude-sonnet-5-5", (2.00, 10.00, 2.50, 0.10)),
    ("claude-sonnet-5",   (2.00, 10.00, 2.50, 0.20)),
    ("claude-sonnet-4",   (3.00, 15.00, 3.75, 0.30)),     # Sonnet 4, 4.5, 4.6
    ("claude-haiku-5-5",  (0.10, 0.50, 0.125, 0.01)),
    ("claude-haiku-4-5",  (1.00, 5.00, 1.25, 0.10)),
]


def price_for(model):
    m = (model or "").lower()
    for key, p in PRICES:
        if m == key or m.startswith(key + "-") or m.startswith(key + "["):
            return p
    return None


def cost_usd(model, in_, out, cw, cr):
    """Estimated USD for one model's tokens, or None when the model has no price."""
    p = price_for(model)
    if p is None:
        return None
    return (in_ * p[0] + out * p[1] + cw * p[2] + cr * p[3]) / 1e6


# ---------------------------------------------------------------- day mapping

class DayMap:
    """ts -> 'YYYY-MM-DD'. A work session's attendance_day when ts falls inside one, else the local date."""

    def __init__(self, sessions=()):
        self.s = sorted((int(a), int(b) if b is not None else 1 << 40, d) for a, b, d in sessions)
        self.starts = [x[0] for x in self.s]

    def __call__(self, ts):
        i = bisect.bisect_right(self.starts, ts) - 1
        # sessions can nest or overlap; look back a few for one that still contains ts
        for j in range(i, max(i - 6, -1), -1):
            a, b, d = self.s[j]
            if a <= ts <= b:
                return d
        return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def load_day_map(tt_dir=None):
    path = Path(tt_dir or config.TT_DIR) / "work.db"
    rows = []
    try:
        if path.exists():
            conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
            try:
                rows = conn.execute("SELECT opened_unix, closed_unix, attendance_day FROM work_session").fetchall()
            finally:
                conn.close()
    except sqlite3.Error:
        rows = []
    return DayMap(rows)


# ---------------------------------------------------------------- transcripts

def _iso_to_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def _rec_from_line(raw, daymap):
    """One transcript line -> (msg_id, day, model, [in,out,cw,cr]) or None. Content is never kept."""
    if b'"assistant"' not in raw or b'"usage"' not in raw:
        return None
    try:
        d = json.loads(raw)
    except ValueError:
        return None
    msg = d.get("message") or {}
    u = msg.get("usage") or {}
    model = msg.get("model") or ""
    if not model or model.startswith("<"):
        return None
    ts = _iso_to_ts(d.get("timestamp") or "")
    if ts is None:
        return None
    vals = [int(u.get("input_tokens") or 0), int(u.get("output_tokens") or 0),
            int(u.get("cache_creation_input_tokens") or 0), int(u.get("cache_read_input_tokens") or 0)]
    if not any(vals):
        return None
    return msg.get("id") or d.get("uuid") or "", daymap(ts), model, vals


def _add(days, day, model, vals, sign=1):
    slot = days.setdefault(day, {}).setdefault(model, [0, 0, 0, 0, 0])
    for i in range(4):
        slot[i] += sign * vals[i]
    slot[4] += sign


def scan_file(path, state, daymap):
    """Read the bytes of `path` past state['off'] and fold them into state. Returns the new state.

    A message can be written several times (streaming): the last write replaces the earlier ones,
    including across a run boundary (state['last'] carries the final message of the previous run)."""
    st = dict(state or {})
    st.setdefault("off", 0)
    st.setdefault("days", {})
    size = os.path.getsize(path)
    if size < st["off"]:                      # truncated or rewritten: start over
        st.update(off=0, days={}, last=None)
    if size == st["off"]:
        return st
    last = st.get("last")                      # [id, day, model, vals]
    seen = {}
    with open(path, "rb") as fh:
        fh.seek(st["off"])
        data = fh.read()
    cut = data.rfind(b"\n")
    if cut < 0:
        return st                              # a partial line: wait for the writer
    data = data[:cut + 1]
    for raw in data.splitlines():
        rec = _rec_from_line(raw, daymap)
        if rec is None:
            continue
        mid, day, model, vals = rec
        if mid:
            prev = seen.get(mid)
            if prev is None and last and last[0] == mid:
                prev = last[1:]
            if prev:
                _add(st["days"], prev[0], prev[1], prev[2], -1)
            seen[mid] = (day, model, vals)
        _add(st["days"], day, model, vals)
        last = [mid, day, model, vals]
    st["off"] += len(data)
    st["last"] = last
    return st


def _scan_job(args):
    path, state, daymap_rows = args
    return path, scan_file(path, state, DayMap(daymap_rows))


def _session_of(path, root):
    """(session id, is_subagent) from a transcript path."""
    rel = Path(path).relative_to(root).parts      # <project>/<sess>.jsonl or <project>/<sess>/subagents/<a>.jsonl
    if len(rel) >= 4 and rel[2] == "subagents":
        return rel[1], True
    return Path(rel[-1]).stem, False


def _iter_transcripts(root, since_ts):
    for proj in sorted(Path(root).iterdir()):
        if not proj.is_dir():
            continue
        for dirpath, _dirs, files in os.walk(proj):
            for f in files:
                if f.endswith(".jsonl"):
                    p = os.path.join(dirpath, f)
                    try:
                        if os.stat(p).st_mtime >= since_ts:
                            yield p
                    except OSError:
                        pass


def scan_transcripts(root, cache, daymap, since_ts, workers=None):
    """Update `cache` ({path: state}) for every transcript touched since `since_ts`. Returns files read."""
    root = Path(root)
    paths = list(_iter_transcripts(root, since_ts)) if root.is_dir() else []
    live = set(paths)
    for p in list(cache):
        if p not in live:
            del cache[p]
    todo = []
    for p in paths:
        st = cache.get(p) or {}
        try:
            if os.path.getsize(p) != st.get("off", -1):
                todo.append(p)
        except OSError:
            pass
    rows = [(a, b, d) for a, b, d in zip(daymap.starts, [x[1] for x in daymap.s], [x[2] for x in daymap.s])]
    jobs = [(p, cache.get(p), rows) for p in todo]
    workers = workers if workers is not None else min(os.cpu_count() or 1, 12)
    if len(jobs) > 8 and workers > 1:
        with ProcessPoolExecutor(max_workers=workers) as ex:
            results = list(ex.map(_scan_job, jobs, chunksize=4))
    else:
        results = [_scan_job(j) for j in jobs]
    for p, st in results:
        sess, sub = _session_of(p, root)
        st["sess"], st["sub"] = sess, sub
        cache[p] = st
    return len(todo)


def prune(cache, first_day):
    for st in cache.values():
        for day in [d for d in st.get("days", {}) if d < first_day]:
            del st["days"][day]


# ---------------------------------------------------------------- ledger

def load_ledger(state_dir=None):
    """Ledger rows (prompt/stop/session/end), oldest first. Falls back to the per-session json files."""
    sd = Path(state_dir or config.STATE_DIR)
    rows = []
    try:
        with open(sd / "sessions.jsonl", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if isinstance(r, dict) and r.get("sess") and r.get("ts"):
                    rows.append(r)
    except OSError:
        pass
    known = {r["sess"] for r in rows}
    for f in sorted((sd / "sessions").glob("*.json")) if (sd / "sessions").is_dir() else []:
        if f.stem in known:
            continue
        r = atomic.read_json(f)
        if isinstance(r, dict) and r.get("ts"):
            r.setdefault("sess", f.stem)
            r.setdefault("action", "session")
            rows.append(r)
    rows.sort(key=lambda r: r["ts"])
    return rows


def ledger_facts(rows, daymap, now):
    """-> (names {sess: agent}, tickets {sess: ticket}, per {(day, sess): {prompts, active, wait}})."""
    names, tickets = {}, {}
    per = defaultdict(lambda: {"prompts": 0, "active": 0.0, "wait": 0.0})
    by_sess = defaultdict(list)
    for r in rows:
        s = r["sess"]
        if r.get("agent"):
            names[s] = r["agent"]
        if r.get("ticket"):
            tickets[s] = r["ticket"]
        by_sess[s].append(r)
    for s, evs in by_sess.items():
        open_prompt = None      # ts of an unanswered prompt
        last_stop = None
        for r in evs:
            a, ts = r.get("action"), r["ts"]
            if a == "prompt":
                if last_stop is not None:
                    per[(daymap(last_stop), s)]["wait"] += min(max(ts - last_stop, 0), WAIT_CAP_SEC)
                    last_stop = None
                if open_prompt is not None:      # two prompts in a row: the first ran until the second
                    per[(daymap(open_prompt), s)]["active"] += min(ts - open_prompt, ACTIVE_CAP_SEC)
                open_prompt = ts
                per[(daymap(ts), s)]["prompts"] += 1
            elif a in ("stop", "end"):
                if open_prompt is not None:
                    per[(daymap(open_prompt), s)]["active"] += min(max(ts - open_prompt, 0), ACTIVE_CAP_SEC)
                    open_prompt = None
                    if a == "stop":
                        last_stop = ts
                elif a == "end":
                    last_stop = None
        if open_prompt is not None and now - open_prompt < ACTIVE_CAP_SEC:
            per[(daymap(open_prompt), s)]["active"] += max(now - open_prompt, 0)
    return names, tickets, per


# ---------------------------------------------------------------- aggregation

def _empty():
    return {"in": 0, "out": 0, "cw": 0, "cr": 0, "msgs": 0, "cost": 0.0, "unpriced": 0, "sub": 0}


def _fold(acc, model, vals, sub):
    acc["in"] += vals[0]
    acc["out"] += vals[1]
    acc["cw"] += vals[2]
    acc["cr"] += vals[3]
    acc["msgs"] += vals[4]
    c = cost_usd(model, *vals[:4])
    if c is None:
        acc["unpriced"] += sum(vals[:4])
    else:
        acc["cost"] += c
    if sub:
        acc["sub"] += sum(vals[:4])


def _tok(acc):
    total = acc["in"] + acc["out"] + acc["cw"] + acc["cr"]
    return {"in": acc["in"], "out": acc["out"], "cacheWrite": acc["cw"], "cacheRead": acc["cr"],
            "total": total, "msgs": acc["msgs"]}


def _cost(acc):
    """null when nothing is priced; costPartial marks a total that left unpriced tokens out."""
    priced = acc["in"] + acc["out"] + acc["cw"] + acc["cr"] - acc["unpriced"]
    if priced <= 0:
        return None
    return round(acc["cost"], 4)


def _share(acc):
    total = acc["in"] + acc["out"] + acc["cw"] + acc["cr"]
    return round(acc["sub"] / total, 4) if total else 0.0


def build(cache, ledger_rows, daymap, now=None, live=None):
    now = int(now or time.time())
    today = daymap(now)
    today_d = datetime.strptime(today, "%Y-%m-%d").date()

    def day_n(n):
        return (today_d - timedelta(days=n)).isoformat()

    names, tickets, per = ledger_facts(ledger_rows, daymap, now)

    # (day, sess, model, sub) -> [in,out,cw,cr,msgs]
    tok = defaultdict(lambda: [0, 0, 0, 0, 0])
    for st in cache.values():
        for day, models in st.get("days", {}).items():
            for model, v in models.items():
                k = (day, st.get("sess", "?"), model, bool(st.get("sub")))
                for i in range(5):
                    tok[k][i] += v[i]

    def name_of(s):
        return names.get(s) or s[:8]

    def ticket_of(s):
        return tickets.get(s)

    def period(first, last):
        """Totals plus breakdowns for days first..last (ISO strings, inclusive)."""
        tot = _empty()
        sess_days = defaultdict(set)
        by_agent, by_ticket, by_model = defaultdict(_empty), defaultdict(_empty), defaultdict(_empty)
        a_sess, a_models = defaultdict(set), defaultdict(set)
        t_sess = defaultdict(set)
        lg = defaultdict(lambda: {"prompts": 0, "active": 0.0, "wait": 0.0})   # by agent
        lt = defaultdict(lambda: {"prompts": 0, "active": 0.0, "wait": 0.0})   # by ticket
        lall = {"prompts": 0, "active": 0.0, "wait": 0.0}
        for (day, s, model, sub), v in tok.items():
            if not first <= day <= last:
                continue
            _fold(tot, model, v, sub)
            _fold(by_agent[name_of(s)], model, v, sub)
            _fold(by_ticket[ticket_of(s) or "untracked"], model, v, sub)
            _fold(by_model[model], model, v, sub)
            a_sess[name_of(s)].add(s)
            a_models[name_of(s)].add(model)
            t_sess[ticket_of(s) or "untracked"].add(s)
            sess_days[s].add(day)
        for (day, s), x in per.items():
            if not first <= day <= last:
                continue
            for k in ("prompts", "active", "wait"):
                lall[k] += x[k]
                lg[name_of(s)][k] += x[k]
                lt[ticket_of(s) or "untracked"][k] += x[k]
            a_sess[name_of(s)].add(s)
            t_sess[ticket_of(s) or "untracked"].add(s)
            sess_days[s].add(day)
        runs = len(sess_days)

        def row(key, acc, led, sessions, extra=None):
            r = {"key": key, "runs": len(sessions), "prompts": led["prompts"],
                 "activeMin": round(led["active"] / 60, 1), "waitingMin": round(led["wait"] / 60, 1),
                 "tokens": _tok(acc), "costUsd": _cost(acc), "subagentShare": _share(acc)}
            if extra:
                r.update(extra)
            return r

        agents = sorted((row(k, v, lg[k], a_sess[k], {"models": sorted(a_models[k])}) for k, v in by_agent.items()),
                        key=lambda r: -r["tokens"]["total"])
        for k in lg:
            if k not in by_agent:
                agents.append(row(k, _empty(), lg[k], a_sess[k], {"models": []}))
        tickets_l = sorted((row(k, v, lt[k], t_sess[k]) for k, v in by_ticket.items()),
                           key=lambda r: -r["tokens"]["total"])
        for k in lt:
            if k not in by_ticket:
                tickets_l.append(row(k, _empty(), lt[k], t_sess[k]))
        models = sorted(({"key": m, "tokens": _tok(v), "costUsd": _cost(v), "priced": price_for(m) is not None,
                          "subagentShare": _share(v)} for m, v in by_model.items()),
                        key=lambda r: -r["tokens"]["total"])
        return {
            "first": first, "last": last, "runs": runs, "prompts": lall["prompts"],
            "activeMin": round(lall["active"] / 60, 1), "waitingMin": round(lall["wait"] / 60, 1),
            "tokens": _tok(tot), "costUsd": _cost(tot), "subagentShare": _share(tot),
            "unpricedTokens": tot["unpriced"],
            "byAgent": agents[:TOP_N], "byTicket": tickets_l[:TOP_N], "byModel": models,
        }

    def delta(cur, prev):
        out = {}
        for k in ("runs", "prompts", "activeMin", "waitingMin"):
            out[k] = round(cur[k] - prev[k], 1)
        out["tokens"] = cur["tokens"]["total"] - prev["tokens"]["total"]
        out["costUsd"] = (round(cur["costUsd"] - prev["costUsd"], 4)
                          if cur["costUsd"] is not None and prev["costUsd"] is not None else None)
        return out

    periods = {}
    for name, n in (("today", 1), ("week", 7), ("month", 30)):
        cur = period(day_n(n - 1), today)
        prev = period(day_n(2 * n - 1), day_n(n))
        cur["prev"] = {k: prev[k] for k in ("first", "last", "runs", "prompts", "activeMin", "waitingMin",
                                            "tokens", "costUsd")}
        cur["delta"] = delta(cur, prev)
        periods[name] = cur

    days = []
    for n in range(SHOW_DAYS - 1, -1, -1):
        d = day_n(n)
        p = period(d, d)
        days.append({"day": d, "runs": p["runs"], "prompts": p["prompts"], "activeMin": p["activeMin"],
                     "waitingMin": p["waitingMin"], "tokens": p["tokens"], "costUsd": p["costUsd"],
                     "subagentShare": p["subagentShare"]})

    out = {"v": VERSION, "ts": now, "today": today, "costIsEstimate": True,
           "prices": [{"match": k, "perMTok": {"in": p[0], "out": p[1], "cacheWrite": p[2], "cacheRead": p[3]}}
                      for k, p in PRICES],
           "days": days, "periods": periods}
    if live is not None:
        out["live"] = live
    return out


# ---------------------------------------------------------------- live status

def live_status(timeout=3):
    """Counts by herdr agent status; None when herdr is absent or slow. No names, no cwd."""
    try:
        cp = subprocess.run(["herdr", "agent", "list"], capture_output=True, text=True, timeout=timeout)
        agents = json.loads(cp.stdout)["result"]["agents"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return None
    by = defaultdict(int)
    needs = 0
    for a in agents:
        by[a.get("agent_status") or "unknown"] += 1
        if "needs you" in ((a.get("tokens") or {}).get("hp_sub") or ""):
            needs += 1
    return {"agents": len(agents), "byStatus": dict(by), "needsYou": needs}


# ---------------------------------------------------------------- entry point

def cache_path():
    return config.STATE_DIR / "agent-metrics-cache" / "tokens.json"


def output_path():
    return config.STATE_DIR / "agent-metrics.json"


def run(now=None, projects_dir=None, with_live=True):
    """Scan, aggregate, write agent-metrics.json atomically. Returns the document."""
    now = int(now or time.time())
    root = Path(projects_dir or Path(os.environ.get("CLAUDE_CONFIG_DIR") or config.HOME / ".claude") / "projects")
    daymap = load_day_map()
    first_day = (datetime.fromtimestamp(now).date() - timedelta(days=KEEP_DAYS)).isoformat()
    cached = atomic.read_json(cache_path(), {}) or {}
    cache = cached.get("files", {}) if cached.get("v") == VERSION else {}
    scan_transcripts(root, cache, daymap, now - KEEP_DAYS * 86400)
    prune(cache, first_day)
    atomic.write_json(cache_path(), {"v": VERSION, "files": cache})
    doc = build(cache, load_ledger(), daymap, now, live_status() if with_live else None)
    atomic.write_json(output_path(), doc)
    return doc


def main():
    t0 = time.time()
    doc = run()
    t = doc["periods"]["today"]
    print(f"agent-metrics: runs={t['runs']} tokens={t['tokens']['total']} cost~${t['costUsd']} "
          f"({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main()
