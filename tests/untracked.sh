#!/usr/bin/env bash
# Untracked time -> ticket: PRIVATE_V9 (untracked_claim), termclass.apply_claims and
# dots-overview untracked. What must never happen: a second task for the same (day, project),
# a claim lost when termclass re-writes the day, an 'ignored' day relabelled, or any change to
# seconds / verdicts / work.db (v_day_worked).
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TIMETRACK_STATE_DIR="$tmp/state" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/xstate" \
       DOTS_OVERVIEW_STATE_DIR="$tmp/ov" DOTS_WORK_CONF="$tmp/work.conf" OPS_STATE="$tmp/ops"
export PYTHONPATH="$root/nix/pkgs/timetrack:$root/nix/pkgs/dots-overview"
python3 - <<'PY'
import hashlib, json, sys, uuid
from datetime import date, datetime, timedelta

from timetrack import dbs, migrate, termclass
from dots_overview import attention, config, tw, untracked

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

# an in-memory Taskwarrior: only what task.new_task touches
tasks = []
def t_add(desc, tags=(), **attrs):
    t = dict(uuid=str(uuid.uuid4()), desc=desc, tags=list(tags), status="pending", **attrs)
    tasks.append(t); return t["uuid"]
tw.add = t_add
tw.export = lambda *f: [t for t in tasks if not f or t["uuid"] == f[0]]
tw.by_ref = lambda ref: next((t for t in tasks if t.get("ref") == ref), None)

migrate.migrate()
with dbs.open_private() as p:
    check("private v9+", p.execute("PRAGMA user_version").fetchone()[0] >= 9, True)
    check("claim columns", [r[1] for r in p.execute("PRAGMA table_info(untracked_claim)")],
          ["day", "project", "task_uuid", "ref", "decided", "decided_unix"])
with dbs.open_work() as w:
    worked = lambda: [tuple(r) for r in w.execute("SELECT * FROM v_day_worked ORDER BY attendance_day")]
    w0 = worked()

today = datetime.now().date()
D, Y = today.isoformat(), (today - timedelta(days=1)).isoformat()
def seg(day, start, minutes, project, ref=None, agent=None, verdict="work"):
    return dict(start=start, end=start + minutes * 60, seconds=minutes * 60, pane_id="p1", terminal_id="t1",
                agent_session=None, agent_name=agent, task_uuid=None, ref=ref, project=project,
                activity="x", verdict=verdict, by="repo" if not ref else "branch", model=None)
def put(day, segs):
    t0 = int(datetime.combine(date.fromisoformat(day), datetime.min.time()).timestamp())
    for s in segs:
        s["start"] += t0; s["end"] += t0
    with dbs.open_private() as p:
        termclass.write(p, date.fromisoformat(day), termclass.merge(segs))
H = 3600
def day_rows(day):
    with dbs.open_private() as p:
        return [tuple(r) for r in p.execute("SELECT task_uuid, ref, project, agent_name, verdict, seconds FROM term_day"
                                            " WHERE day = ? ORDER BY 1,2,3,4,5", (day,))]
def total(day):
    with dbs.open_private() as p:
        return p.execute("SELECT SUM(seconds), SUM(CASE WHEN verdict='work' THEN seconds END) FROM term_segment WHERE day=?", (day,)).fetchone()[:]

def build(day):
    return lambda: [seg(day, 0, 130, "alpha"), seg(day, 4 * H, 40, "beta"), seg(day, 6 * H, 29, "gamma"),
                    seg(day, 8 * H, 90, "alpha", ref="HD-1"), seg(day, 10 * H, 90, "delta", agent="Vega", verdict="delegated")]
put(D, build(D)())
put(Y, [seg(Y, 0, 45, "alpha")])
seconds_before = total(D)

# 1. threshold: >= 30 min, human, no ticket, today and yesterday only
got = [(c["day"], c["project"], c["sec"]) for c in untracked.candidates()]
check("candidates", sorted(got), sorted([(D, "alpha", 130 * 60), (D, "beta", 40 * 60), (Y, "alpha", 45 * 60)]))
open(tmp_conf := config.CONF, "w").write("UNTRACKED_MIN_MINUTES=60\n")
check("config threshold", [(c["day"], c["project"]) for c in untracked.candidates()], [(D, "alpha")])
open(tmp_conf, "w").write("")
it = [i for i in untracked.items() if i["project"] == "alpha" and i["day"] == D][0]
check("item", (it["kind"], it["title"], it["canPromote"], it["waiting"], it["urgency"]),
      ("untracked", "2h10m on alpha, no ticket", True, False, "passive"))
check("in attention.build", sum(1 for i in attention.build([], [], now=None)["items"] if i["kind"] == "untracked"), 3)

# 2. promote: exactly one task, one claim, same seconds, attribution moved
t, created = untracked.promote(D, "alpha")
check("created", created, True)
check("one task", len(tasks), 1)
check("task shape", (tasks[0]["desc"], tasks[0]["project"], tasks[0]["ref"].startswith("local:")),
      (f"alpha: untracked work {D}", "alpha", True))
with dbs.open_private() as p:
    c = [tuple(r) for r in p.execute("SELECT day, project, task_uuid, ref, decided FROM untracked_claim")]
check("claim", c, [(D, "alpha", tasks[0]["uuid"], tasks[0]["ref"], "promoted")])
check("seconds unchanged", total(D), seconds_before)
check("term_day relabelled", [r for r in day_rows(D) if r[2] == "alpha"],
      sorted([("", "HD-1", "alpha", "", "work", 90 * 60), (tasks[0]["uuid"], tasks[0]["ref"], "alpha", "", "work", 130 * 60)]))
check("item gone", [i["id"] for i in untracked.items() if i["project"] == "alpha" and i["day"] == D], [])
check("yesterday alpha still offered", [i["id"] for i in untracked.items() if i["day"] == Y], [f"untracked:{Y}:alpha"])

# 3. idempotent re-promote
t2, created2 = untracked.promote(D, "alpha")
check("re-promote no-op", (created2, len(tasks), t2["ref"]), (False, 1, tasks[0]["ref"]))

# 4. termclass re-run (whole day replaced) keeps the attribution; labelled_by is 'claim'
put(D, build(D)())
check("rerun keeps attribution", [r for r in day_rows(D) if r[2] == "alpha"],
      sorted([("", "HD-1", "alpha", "", "work", 90 * 60), (tasks[0]["uuid"], tasks[0]["ref"], "alpha", "", "work", 130 * 60)]))
with dbs.open_private() as p:
    by = [r[0] for r in p.execute("SELECT labelled_by FROM term_segment WHERE day=? AND project='alpha' AND ref=?", (D, tasks[0]["ref"]))]
check("labelled_by claim", by, ["claim"])
check("seconds unchanged after rerun", total(D), seconds_before)
check("other projects untouched", [r for r in day_rows(D) if r[2] in ("beta", "gamma", "delta")],
      sorted([("", "", "beta", "", "work", 2400), ("", "", "gamma", "", "work", 1740), ("", "", "delta", "Vega", "delegated", 5400)]))

# 5. ignore hides the item and never relabels; promote after ignore still works
check("ignore", untracked.ignore(D, "beta"), True)
check("ignored hidden", [i["id"] for i in untracked.items() if i["project"] == "beta"], [])
put(D, build(D)())
check("ignored stays unattributed", [r for r in day_rows(D) if r[2] == "beta"], [("", "", "beta", "", "work", 2400)])
check("ignore after promote refused", untracked.ignore(D, "alpha"), False)

# 6. bad input is refused, not guessed
for args in (("nope", "alpha"), (D, "-x"), (D, "zeta")):
    try: untracked.promote(*args); fails.append(f"promote{args} should fail")
    except untracked.UntrackedError: pass
check("still one task", len(tasks), 1)

# 7. work.db untouched: worked numbers identical
with dbs.open_work() as w:
    check("v_day_worked unchanged", [tuple(r) for r in w.execute("SELECT * FROM v_day_worked ORDER BY attendance_day")], w0)

# 8. a claim moves only what candidates() offered: human 'work'. Agent and unproductive time
#    on the same project keep their label and seconds.
put(Y, [seg(Y, 12 * H, 35, "eps"), seg(Y, 14 * H, 300, "eps", agent="Vega", verdict="delegated"),
        seg(Y, 21 * H, 60, "eps", verdict="unproductive")])
check("offer is 35m", [c["sec"] for c in untracked.candidates() if c["project"] == "eps"], [35 * 60])
te, ce = untracked.promote(Y, "eps")
want_eps = sorted([(te["uuid"], te["ref"], "eps", "", "work", 35 * 60),
                   ("", "", "eps", "Vega", "delegated", 300 * 60),
                   ("", "", "eps", "", "unproductive", 60 * 60)])
check("ticket is 35m only", [r for r in day_rows(Y) if r[2] == "eps"], want_eps)
put(Y, [seg(Y, 12 * H, 35, "eps"), seg(Y, 14 * H, 300, "eps", agent="Vega", verdict="delegated"),
        seg(Y, 21 * H, 60, "eps", verdict="unproductive")])
check("ticket is 35m only after rerun", [r for r in day_rows(Y) if r[2] == "eps"], want_eps)

# 9. 'ignored' rows are never relabelled (rerun above already re-wrote beta), promote after ignore works
with dbs.open_private() as p:
    check("ignored: no claim label",
          p.execute("SELECT COUNT(*) FROM term_segment WHERE day=? AND project='beta' AND labelled_by='claim'", (D,)).fetchone()[0], 0)
    check("ignored row", p.execute("SELECT decided, task_uuid FROM untracked_claim WHERE day=? AND project='beta'", (D,)).fetchone()[:], ("ignored", ""))
n0 = len(tasks)
tb, cb = untracked.promote(D, "beta")
check("promote after ignore", (cb, len(tasks)), (True, n0 + 1))
check("beta now on the new task", [r for r in day_rows(D) if r[2] == "beta"], [(tb["uuid"], tb["ref"], "beta", "", "work", 2400)])
check("ignore after promote refused", untracked.ignore(D, "beta"), False)

if fails:
    print("FAIL"); print("\n".join(fails)); sys.exit(1)
print("untracked: all checks passed")
PY

# ---- second state dir: a v8 database WITH rows, crash-after-COMMIT, real concurrent processes ----
export TIMETRACK_STATE_DIR="$tmp/state2" DOTS_OVERVIEW_STATE_DIR="$tmp/ov2"
python3 - <<'PY'
import os, sys, textwrap, subprocess
from datetime import date, datetime, timedelta

from timetrack import dbs, migrate, termclass

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

# --- A. v8 database with rows migrates to v9 and keeps rows, ids, columns and the index ----------
for which, opener in (("work", dbs.open_work), ("private", dbs.open_private)):
    with opener() as c:
        for v, sql in migrate.MIGRATIONS[which]:
            if which == "private" and v > 8:
                break
            c.executescript(sql); c.execute(f"PRAGMA user_version = {v:d}")
        c.commit()
day = datetime.now().date().isoformat()
INS = ("INSERT INTO term_segment(id, day, start_unix, end_unix, seconds, pane_id, terminal_id, agent_session,"
       " agent_name, task_uuid, ref, project, activity, verdict, labelled_by, model) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
rows = [(5, day, 100, 1900, 1800, "p1", "t1", None, None, None, None, "alpha", "a", "work", "repo", None),
        (9, day, 2000, 2600, 600, "p1", "t1", "s", "Vega", "u-1", "HD-1", "beta", "b", "delegated", "llm", "m"),
        (42, day, 3000, 3300, 300, None, None, None, None, None, None, None, "c", "unproductive", "none", None)]
with dbs.open_private() as p:
    p.executemany(INS, rows)
    p.execute("INSERT INTO term_day(day, task_uuid, ref, project, agent_name, verdict, seconds) VALUES(?,?,?,?,?,?,?)",
              (day, "", "", "alpha", "", "work", 1800))
    p.commit()
    cols8 = [tuple(r) for r in p.execute("PRAGMA table_info(term_segment)")]
    check("v8 user_version", p.execute("PRAGMA user_version").fetchone()[0], 8)
before = None
with dbs.open_private() as p:
    before = [tuple(r) for r in p.execute("SELECT * FROM term_segment ORDER BY id")]
check("v8 -> v9 report", migrate.migrate()["private"], (8, [9]))
with dbs.open_private() as p:
    check("rows survive", [tuple(r) for r in p.execute("SELECT * FROM term_segment ORDER BY id")], before)
    check("ids survive", [r[0] for r in p.execute("SELECT id FROM term_segment ORDER BY id")], [5, 9, 42])
    check("table_info unchanged", [tuple(r) for r in p.execute("PRAGMA table_info(term_segment)")], cols8)
    check("ix_ts_day exists", p.execute("SELECT tbl_name, sql FROM sqlite_master WHERE type='index' AND name='ix_ts_day'").fetchone()[:],
          ("term_segment", "CREATE INDEX ix_ts_day ON term_segment(day, start_unix)"))
    check("term_day untouched", p.execute("SELECT COUNT(*) FROM term_day").fetchone()[0], 1)
    check("claim allowed in CHECK", "'claim'" in p.execute("SELECT sql FROM sqlite_master WHERE name='term_segment'").fetchone()[0], True)
    nid = p.execute("INSERT INTO term_segment(day, start_unix, end_unix, seconds, activity, verdict, labelled_by)"
                    " VALUES(?,?,?,?,?,?,?)", (day, 1, 2, 1, "x", "work", "claim")).lastrowid
    check("autoid continues above the old max", nid > 42, True)
    p.rollback()

# --- B. crash after the script's COMMIT: the version must already be 9 -------------------------
with dbs.open_private() as p:
    p.execute("DROP TABLE untracked_claim"); p.execute("PRAGMA user_version = 8"); p.commit()
    p.execute("DROP INDEX ix_ts_day"); p.commit()
    # run the v9 script and "crash" before _apply sets user_version
    p.executescript(migrate.PRIVATE_V9)
    check("script alone leaves user_version 9", p.execute("PRAGMA user_version").fetchone()[0], 9)
try: rep = migrate.migrate()["private"]
except Exception as e: rep = repr(e)
check("rerun after the crash is a no-op, no 'already exists'", rep, (9, []))

# --- C. real concurrent processes: one task for one (day, project) ------------------------------
Y = (datetime.now().date()).isoformat()
t0 = int(datetime.combine(date.fromisoformat(Y), datetime.min.time()).timestamp())
seg = lambda s, m, proj: dict(start=t0 + s, end=t0 + s + m * 60, seconds=m * 60, pane_id="p", terminal_id="t",
                              agent_session=None, agent_name=None, task_uuid=None, ref=None, project=proj,
                              activity="x", verdict="work", by="repo", model=None)
with dbs.open_private() as p:
    termclass.write(p, date.fromisoformat(Y), [seg(0, 90, "racea"), seg(7200, 90, "raceb")])
worker = os.path.join(os.environ["TIMETRACK_STATE_DIR"], "worker.py")
open(worker, "w").write(textwrap.dedent('''
    import sys, time, uuid, json, os
    from dots_overview import tw, untracked
    log = os.path.join(os.environ["TIMETRACK_STATE_DIR"], "created.log")
    def add(desc, tags=(), **a):
        time.sleep(0.4)                       # widen the check-then-create window
        u = str(uuid.uuid4())
        with open(log, "a") as f: f.write(json.dumps(dict(uuid=u, **a)) + "\\n")
        return u
    tw.add = add
    tw.by_ref = lambda ref: None
    tw.export = lambda *f: [json.loads(l) for l in open(log) if f and json.loads(l)["uuid"] == f[0]]
    day, project, action = sys.argv[1:4]
    if action == "promote":
        t, created = untracked.promote(day, project)
        print("promote", created, t["uuid"])
    else:
        print("ignore", untracked.ignore(day, project))
'''))
def run(project, actions):
    ps = [subprocess.Popen([sys.executable, worker, Y, project, a], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
          for a in actions]
    return [(p.wait(), *p.communicate()) for p in ps]
log = os.path.join(os.environ["TIMETRACK_STATE_DIR"], "created.log")
made = lambda: sum(1 for _ in open(log)) if os.path.exists(log) else 0
res = run("racea", ["promote"] * 6)
check("double-click: all exit 0", [r[0] for r in res], [0] * 6)
check("double-click: exactly one task", made(), 1)
out = [r[1].split() + ["", "", ""] for r in res]
check("double-click: exactly one creator", sorted(o[1] for o in out), [""] * 0 + ["False"] * 5 + ["True"])
check("double-click: all see one uuid", len({o[2] for o in out}), 1)
with dbs.open_private() as p:
    check("one claim", p.execute("SELECT COUNT(*), MIN(decided) FROM untracked_claim WHERE project='racea'").fetchone()[:], (1, "promoted"))

n0 = made()
res = run("raceb", ["promote", "ignore", "ignore", "promote", "ignore", "promote"])
check("promote/ignore race: exit 0", [r[0] for r in res], [0] * 6)
with dbs.open_private() as p:
    claim = p.execute("SELECT decided, task_uuid FROM untracked_claim WHERE project='raceb'").fetchone()[:]
check("promote/ignore race: at most one task", made() - n0 <= 1, True)
check("promote/ignore race: promoted wins whenever a task exists",
      (claim[0] == "promoted") == (made() - n0 == 1), True)

if fails:
    print("FAIL"); print("\n".join(fails)); sys.exit(1)
print("untracked (migration, crash, concurrency): all checks passed")
PY
