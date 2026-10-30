#!/usr/bin/env bash
# Terminal time attributed to real work (focuslog.py, termclass.py, clockd's focus hooks).
# What must hold:
#   1  migration     private v4 adds the tables; work.db never holds a pane label or a cwd
#   2  focus spans   open on focus, close on the next focus / idle / gap, reopen on return;
#                    an empty span is not kept; a broken log cannot raise into the clock
#   3  reconnect     a real clockd loop against a fake herdr socket: a dropped stream closes
#                    the span where the daemon was last alive, never across the gap
#   4  join ladder   session -> task, token, branch, repo; pre-log time is workspace-only
#   5  the model     stubbed Ollama: batched, offered tasks only, cached, redacted, no network
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/timetrack"
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config" HOME="$tmp/home"
mkdir -p "$HOME"
python3 - <<'PY'
import json, os, socket, sqlite3, threading, time
from datetime import date, datetime, timedelta
from pathlib import Path

from timetrack import binding, clockd, config, dbs, focuslog, migrate, presence, termclass, webclass

fails = []
n = [0]
def check(name, got, want):
    n[0] += 1
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

SENTINEL = "zq-private-label"

# ---- 1. migration --------------------------------------------------------------------------
# build a v3 private db first, then upgrade it: the migration must work on a live file
for which, opener in (("work", dbs.open_work), ("private", dbs.open_private)):
    with opener() as c:
        for v, sql in migrate.MIGRATIONS[which]:
            if which == "private" and v > 3:
                break
            c.executescript(sql); c.execute(f"PRAGMA user_version = {v:d}")
        c.commit()
rep = migrate.migrate()
LATEST = max(v for v, _ in migrate.MIGRATIONS["private"])
check("private upgraded 3 -> latest", rep["private"], (3, list(range(4, LATEST + 1))))
check("rerun is a no-op", migrate.migrate()["private"], (LATEST, []))
tables = lambda c: {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
with dbs.open_private(readonly=True) as c:
    check("private tables", {"focus_span", "term_segment", "term_day", "term_label_cache"} <= tables(c), True)
    check("verdict is a CHECK'd enum", "CHECK (verdict IN" in c.execute(
        "SELECT sql FROM sqlite_master WHERE name='term_segment'").fetchone()[0], True)
with dbs.open_work(readonly=True) as c:
    check("work.db has no focus or terminal tables",
          [t for t in tables(c) if t.startswith(("focus", "term"))], [])

# ---- 2. focus spans ------------------------------------------------------------------------
def snap(focused="w1:p1", sess2=None, cwd2="/srv/x/api", ws="alpha"):
    return {"focused_pane_id": focused,
            "workspaces": [{"workspace_id": "w1", "label": ws}],
            "tabs": [{"tab_id": "w1:t1", "workspace_id": "w1", "label": "main"}],
            "panes": [
                {"pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1", "terminal_id": "term_a",
                 "cwd": "/srv/x/web", "foreground_cwd": "/srv/x/web", "label": SENTINEL},
                {"pane_id": "w1:p2", "tab_id": "w1:t1", "workspace_id": "w1", "terminal_id": "term_b",
                 "cwd": cwd2, "foreground_cwd": cwd2, "tokens": {"ticket": "TASK-2026-00512"},
                 **({"agent_session": {"value": sess2}} if sess2 else {})}]}

state = {"snap": snap()}
def fetch():
    return {"type": "session_snapshot", "snapshot": state["snap"]}   # the real, wrapped shape

pconn = dbs.open_private()
fl = focuslog.FocusLog(pconn, fetch)
spans = lambda: [dict(r) for r in pconn.execute("SELECT * FROM focus_span ORDER BY id")]

fl.connect(1000.0)
s = spans()
check("connect opens a span on the focused pane", (len(s), s[0]["pane_id"], s[0]["end_unix"]), (1, "w1:p1", None))
check("context captured", (s[0]["ws_label"], s[0]["tab_label"], s[0]["pane_label"], s[0]["cwd"], s[0]["terminal_id"]),
      ("alpha", "main", SENTINEL, "/srv/x/web", "term_a"))

state["snap"] = snap("w1:p2")
fl.on_event("pane_focused", {"pane_id": "w1:p2"}, 1100.0)
s = spans()
check("next focus closes the old span at the event", (s[0]["end_unix"], s[1]["start_unix"], s[1]["pane_id"]), (1100, 1100, "w1:p2"))
check("token and no session captured", (s[1]["ticket_token"], s[1]["agent_session"]), ("TASK-2026-00512", None))

# one user action = pane + tab + workspace focus in the same millisecond: no empty rows
fl.on_event("tab_focused", {}, 1100.0); fl.on_event("workspace_focused", {}, 1100.0)
fl.tick(1100.0)
check("a focus burst leaves one open span", [(r["pane_id"], r["end_unix"]) for r in spans()][-1], ("w1:p2", None))
state["snap"] = snap("w1:p1")
fl.on_event("pane_focused", {"pane_id": "w1:p1"}, 1200.0)
state["snap"] = snap("w1:p2")
fl.on_event("pane_focused", {"pane_id": "w1:p2"}, 1200.0)       # bounced inside one second
check("a zero-length span is not kept", [r["pane_id"] for r in spans() if r["start_unix"] == 1200], ["w1:p2"])

# tab/workspace focus alone: the pane is learned from a snapshot, stamped at the event
state["snap"] = snap("w1:p1")
fl.on_event("tab_focused", {"tab_id": "w1:t1"}, 1300.0)
fl.tick(1305.0)
s = spans()
check("tab focus resolved by snapshot, stamped at the event",
      (s[-2]["pane_id"], s[-2]["end_unix"], s[-1]["pane_id"], s[-1]["start_unix"]), ("w1:p2", 1300, "w1:p1", 1300))

# context change on the focused pane closes and reopens it: agent session appears
state["snap"] = snap("w1:p2")
fl.on_event("pane_focused", {"pane_id": "w1:p2"}, 1400.0)
state["snap"] = snap("w1:p2", sess2="sess-123")
fl.on_event("pane_updated", {}, 1410.0)
fl.tick(1413.0)
s = spans()
check("a new agent session splits the span", [(r["agent_session"], r["end_unix"]) for r in s[-2:]], [(None, 1413), ("sess-123", None)])

# idle: closed when the human goes away, reopened on the pane that is then focused
fl.set_present(False, 1500.0)
check("away closes", spans()[-1]["end_unix"], 1500)
fl.tick(1510.0)
check("nothing opens while away", spans()[-1]["end_unix"], 1500)
fl.set_present(True, 1600.0)
check("return reopens on the focused pane", (spans()[-1]["pane_id"], spans()[-1]["start_unix"], spans()[-1]["end_unix"]), ("w1:p2", 1600, None))

# a heartbeat moves seen_unix; a crash closes where the previous life last looked
fl.tick(1616.0)
check("heartbeat", spans()[-1]["seen_unix"], 1616)
fl2 = focuslog.FocusLog(pconn, fetch)
check("dangling span closed", fl2.close_dangling(), 1)
check("closed at last heartbeat, not now", spans()[-1]["end_unix"], 1616)

# connection gap: closed at the last instant known alive; nothing reopens until reconnect
fl3 = focuslog.FocusLog(pconn, fetch)
fl3.connect(2000.0)
fl3.gap(2007.0)
check("gap closes at last alive", spans()[-1]["end_unix"], 2007)
fl3.set_present(False, 2050.0); fl3.set_present(True, 2060.0)
check("no span opens while disconnected", spans()[-1]["end_unix"], 2007)
fl3.connect(2100.0)
check("reconnect opens a fresh span", (spans()[-1]["start_unix"], spans()[-1]["end_unix"]), (2100, None))
fl3.suspend(2150.0)
check("suspend closes", spans()[-1]["end_unix"], 2150)
fl3.close(2150.0)

# a broken log must never raise into the clock
import contextlib, io
with dbs.open_work() as wconn, contextlib.redirect_stderr(io.StringIO()) as quiet:
    bad = sqlite3.connect(":memory:")            # no focus_span table at all
    d = clockd.Clockd(wconn, private=bad)
    d.focus.snapshot_fn = lambda: (_ for _ in ()).throw(OSError("herdr gone"))
    for ev in ("pane_focused", "tab_focused", "pane_updated"):
        d.handle({"event": ev, "data": {"pane_id": "w1:p1"}}, time.time())
    d.focus.snapshot_fn = fetch
    d._focus(d.focus.connect, time.time())       # table missing -> logged, swallowed
check("clockd survives a broken focus log", (d.focus_errors >= 1, "no such table" in quiet.getvalue()), (True, True))

# ---- 3. reconnect, end to end ---------------------------------------------------------------
# a fake herdr on a unix socket: ping / agent.list / session.snapshot / events.subscribe,
# and a stream we can push frames into and then cut
sock_path = str(Path(os.environ["HOME"]) / "herdr.sock")
srv_state = {"focused": "w1:p1", "stream": None, "stop": False, "snapshots": 0, "subs": 0}
def serve():
    ls = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    ls.bind(sock_path); ls.listen(8); ls.settimeout(0.2)
    def conn_loop(c):
        f = c.makefile("rwb")
        try:
            for line in f:
                req = json.loads(line)
                m = req["method"]
                res = {}
                if m == "agent.list": res = {"agents": []}
                elif m == "session.snapshot":
                    srv_state["snapshots"] += 1
                    res = {"type": "session_snapshot", "snapshot": snap(srv_state["focused"])}
                elif m == "events.subscribe": srv_state["stream"] = c; srv_state["subs"] += 1
                f.write((json.dumps({"id": req["id"], "result": res}) + "\n").encode()); f.flush()
        except (OSError, ValueError):
            pass
    while not srv_state["stop"]:
        try:
            c, _ = ls.accept()
        except socket.timeout:
            continue
        threading.Thread(target=conn_loop, args=(c,), daemon=True).start()
    ls.close()
threading.Thread(target=serve, daemon=True).start()
time.sleep(0.3)

def push(ev, data):
    c = srv_state["stream"]
    c.sendall((json.dumps({"event": ev, "data": data}) + "\n").encode())

events = {}
def script():
    t0 = time.time()
    time.sleep(1.0)
    srv_state["focused"] = "w1:p2"; push("pane_focused", {"pane_id": "w1:p2", "workspace_id": "w1"})
    time.sleep(1.2)
    events["drop"] = time.time()
    srv_state["focused"] = "w1:p1"
    srv_state["stream"].shutdown(socket.SHUT_RDWR); srv_state["stream"].close()
threading.Thread(target=script, daemon=True).start()

clockd.SOCK = sock_path
clockd.BACKOFF = (0.2,)
presence.human_active = lambda now=None: presence.Presence(True, "aw", False, "test")
with dbs.open_private() as c:
    c.execute("DELETE FROM focus_span"); c.commit()
with dbs.open_work() as wconn, dbs.open_private() as p2:
    d = clockd.Clockd(wconn, private=p2)
    d.connect()
    d.run(stop_after=4.0)
    d.shutdown()
    rows = [dict(r) for r in p2.execute("SELECT * FROM focus_span ORDER BY start_unix")]
srv_state["stop"] = True
check("three spans: p1, p2, then p1 again after reconnect", [r["pane_id"] for r in rows], ["w1:p1", "w1:p2", "w1:p1"])
check("every span is closed", [r["end_unix"] is not None for r in rows], [True, True, True])
check("the focus event closed the first span", rows[0]["end_unix"] == rows[1]["start_unix"], True)
check("the gap is not credited", rows[1]["end_unix"] <= events["drop"] + 1 and rows[1]["end_unix"] <= rows[2]["start_unix"], True)
check("an idle stream is not torn down: one subscription per connection, two connections", srv_state["subs"], 2)
check("the clock was not touched by focus logging", d.focus_errors, 0)

# ---- 4. the join ladder ---------------------------------------------------------------------
config.web = lambda: {}
day = date(2026, 10, 27)
T = lambda h, m=0: int(datetime(2026, 10, 27, h, m).astimezone().timestamp())
pconn.execute("DELETE FROM focus_span"); pconn.commit()

TASKS = [
    {"id": "aaaa1111", "uuid": "aaaa1111-0000", "desc": "fix ingress timeout", "ref": "HD-101", "project": "alpha",
     "sess": "sess-A", "agent": "Vega", "open": True, "refs": set()},
    {"id": "bbbb2222", "uuid": "bbbb2222-0000", "desc": "upgrade the cluster", "ref": "TASK-2026-00512", "project": "beta",
     "sess": None, "agent": None, "open": True, "refs": {"TASK-2026-00512"}},
    {"id": "cccc3333", "uuid": "cccc3333-0000", "desc": "write the runbook", "ref": None, "project": "beta",
     "sess": None, "agent": None, "open": True, "refs": set()},
]
SESSIONS = {"sess-B": [{"sess": "sess-B", "agent": "Isis", "ticket": None, "action": "prompt", "ts": T(12, 5),
                        "prompt_head": "check ghp_abcdefghijklmnop and the dashboard", "pane": "w1:p9"}]}
BRANCHES = {"/w/feature": "feat/ABC-77-thing", "/w/plain": "main"}
termclass.load_tasks = lambda: TASKS
termclass.load_sessions = lambda path=None: SESSIONS
termclass.git_branch = lambda cwd: BRANCHES.get(cwd)
termclass.live_snapshot = lambda: {}
binding._repo_map = lambda: {"/srv/mono": "gamma"}
termclass.webclass.agent_spans = lambda d: [(T(15), T(15, 30))]

# the terminal had OS focus and the user was present 09:00-16:00, titled the old way
termclass.window_segments = lambda d, now=None: [(T(9), T(16), "devhost: alpha")]
def span(a, b, **kw):
    ctx = dict(pane_id="w1:p1", tab_id="w1:t1", workspace_id="w1", terminal_id="term_a", agent_session=None,
               ticket_token=None, cwd="/w/plain", ws_label="alpha", tab_label="main", pane_label="api")
    ctx.update(kw)
    with dbs.open_private() as c:
        c.execute("INSERT INTO focus_span(start_unix,end_unix,seen_unix,pane_id,tab_id,workspace_id,terminal_id,"
                  "agent_session,ticket_token,cwd,ws_label,tab_label,pane_label) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (a, b, b, ctx["pane_id"], ctx["tab_id"], ctx["workspace_id"], ctx["terminal_id"],
                   ctx["agent_session"], ctx["ticket_token"], ctx["cwd"], ctx["ws_label"], ctx["tab_label"], ctx["pane_label"]))
span(T(10), T(10, 30), agent_session="sess-A", ticket_token="TASK-2026-00512")   # session beats token
span(T(10, 30), T(11), ticket_token="TASK-2026-00512")                           # token
span(T(11), T(11, 30), cwd="/w/feature")                                         # branch, no such task
span(T(11, 30), T(12), cwd="/srv/mono/svc")                                      # repo -> project only
span(T(12), T(12, 30), cwd="/w/plain", agent_session="sess-B", pane_id="w1:p4")  # unresolved + prompt
span(T(13), T(13, 30), cwd="/w/other", pane_id="w1:p5", ws_label="delta", pane_label="logs")   # unresolved
span(T(15), T(15, 20), cwd="/w/other", pane_id="w1:p6", ws_label="epsilon", pane_label="idle") # unresolved, agent ran

llm_calls, seen_items = [], []
offered_ids = []
def fake_llm(batch, tasks, projects, model):
    llm_calls.append(len(batch))
    offered_ids.append({t["id"] for t in tasks})
    out = {}
    for b in batch:
        seen_items.append(b["item"])
        it = b["item"]
        if it["workspace"] == "alpha":
            out[b["k"]] = {"task": "cccc3333", "project": "beta", "activity": "Writing the runbook ghp_abcdefghijklmnop", "verdict": "work"}
        elif it["workspace"] == "delta":
            # both fabricated: not offered, not known
            out[b["k"]] = {"task": "zzzz9999", "project": "made-up", "activity": "Browsing logs", "verdict": "unproductive"}
        else:
            out[b["k"]] = {"task": None, "project": None, "activity": "Idle shell", "verdict": "unproductive"}
    return out
real_llm_label = termclass.llm_label
termclass.llm_label = fake_llm

rows = termclass.classify(day, now=T(23))
R = [dict(zip(termclass.ROW, r)) for r in rows]
at = lambda h, m=0: next(r for r in R if r["start_unix"] == T(h, m))
check("session -> task", (at(10)["task_uuid"], at(10)["ref"], at(10)["project"], at(10)["agent_name"], at(10)["labelled_by"]),
      ("aaaa1111-0000", "HD-101", "alpha", "Vega", "session"))
check("token -> task by ref", (at(10, 30)["task_uuid"], at(10, 30)["labelled_by"], at(10, 30)["verdict"]), ("bbbb2222-0000", "token", "work"))
check("branch -> ticket (no task)", (at(11)["ref"], at(11)["task_uuid"], at(11)["labelled_by"]), ("ABC-77", None, "branch"))
check("repo -> project, no ticket", (at(11, 30)["project"], at(11, 30)["ref"], at(11, 30)["labelled_by"]), ("gamma", None, "repo"))
check("session with no task still names the agent", at(12)["agent_name"], "Isis")
check("model label accepted for an offered task",
      (at(12)["task_uuid"], at(12)["project"], at(12)["labelled_by"], at(12)["verdict"], at(12)["model"]),
      ("cccc3333-0000", "beta", "llm", "work", webclass.DEFAULT_MODEL))
check("model answer outside the offer is dropped",
      (at(13)["task_uuid"], at(13)["project"], at(13)["verdict"]), (None, None, "unproductive"))
check("unproductive while an agent ran is delegated", at(15)["verdict"], "delegated")
pre = [r for r in R if r["labelled_by"] == "title"]
check("time with no focus span is workspace-level, labelled 'title'", len(pre) >= 1 and all(r["pane_id"] is None for r in pre), True)
check("every focused second is accounted for", sum(r["seconds"] for r in R), 7 * 3600)
with dbs.open_private(readonly=True) as c:
    check("rollup matches segments", c.execute("SELECT SUM(seconds) FROM term_day").fetchone()[0], 7 * 3600)
    check("verdict rollup", dict(c.execute("SELECT verdict, SUM(seconds) FROM term_day GROUP BY 1").fetchall()),
          {v: sum(r["seconds"] for r in R if r["verdict"] == v) for v in {r["verdict"] for r in R}})

# ---- 5. the model ---------------------------------------------------------------------------
check("one batch for all leftovers", len(llm_calls), 1)
blob = json.dumps(seen_items)
check("secrets never reach the model", "ghp_abcdefghijklmnop" in blob, False)
check("the prompt head did, redacted", "[redacted]" in blob, True)
check("only a directory NAME is sent, never a path", "/w/" in blob or "/srv/" in blob, False)
check("model echoing a secret is redacted before it is stored", any("ghp_" in (r["activity"] or "") for r in R), False)
with dbs.open_private(readonly=True) as c:
    check("cache rows hold no secret", "ghp_" in json.dumps([r[0] for r in c.execute("SELECT label FROM term_label_cache")]), False)
    check("cache holds one row per distinct context", c.execute("SELECT COUNT(*) FROM term_label_cache").fetchone()[0], 4)

# the real llm_label against a stubbed Ollama (no network): payload shape and acceptance
class Resp:
    def __init__(self, body): self.b = json.dumps(body).encode()
    def read(self): return self.b
    def __enter__(self): return self
    def __exit__(self, *a): return False
sent = []
def fake_urlopen(req, timeout=None):
    sent.append((req.full_url, json.loads(req.data)))
    answer = {"items": [
        {"k": "k1", "task": "aaaa1111", "project": "alpha", "activity": "Tuning ingress", "verdict": "work"},
        {"k": "k2", "task": "bbbb2222", "project": "unknown", "activity": "x", "verdict": "bogus"},   # not offered
        {"k": "zz", "task": "aaaa1111", "activity": "never asked", "verdict": "work"}]}
    return Resp({"message": {"content": json.dumps(answer)}})
termclass.urllib.request.urlopen = fake_urlopen
batch = [{"k": "k1", "item": {"cwd": "api", "workspace": "alpha"}}, {"k": "k2", "item": {"cwd": "web", "workspace": "alpha"}}]
got = real_llm_label(batch, [TASKS[0]], {"alpha"}, "m")
url, payload = sent[0]
check("Ollama is loopback", url.startswith("http://127.0.0.1:11434/"), True)
check("asked for JSON, no streaming", (payload["format"], payload["stream"]), ("json", False))
user = json.loads(payload["messages"][1]["content"])
check("only the offered tasks are shown", [t["id"] for t in user["TASKS"]], ["aaaa1111"])
check("items carry their key", [i["k"] for i in user["ITEMS"]], ["k1", "k2"])
check("offered task and known project accepted", (got["k1"]["task"], got["k1"]["project"], got["k1"]["verdict"]), ("aaaa1111", "alpha", "work"))
check("task not offered, project unknown, verdict bogus: all dropped", (got["k2"]["task"], got["k2"]["project"], got["k2"]["verdict"]), (None, None, None))
check("an answer for an item never asked is ignored", sorted(got), ["k1", "k2"])
def down(req, timeout=None): raise termclass.urllib.error.URLError("refused")
termclass.urllib.request.urlopen = down
check("model unreachable: empty, not an error", real_llm_label(batch, [TASKS[0]], {"alpha"}, "m"), {})

before = len(llm_calls)
rows2 = termclass.classify(day, now=T(23))
check("labels cached: no second model call", len(llm_calls), before)
check("rerun replaces, not appends", len(rows2), len(rows))

# a task made from untracked time (a promoted claim) is not offered to the labeller
check("baseline: runbook task offered", "cccc3333" in offered_ids[0], True)
with dbs.open_private() as c:
    c.execute("DELETE FROM term_label_cache")
    c.execute("INSERT INTO untracked_claim(day, project, task_uuid, ref, decided, decided_unix)"
              " VALUES('1999-01-01','beta','cccc3333-0000','','promoted',0)"); c.commit()
offered_ids.clear()
termclass.classify(day, now=T(23))
check("promoted task not offered", [("cccc3333" in o) for o in offered_ids], [False] * len(offered_ids))
check("labeller was called", len(offered_ids) > 0, True)
with dbs.open_private() as c:
    c.execute("DELETE FROM untracked_claim"); c.execute("DELETE FROM term_label_cache"); c.commit()
termclass.classify(day, now=T(23))       # restore the cache the later checks expect

with dbs.open_private() as c:
    c.execute("DELETE FROM term_label_cache"); c.commit()
termclass.llm_label = lambda *a: {}
rows3 = [dict(zip(termclass.ROW, r)) for r in termclass.classify(day, now=T(23))]
unres = [r for r in rows3 if r["task_uuid"] is None and r["project"] is None and r["labelled_by"] in ("none", "title")]
check("model down: the deterministic rungs still label", {r["labelled_by"] for r in rows3} >= {"session", "token", "branch", "repo"}, True)
check("model down: leftovers are not invented", all(r["verdict"] in ("unproductive", "delegated") for r in unres), True)
termclass.classify(day, now=T(23), use_llm=False)

# --no-llm must never call the model
termclass.llm_label = lambda *a: (_ for _ in ()).throw(AssertionError("model called with use_llm=False"))
termclass.classify(day, now=T(23), use_llm=False)

# a session record for the same PANE but hours away is another life of a recycled pane id
termclass.load_sessions = lambda path=None: {"old": [{"sess": "old", "agent": "Ghost", "ticket": "ZZ-1", "pane": "w1:p4",
                                                       "cwd": "/w/plain", "ts": T(3), "action": "stop"}]}
ctx = {"pane_id": "w1:p4", "cwd": "/w/plain", "agent_session": None}
check("recycled pane id: a stale record is not joined", termclass.resolve(ctx, TASKS, termclass.load_sessions(), T(12), T(12, 30)), None)
termclass.load_sessions = lambda path=None: {"new": [{"sess": "new", "agent": "Ada", "ticket": "TASK-2026-00512", "pane": "w1:p4",
                                                       "cwd": "/w/plain", "ts": T(12, 10), "action": "stop"}]}
res = termclass.resolve(ctx, TASKS, termclass.load_sessions(), T(12), T(12, 30))
check("a record inside the window is", (res["by"], res["agent_name"], res["task"]["uuid"]), ("session", "Ada", "bbbb2222-0000"))

# titles, both formats
check("title: ours", termclass.parse_title("alpha · main · api"), "alpha")
check("title: herdr's default", termclass.parse_title("devhost: alpha"), "alpha")

# privacy: nothing private reached work.db (checked on the bytes, WAL included)
wal = b"".join(p.read_bytes() for p in Path(os.environ["TIMETRACK_STATE_DIR"]).glob("work.db*"))
check("work.db holds no pane label, cwd or prompt", any(x in wal for x in (SENTINEL.encode(), b"/srv/mono", b"ghp_")), False)

if fails:
    print("term FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print(f"term ok ({n[0]} assertions)")
PY
