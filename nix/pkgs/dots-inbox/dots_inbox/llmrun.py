"""The one place that starts `claude -p`: its argv, its environment, the kill switch, the ledger.

Why one place: the agents read mail and Slack, which is untrusted text, and the machine's
own Claude setup is private. So every spawn gets the same three guarantees:

  context   no transcript is written (--no-session-persistence), and the user's CLAUDE.md,
            auto-memory and output style are not sent. Verified by capturing the request
            body against a loopback listener (see tests/inbox-phase0.sh). --setting-sources ""
            would also drop user hooks and settings, but it removes plugin-provided MCP
            servers, so only a caller that needs none (plugins=False) uses it.
  switch    ~/.config/dots-mail/AGENT_OFF stops every spawn. Rules, floors and toasts are not
            touched: nothing outside this module looks at that file.
  spend     a ledger in the encrypted store, checked BEFORE each spawn: per-model runs a day
            and an estimated dollar total a day. Over a cap the spawn is refused and logged.
            This is the owner's cap on extra usage, enforced in code, not by prompt.

Prices behind the estimate (USD per million tokens, input / output) and the tokens one run
is assumed to use (after prompt caching) are the constants below. When claude reports its
own total_cost_usd the real figure replaces the estimate.
"""
import json
import os
import time

from . import config, db

CAPS = {"haiku": 200, "sonnet": 6}       # runs per local calendar day
USD_CAP = 1.00                           # estimated dollars per local calendar day, all models
PRICE = {"haiku": (1.0, 5.0), "sonnet": (3.0, 15.0)}
TOKENS = {"haiku": (20_000, 1_500), "sonnet": (40_000, 3_000)}      # (input, output) per run

DDL = """CREATE TABLE IF NOT EXISTS llm_run (
  id INTEGER PRIMARY KEY, ts_unix INTEGER NOT NULL, kind TEXT NOT NULL, model TEXT NOT NULL,
  est_usd REAL NOT NULL, actual_usd REAL)"""


class Refused(RuntimeError):
    """The spawn did not happen: kill switch or cap. Never retried in a loop."""


def agent_off():
    return config.AGENT_OFF.exists()


def estimate(model):
    pin, pout = PRICE[model]
    tin, tout = TOKENS[model]
    return round(tin * pin / 1e6 + tout * pout / 1e6, 4)


# argv and environment -----------------------------------------------------------------

def build_argv(model, *, tools, allowed, disallowed, max_turns=None, mcp_config=None,
               strict_mcp=False, plugins=False):
    """Read-only by construction: dontAsk refuses whatever `allowed` does not name (the user's
    default mode would let a classifier decide on text from a stranger), --tools lists the only
    built-ins, and no session is kept. plugins=False also drops every settings file; True keeps
    user settings only because a plugin MCP server comes from them (the context itself is
    still cut: see child_env and the outputStyle override)."""
    argv = ["claude", "-p", "--model", model, "--output-format", "json", "--no-session-persistence"]
    if max_turns:
        argv += ["--max-turns", str(max_turns)]
    argv += ["--permission-mode", "dontAsk"]
    if plugins:
        argv += ["--settings", json.dumps({"outputStyle": "default"})]
    else:
        argv += ["--setting-sources", ""]
    argv += ["--tools", tools]
    if strict_mcp:
        argv += ["--strict-mcp-config"]
    argv += ["--allowedTools", allowed, "--disallowedTools", disallowed]
    if mcp_config:
        argv += ["--mcp-config", str(mcp_config)]
    return argv


def child_env(extra=None):
    """No CLAUDE.md files, no auto-memory directory (it would also create a project dir)."""
    return {**os.environ, "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
            "DOTS_TASK_GATE": "off", **(extra or {})}


# ledger -------------------------------------------------------------------------------

def _day_start(now):
    t = time.localtime(now)
    return int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 0, 0, 0, 0, 0, -1)))


def usage(conn, now=None):
    """({model: runs}, dollars) since local midnight."""
    conn.execute(DDL)
    since = _day_start(now or time.time())
    runs = {r["model"]: r["n"] for r in conn.execute(
        "SELECT model, COUNT(*) AS n FROM llm_run WHERE ts_unix >= ? GROUP BY model", (since,))}
    usd = conn.execute("SELECT COALESCE(SUM(COALESCE(actual_usd, est_usd)), 0) FROM llm_run WHERE ts_unix >= ?",
                       (since,)).fetchone()[0]
    return runs, float(usd)


def _refuse(conn, kind, reason):
    recent = conn.execute("SELECT 1 FROM event WHERE kind='llm_refused' AND ref=? AND detail=? AND ts_unix > ?",
                          (kind, reason, int(time.time()) - 3600)).fetchone()
    if not recent:
        db.log(conn, "llm_refused", kind, reason)
        conn.commit()
    raise Refused(reason)


def reserve(conn, kind, model, now=None):
    """Check the switch and the caps, then record the run (before it starts, so a crash or a
    timeout still counts). Returns the ledger row id; raises Refused."""
    now = int(now or time.time())
    if agent_off():
        raise Refused("agent switched off (AGENT_OFF)")
    if model not in CAPS:
        _refuse(conn, kind, f"model {model!r} has no cap or price: refused")
    conn.execute(DDL)
    conn.commit()
    conn.execute("BEGIN IMMEDIATE")
    try:
        runs, usd = usage(conn, now)
        est = estimate(model)
        if runs.get(model, 0) >= CAPS[model]:
            conn.rollback()
            _refuse(conn, kind, f"daily cap of {CAPS[model]} {model} runs reached")
        if usd + est > USD_CAP:
            conn.rollback()
            _refuse(conn, kind, f"estimated spend ${usd:.2f} + ${est:.2f} would pass the ${USD_CAP:.2f} daily cap")
        cur = conn.execute("INSERT INTO llm_run(ts_unix, kind, model, est_usd) VALUES(?,?,?,?)",
                           (now, kind, model, est))
        conn.commit()
    except Refused:
        raise
    except Exception:
        conn.rollback()
        raise
    return cur.lastrowid


def settle(conn, rowid, out):
    """Replace the estimate with claude's own total_cost_usd when it reported one."""
    text = getattr(out, "stdout", out)
    try:
        cost = float(json.loads(text)["total_cost_usd"])
    except (TypeError, ValueError, KeyError):
        return
    if 0 < cost < 100:
        conn.execute("UPDATE llm_run SET actual_usd=? WHERE id=?", (cost, rowid))
        conn.commit()


def guarded(conn, kind, model, fn):
    """Run fn() (the actual spawn) only if the switch and the ledger allow it."""
    rowid = reserve(conn, kind, model)
    out = fn()
    settle(conn, rowid, out)
    return out
