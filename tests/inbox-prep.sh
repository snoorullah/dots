#!/usr/bin/env bash
# dots-inbox prep + brief: what gets analysed (and what must not), that the analysis agent
# is read-only and Sonnet, that the dashboard file holds numbers only, and that the brief
# is silent when the store is locked or the panic switch is on. No real claude, mail or toast.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/dots-inbox"
export DOTS_INBOX_TEST=1 DOTS_INBOX_MAIL="$tmp/Mail" DOTS_OVERVIEW_STATE_DIR="$tmp/ov" \
       XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
python3 - "$tmp" <<'PY'
import argparse, json, os, stat, subprocess, sys, time
from pathlib import Path

from dots_inbox import brief, config, db, mail, notify, prep

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

tmp = Path(sys.argv[1])
config.PANIC = tmp / "config" / "timetrack" / "PANIC"
now = int(time.time())
spawns, toasts, asks, popups, calls = [], [], [], [], []
prep._spawn = lambda n: spawns.append(n)
notify.toast = lambda app, summary, body="", **k: toasts.append(summary)
prep.notify.toast = notify.toast
M = {"id": "m1@x", "thread": "t1", "file": None, "folder": "INBOX", "from": "Boss <b@x>",
     "from_addr": "b@x", "to": ["me@x"], "cc": [], "subject": "Prod is down", "date": now - 100,
     "tags": {"inbox", "vip", "critical"}, "headers": {}}
mail.get = lambda mid: dict(M, id=mid, subject="Prod is down" if mid == "m1@x" else f"Subj {mid}")
mail.messages = lambda q, limit=None: []
mail.body = lambda m, limit=20000: "the cluster is on fire"
mail.count = lambda q: 3

conn = db.open_db()
def ev(kind, ref, ts=None): db.log(conn, kind, ref, None, ts=ts or now); conn.commit()
def rows(): return [dict(r) for r in conn.execute("SELECT * FROM prep ORDER BY id")]

# 1. dedupe by ref; the cursor means one run's events are not replayed
prep.queue(conn, [], now)                      # first look: sets the cursor
ev("critical", "m1@x"); ev("critical", "m1@x")
check("queued once", prep.queue(conn, [], now), 1)
check("one row, queued", [(r["ref"], r["status"], r["kind"], r["title"]) for r in rows()],
      [("m1@x", "queued", "mail", "Prod is down")])
check("runner spawned once", len(spawns), 1)
ev("critical", "m1@x")
check("same ref again: nothing", prep.queue(conn, [], now), 0)
check("no replay without new events", prep.queue(conn, [], now), 0)

# 2. an alert NAME is prepared once a week
ev("alert_firing", "HighCPU|node-a")
check("alert queued", prep.queue(conn, [], now), 1)
ev("alert_firing", "HighCPU|node-b")
check("same name, other scope, within 7 d: no", prep.queue(conn, [], now), 0)
ev("alert_firing", "DiskFull|node-a")
check("other name queues", prep.queue(conn, [], now), 1)
conn.execute("UPDATE prep SET created_unix=? WHERE ref='HighCPU|node-a'", (now - 8 * 86400,))
conn.commit()
ev("alert_firing", "HighCPU|node-a")
check("after 8 days the same alert is prepared again", prep.queue(conn, [], now), 1)
check("re-prepare reuses the row", len([r for r in rows() if r["ref"] == "HighCPU|node-a"]), 1)

# 3. daily cap of 6 -> skipped with the reason
for i in range(5): ev("critical", f"c{i}@x")
n = prep.queue(conn, [], now)
st = [r["status"] for r in rows()]
check("cap: six taken, rest skipped", (st.count("queued"), st.count("skipped")), (6, 2))
check("skip reason", [r["summary"] for r in rows() if r["status"] == "skipped"][0].startswith("daily cap"), True)

# 4. PANIC queues nothing, and does not replay later
config.PANIC.parent.mkdir(parents=True, exist_ok=True); config.PANIC.write_text("")
before, spawned = len(rows()), len(spawns)
ev("critical", "p1@x")
check("panic: nothing", (prep.queue(conn, [], now + 86400), len(rows()), len(spawns)), (0, before, spawned))
config.PANIC.unlink()
check("panic event not replayed afterwards", prep.queue(conn, [], now + 86400), 0)

# 5. runner argv: Sonnet, read-only, never opus
argv = prep.claude_argv()
check("model", argv[argv.index("--model") + 1], "sonnet")
check("no opus anywhere", any("opus" in a.lower() for a in argv), False)
dis = argv[argv.index("--disallowedTools") + 1].split(",")
for t in ("Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "mcp__plugin_slack_slack__slack_send_message",
          "mcp__pnow-erp__create_document", "mcp__pnow-erp__update_document", "mcp__pnow-erp__delete_document",
          "mcp__pnow-erp__submit_document", "mcp__pnow-erp__cancel_document"):
    check(f"denies {t}", t in dis, True)
for t in ("Read(~/.ssh/**)", "Read(~/.config/**)", "Read(~/Mail/**)", "WebSearch"):
    check(f"denies {t}", t in dis, True)
al = argv[argv.index("--allowedTools") + 1].split(",")
from dots_inbox import slack as _slack
for t in _slack.DENY_TOOLS + ["Grep", "Glob", "mcp__plugin_slack_slack", "mcp__pnow-erp"]:
    check(f"denies {t} (shared with the slack checker)", t in dis, True)
check("no unscoped search tool is allowed", any(x in ("Grep", "Glob") for x in al), False)
check("allows only reads", sorted(al), sorted(["Read(~/work/**)"] + [
    "mcp__k8s-ro__" + x for x in ("list_resources", "get_resource", "get_logs", "get_pod_metrics",
    "get_node_metrics", "list_contexts", "get_pod_containers", "list_api_resources")]))
check("turn limit", argv[argv.index("--max-turns") + 1], "25")

# 6. runner writes the md (0600) and marks done; a failing call marks failed and continues
conn.execute("DELETE FROM prep"); conn.commit()
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','m1@x','Prod is down','queued',?)", (now,))
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','bad@x','Breaks','queued',?)", (now,))
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','m3@x','Third','queued',?)", (now,))
conn.commit()
seen = []
def fake(argv, input=None, **kw):
    seen.append((argv, input, kw))
    if "Subj bad@x" in input or "Breaks" in input:
        return subprocess.CompletedProcess(argv, 1, "", "boom")
    return subprocess.CompletedProcess(argv, 0, json.dumps({"result": "# Pods are crash-looping\n\nDetails."}), "")
prep.run = fake
mail.get = lambda mid: dict(M, id=mid, subject="Breaks" if mid == "bad@x" else "Prod is down")
check("runner exits 0", prep.run_all(), 0)
r = {x["ref"]: x for x in rows()}
check("statuses", [(k, v["status"]) for k, v in r.items()],
      [("m1@x", "done"), ("bad@x", "failed"), ("m3@x", "done")])
check("summary is the first line", r["m1@x"]["summary"], "Pods are crash-looping")
p = Path(r["m1@x"]["path"])
check("md path", p, config.PREP_DIR / f"{r['m1@x']['id']}.md")
check("md mode 0600", stat.S_IMODE(p.stat().st_mode), 0o600)
check("md body", "Details." in p.read_text(), True)
check("failed has reason", r["bad@x"]["summary"], "failed: boom")
check("material carries the body", "the cluster is on fire" in seen[0][1], True)
check("untrusted-data warning in prompt", "untrusted" in seen[0][1], True)
check("toast per finished analysis", toasts, ["Prepared: Prod is down", "Prepared: Third"])
check("prepared events", conn.execute("SELECT COUNT(*) FROM event WHERE kind='prepared'").fetchone()[0], 2)
check("prep-run with nothing queued", prep.run_all(), 0)

# 7. counts: numbers only
for s in ("INSERT INTO alert_state(name,scope,severity,state,since_unix,last_unix) VALUES('A','n1','crit','firing',%d,%d)" % (now - 3600, now - 60),
          "INSERT INTO alert_state(name,scope,severity,state,since_unix,last_unix) VALUES('Old','n1','warn','firing',%d,%d)" % (now - 99999, now - 99999),
          "INSERT INTO item(source,direction,key,counterpart,subject,purpose,state,created_unix,updated_unix,reply_unix,reply_summary) VALUES('mail','them','k1','Dana','Q','asked for the invoice','replied',%d,%d,%d,'sent it')" % (now - 7200, now, now - 600),
          "INSERT INTO item(source,direction,key,counterpart,subject,purpose,state,created_unix,updated_unix) VALUES('mail','them','k2','Raj','Deploy','asked for sign-off','open',%d,%d)" % (now - 90000, now - 90000),
          "INSERT INTO item(source,direction,key,counterpart,subject,purpose,state,created_unix,updated_unix) VALUES('mail','me','k3','Eve','Review','','open',%d,%d)" % (now - 3600, now - 3600)):
    conn.execute(s)
conn.commit()
doc = brief.counts(conn, now)
on_disk = json.loads(config.OVERVIEW_COUNTS.read_text())
check("counts file == returned doc", on_disk, doc)
check("numbers only", all(isinstance(v, int) and not isinstance(v, bool) for v in on_disk.values()), True)
check("count keys", sorted(on_disk), sorted(["updated", "people_unread", "pr", "alerts_firing", "waiting_them",
      "replied", "waiting_me", "prepared_unseen", "critical"]))
check("stale alert not counted", on_disk["alerts_firing"], 1)
check("ledger counts", (on_disk["waiting_them"], on_disk["replied"], on_disk["waiting_me"], on_disk["prepared_unseen"]), (1, 1, 1, 2))
check("tag counts via mail.count", (on_disk["people_unread"], on_disk["critical"]), (3, 3))
check("counts file mode", stat.S_IMODE(config.OVERVIEW_COUNTS.stat().st_mode), 0o600)

# 8. brief sections from fixture rows
db.log(conn, "nudge", "k2", None, ts=now - 100)
db.log(conn, "alert_firing", "A|n1", None, ts=now - 3600)
conn.commit()
vip = dict(M, id="v1@x", subject="Need your sign-off", tags={"vip", "inbox"})
hr = dict(M, id="h1@x", subject="Late Arrival: 2026-10-28", tags={"hr", "inbox"}, date=now - 50)
mail.messages = lambda q, limit=None: ([hr] if "hr" in q else [vip] if "vip" in q else [])
md, n = brief.build(conn, now - 16 * 3600, now)
order = ["Prepared for you", "Replies you were waiting for", "Needs you", "Still waiting on", "Alerts", "HR / ERP notices"]
pos = [md.index(f"**{t}**") for t in order]
check("sections in priority order", pos, sorted(pos))
for needle in ("Prod is down", "Pods are crash-looping", "Dana", "sent it", "asked for the invoice",
               "Eve", "Need your sign-off", "Raj", "**nudged**", "`A` n1", "fired `A|n1`", "Late Arrival"):
    check(f"brief mentions {needle}", needle in md, True)
check("stale alert not listed", "Old" in md.split("**Alerts**")[1], False)
check("brief counts", (n["Replies you were waiting for"], n["Prepared for you"], n["Needs you"]), (1, 2, 2))

# 9. --login: toast text, prepared marked seen, brief written, popup only on "open"
brief.ask = lambda app, summary, body, actions, timeout, **k: (asks.append((summary, actions)), "open")[1]
brief.popen = lambda argv, **k: popups.append(argv)
args = lambda **k: argparse.Namespace(**{"login": False, "show": False, "since": None, **k})
check("login exit", brief.run(args(login=True)), 0)
check("toast text", asks[0][0], "Ready for you: 1 replies, 2 prepared, 2 need you")
check("action is open", asks[0][1], [("open", "Open")])
check("popup argv", popups[0][:4], ["ghostty", "--class=dots.brief", "--gtk-single-instance=false", "-e"])
check("popup runs glow on the brief", str(config.BRIEF) in popups[0][-1] and "glow -p" in popups[0][-1], True)
check("brief written 0600", stat.S_IMODE(config.BRIEF.stat().st_mode), 0o600)
check("prepared marked seen", conn.execute("SELECT COUNT(*) FROM prep WHERE seen_unix IS NULL AND status='done'").fetchone()[0], 0)
check("brief event logged", conn.execute("SELECT COUNT(*) FROM event WHERE kind='brief'").fetchone()[0], 1)
check("--since defaults to the last brief", brief._last_brief(conn) is not None, True)
popups.clear(); asks.clear()
brief.ask = lambda *a, **k: None
brief.run(args(login=True))
check("no answer: no popup", popups, [])

# 10. --show opens the popup directly; panic and a locked store are silent
popups.clear()
brief.run(args(show=True))
check("--show opens", len(popups), 1)
config.PANIC.write_text("")
asks.clear(); brief.ask = lambda *a, **k: asks.append(a)
check("panic login exit 0", brief.run(args(login=True)), 0)
check("panic login: no toast", asks, [])
config.PANIC.unlink()
config.mounted = lambda: False
before = config.BRIEF.read_text()
import io, contextlib
out = io.StringIO()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
    rc = brief.run(args(login=True))
check("locked store: exit 0, silent, untouched", (rc, out.getvalue(), asks, config.BRIEF.read_text() == before), (0, "", [], True))

if fails:
    print("inbox-prep FAILED:")
    for f in fails: print("  " + f)
    raise SystemExit(1)
print("inbox-prep ok")
PY
