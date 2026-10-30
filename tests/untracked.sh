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

if fails:
    print("FAIL"); print("\n".join(fails)); sys.exit(1)
print("untracked: all checks passed")
PY
