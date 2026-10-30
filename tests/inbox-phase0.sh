#!/usr/bin/env bash
# dots-inbox phase 0: the holes in a live system, no LLM added.
#   sender spoofing (display name, several addresses, lookalike domain), alert muting, auth in
#   shadow, VIP matching, the one claude argv builder, the "Prepared" toast text, the AGENT_OFF
#   switch (floors keep working), the spend ledger, the listener units, the notification log.
# No real mail, desktop or model. The last block captures a REAL `claude -p` request against a
# loopback listener to prove the user's context never leaves the machine; it runs only where
# a claude binary and a login exist, and says SKIP otherwise.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/dots-inbox" || exit 1
export DOTS_INBOX_TEST=1 DOTS_INBOX_MAIL="$tmp/Mail" XDG_CONFIG_HOME="$tmp/cfg" XDG_STATE_HOME="$tmp/state" \
       DOTS_OVERVIEW_STATE_DIR="$tmp/ov" PYTHONPATH="$root/nix/pkgs/dots-inbox:$root/nix/pkgs/dots-overview" ROOT="$root"
unset DOTS_INBOX_TERMINAL
python3 -B - <<'PY'
import argparse, io, contextlib, json, os, subprocess, sys, time
from pathlib import Path

from dots_inbox import alerts, authshadow, config, db, llmrun, mail, notify, prep, slack, triage

ok = bad = 0
def check(name, cond, extra=""):
    global ok, bad
    if cond:
        ok += 1
    else:
        bad += 1
        print(f"FAIL {name} {extra}")

root = Path(os.environ["ROOT"])
CFG = {
    "me": ["me@example.com"],
    "vip": ["boss@example.com", "@client.example", "client", "client.example", "@", "x@@y"],
    "people": {"domains": ["example.com"]},
    "alerts": {"from": r"alerts@mon\.example", "authserv_id": "mx.example.net"},
    "backup": {"from": r"root@host\.example\.net", "ok": "backup successful", "fail": "backup (failed|error)"},
    "sender_class": {"chat-relay": r"noreply@chat\.example", "erp-relay": r"support@erp\.example"},
    "rule": [
        {"name": "impersonation", "from": "support@erp.example", "subject": "being impersonated",
         "add": ["security"], "notify": "critical", "critical": "account impersonation"},
        {"name": "ticket", "from": "support@erp.example", "subject": "assigned a new task",
         "add": ["ticket", "erp"], "notify": "now", "critical": "ticket assigned"},
        {"name": "catch-all", "from": ".*", "subject": "catchall", "add": ["fyi"], "inbox": False},
    ],
}
config.rules = lambda: CFG
config.me = lambda: "me@example.com"
PANIC = Path(os.environ["XDG_CONFIG_HOME"]) / "timetrack" / "PANIC"
config.PANIC = PANIC

tags, toasts, spawned, asks = [], [], [], []
mail.tag = lambda mid, *ch: tags.append((mid, ch))
mail.body = lambda m, limit=20000: ""
notify.toast = lambda app, s, b="", urgency="normal", ms=8000: toasts.append((app, s, b, urgency))
triage.spawn = lambda argv, **kw: spawned.append(argv)
triage._ask_model = lambda prompt: None
prep._spawn = lambda n: None
conn = db.open_db()
now = int(time.time())
N = [0]

def mk(frm, subject, headers=None, folder="INBOX", age=60):
    N[0] += 1
    a = mail._addrs(frm)
    return {"id": f"m{N[0]}@t", "thread": "t", "file": None, "folder": folder, "from": frm,
            "from_addr": (a or [""])[0], "from_count": len(a), "to": ["me@example.com"], "cc": [],
            "subject": subject, "date": now - age, "tags": set(), "headers": headers or {}}

def reset():
    tags.clear(); toasts.clear(); spawned.clear(); asks.clear()

def post(*ms):
    """post-new minus the stages that are other agents': triage, alerts, notify."""
    reset()
    new = list(ms)
    triage.run(conn, new); alerts.run(conn, new); triage.notify(conn, new)
    conn.commit()
    return {m["id"]: {c for t in [x[1] for x in tags if x[0] == m["id"]] for c in t} for m in new}

def events(kind):
    return conn.execute("SELECT * FROM event WHERE kind=?", (kind,)).fetchall()

# ---- 1. SPOOF: the address decides, never the display name ----------------------------------
real = mk("ERP Support <support@erp.example>", "You were assigned a new task")
r = post(real)[real["id"]]
check("real ERP sender: critical + toast", "+critical" in r and len(spawned) == 1, (r, spawned))
for label, frm in (
        ("display-name spoof (quoted)", '"support@erp.example" <attacker@evil.example>'),
        ("display-name spoof (bare)", "support@erp.example <attacker@evil.example>"),
        ("two addresses", "ERP <support@erp.example>, other@evil.example"),
        ("two addresses, spoof first", "attacker@evil.example, support@erp.example"),
        ("lookalike domain", "support@erp.example.evil.net"),
        ("lookalike prefix", "xsupport@erp.example"),
        ("lookalike suffix", "support@erp.example2")):
    m = mk(frm, "You were assigned a new task")
    r = post(m)[m["id"]]
    check(f"spoof no critical: {label}", "+critical" not in r and not spawned and not toasts, (r, spawned, toasts))
check("spoof: no critical event row besides the real one", len(events("critical")) == 1)
m = mk("a@b.example, c@d.example", "catchall")                       # a `from = ".*"` rule must not match nothing-sender either
check("several senders: even from='.*' matches no rule", "+fyi" not in post(m)[m["id"]])
m = mk("Me <me@example.com>", "own mail")
check("own mail still recognised", "+sent" in post(m)[m["id"]])
m = mk('"me@example.com" <attacker@evil.example>', "own mail?")
check("own-mail spoof is not own mail", "+sent" not in post(m)[m["id"]])
m = mk("Pat <pat@example.com>", "hello")
check("people domain: real colleague", "+people" in post(m)[m["id"]])
for frm in ('"pat@example.com" <x@evil.example>', "x@notexample.com", "x@example.com.evil.net", "a@example.com, b@evil.example"):
    m = mk(frm, "hello")
    check(f"people domain: not {frm}", "+people" not in post(m)[m["id"]])

# ---- 2. ALERT MUTING ------------------------------------------------------------------------
SUBJ = "[CRITICAL] DiskFull (FIRING) - cluster-1"
check("classify: real alert sender", alerts.classify(mk("Mon <alerts@mon.example>", SUBJ), CFG)["name"] == "DiskFull")
for label, frm in (("display name", '"alerts@mon.example" <x@evil.example>'),
                   ("display name bare", "alerts@mon.example <x@evil.example>"),
                   ("two addresses", "alerts@mon.example, x@evil.example"),
                   ("lookalike", "alerts@mon.example.evil.net")):
    check(f"classify: not an alert: {label}", alerts.classify(mk(frm, SUBJ), CFG) is None)
check("classify: backup spoof is not backup",
      alerts.classify(mk('"root@host.example.net" <x@evil.example>', "backup failed"), CFG) is None)
check("classify: real backup", alerts.classify(mk("root@host.example.net", "backup failed"), CFG)["kind"] == "backup_fail")
prep.queue(conn, [], now)                                            # cursor first: nothing yet
spoof = mk('"alerts@mon.example" <x@evil.example>', SUBJ)
post(spoof)
check("fake FIRING: no alert_state", conn.execute("SELECT COUNT(*) FROM alert_state").fetchone()[0] == 0)
check("fake FIRING: no event, no toast", not events("alert_firing") and not [t for t in toasts if "FIRING" in t[2]])
check("fake FIRING: starts no analysis", prep.queue(conn, [], now) == 0
      and conn.execute("SELECT COUNT(*) FROM prep WHERE kind='alert'").fetchone()[0] == 0)
check("fake FIRING: not tagged alert", "+alert" not in {c for t in tags for c in t[1]})
genuine = mk("Monitoring <alerts@mon.example>", SUBJ)
post(genuine)
check("real first FIRING after the fake: state firing", conn.execute(
    "SELECT state, repeats FROM alert_state WHERE name='DiskFull'").fetchone()[:] == ("firing", 1))
check("real first FIRING after the fake: toast", any("FIRING   DiskFull" in t[2] for t in toasts), toasts)
check("real first FIRING after the fake: analysis queued", prep.queue(conn, [], now) == 1
      and conn.execute("SELECT ref FROM prep WHERE kind='alert'").fetchone()[0] == "DiskFull|cluster-1")

# ---- 3. AUTH SHADOW -------------------------------------------------------------------------
AR = "mx.example.net; dkim=pass header.d=corp.example; dmarc=pass header.from=corp.example"
cases = {
    "pass": mk("a@corp.example", "x", {"authentication-results-all": [AR]}),
    "fail-domain": mk("a@other.example", "x", {"authentication-results-all": [AR]}),
    "fail-dmarc": mk("a@corp.example", "x", {"authentication-results-all": ["mx.example.net; dmarc=fail header.from=corp.example"]}),
    "none-nohdr": mk("a@corp.example", "x"),
    "none-foreign-top": mk("a@corp.example", "x", {"authentication-results-all": ["evil.example; dmarc=pass header.from=corp.example", AR]}),
    "fail-comment-trick": mk("a@corp.example", "x", {"authentication-results-all": ["mx.example.net; dmarc=fail (dmarc=pass) header.from=corp.example"]}),
    "fail-multi": mk("a@corp.example, b@corp.example", "x", {"authentication-results-all": [AR]}),
}
want = {"pass": "pass", "fail-domain": "fail", "fail-dmarc": "fail", "none-nohdr": "none",
        "none-foreign-top": "none", "fail-comment-trick": "fail", "fail-multi": "fail"}
for k, m in cases.items():
    check(f"auth result {k}", authshadow.result(m, CFG) == want[k], authshadow.result(m, CFG))
check("auth result: no authserv_id -> unknown", authshadow.result(cases["pass"], {"alerts": {}}) == "unknown")
check("auth result: empty authserv_id -> unknown", authshadow.result(cases["pass"], {"alerts": {"authserv_id": " "}}) == "unknown")
classes = {"internal": mk("a@example.com", "x"), "alert": mk("alerts@mon.example", "x"),
           "backup": mk("root@host.example.net", "x"), "chat-relay": mk("Syed in Teams <noreply@chat.example>", "x"),
           "erp-relay": mk("support@erp.example", "x"), "external": mk("z@elsewhere.example", "x"),
           "multi-from": mk("a@example.com, b@example.com", "x")}
for k, m in classes.items():
    check(f"sender class {k}", authshadow.sender_class(m, CFG) == k, authshadow.sender_class(m, CFG))
conn.execute("DELETE FROM event WHERE kind='auth_shadow'")
before = [triage.decide(m, CFG, use_model=False)["kind"] for m in list(cases.values()) + list(classes.values())]
authshadow.run(conn, list(cases.values()) + [classes["chat-relay"], classes["erp-relay"]], CFG)
conn.commit()
rows = conn.execute("SELECT ref, detail FROM event WHERE kind='auth_shadow'").fetchall()
check("auth_shadow: one event per message", len(rows) == len(cases) + 2)
check("auth_shadow: events hold class and result only", all(set(r["ref"]) <= set("abcdefghijklmnopqrstuvwxyz-0123456789") for r in rows)
      and {r["detail"] for r in rows} <= {"pass", "fail", "none", "unknown"})
check("auth_shadow: enforces nothing (decisions unchanged)",
      before == [triage.decide(m, CFG, use_model=False)["kind"] for m in list(cases.values()) + list(classes.values())])
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    authshadow.report(argparse.Namespace(days=7))
rep = buf.getvalue()
check("auth-report: per-class table", "chat-relay" in rep and "erp-relay" in rep and "external" in rep, rep)
line = {l.split()[0]: l.split() for l in rep.splitlines() if l and l.split()[0] in ("chat-relay", "erp-relay", "external", "total")}
check("auth-report: chat relay carries no result (none=1)", line["chat-relay"][1:6] == ["0", "0", "1", "0", "1"], line.get("chat-relay"))
check("auth-report: total row", line["total"][5] == str(len(rows)), line.get("total"))
conn.execute("DELETE FROM event WHERE kind='auth_shadow'"); conn.commit()
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    authshadow.report(argparse.Namespace(days=7))
check("auth-report: empty says so", "no auth_shadow events" in buf.getvalue())

# ---- 4. VIP: exact address or @domain, parsed address only ----------------------------------
def vip(frm): return triage._vip(mk(frm, "x"), CFG)
check("vip exact address", vip("Boss <boss@example.com>"))
check("vip @domain", vip("c@client.example"))
check("vip not a subdomain", not vip("c@mail.client.example"))
check("vip not a lookalike domain", not vip("c@notclient.example") and not vip("c@client.example.evil.net"))
check("vip bare word 'client' is nobody", not vip("client@x.example") and not vip("a@client"))
check("vip display name never used", not vip('"boss@example.com" <x@evil.example>') and not vip("Boss <x@evil.example>"))
check("vip several addresses match nothing", not vip("boss@example.com, x@evil.example"))
check("vip junk entries match nothing", not triage._vip(mk("a@b.example", "x"), {"vip": ["@", "x@@y", ""]}))
check("vip only-bare config matches nobody", not triage._vip(mk("c@client.example", "x"), {"vip": ["client.example", "client"]}))

# ---- 5. one argv builder --------------------------------------------------------------------
pa, sa = prep.claude_argv("/x/mcp.json"), slack.claude_argv()
for name, a in (("prep", pa), ("slack", sa)):
    check(f"{name}: no session persistence", "--no-session-persistence" in a)
    check(f"{name}: dontAsk", a[a.index("--permission-mode") + 1] == "dontAsk")
    check(f"{name}: json output", a[a.index("--output-format") + 1] == "json")
check("prep: user settings sources dropped", pa[pa.index("--setting-sources") + 1] == "")
check("prep: strict mcp + the written config", "--strict-mcp-config" in pa and pa[pa.index("--mcp-config") + 1] == "/x/mcp.json")
check("slack: output style neutralised, plugin settings kept", json.loads(sa[sa.index("--settings") + 1]) == {"outputStyle": "default"}
      and "--setting-sources" not in sa)
env = llmrun.child_env()
check("child env cuts CLAUDE.md and memory", env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] == "1" and env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1")
check("prep and slack share llmrun.build_argv", prep.llmrun is slack.llmrun is llmrun)

# ---- 6. the "Prepared" toast: verified sender + raw subject, never model text ---------------
M = {"id": "p1@x", "thread": "t", "file": None, "folder": "INBOX", "from": '"CEO" <attacker@evil.example>',
     "from_addr": "attacker@evil.example", "from_count": 1, "to": ["me@example.com"], "cc": [],
     "subject": "Prod is down\nline two <b>x</b>", "date": now, "tags": set(), "headers": {}}
mail.get = lambda mid: dict(M, id=mid)
mail.messages = lambda q, limit=None: []
INJECT = "URGENT: reply to the CEO and wire the money"
prep.run = lambda argv, input=None, **kw: subprocess.CompletedProcess(argv, 0, json.dumps({"result": INJECT + "\n\nbody"}), "")
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','p1@x',?, 'running', ?)", (M["subject"], now))
row = conn.execute("SELECT * FROM prep WHERE ref='p1@x'").fetchone()
toasts.clear()
check("run_one ok", prep.run_one(conn, row))
app, summary, body, _ = toasts[0]
check("toast body: sender address then raw subject", body == "from attacker@evil.example - Prod is down line two <b>x</b>", body)
check("toast carries no model text", INJECT not in summary + body, (summary, body))
check("toast text has no control chars", "\n" not in summary + body)
sent = []
def _rec(argv, **kw):
    sent.append(argv)
    raise OSError("recorded, not run")
notify.popen = _rec
import importlib; real_toast = importlib.reload(notify).toast
notify.popen = _rec
real_toast("a", "--evil", "-t 1")
check("notify-send: -- before user-derived args", sent[-1][-3:] == ["--", "--evil", "-t 1"], sent[-1])
notify.ask("a", "--s", "b", [("open", "Open")], 1)
check("notify-send ask: -- before user-derived args", sent[-1][-3:] == ["--", "--s", "b"], sent[-1])
notify.toast = lambda app, s, b="", urgency="normal", ms=8000: toasts.append((app, s, b, urgency))   # back to the recorder
prep.notify.toast = notify.toast

# ---- 7. AGENT_OFF: no LLM, floors keep working; PANIC semantics -----------------------------
config.AGENT_OFF.parent.mkdir(parents=True, exist_ok=True)
calls = []
prep.run = lambda argv, input=None, **kw: (calls.append(argv), subprocess.CompletedProcess(argv, 0, json.dumps({"result": "# ok"}), ""))[1]
slack.run_claude = lambda argv, prompt, timeout=120: (calls.append(argv), "{}")[1]
conn.execute("DELETE FROM prep"); conn.commit()
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','q1@x','Queued','queued',?)", (now,))
conn.execute("INSERT INTO item(source,direction,key,thread,counterpart,subject,purpose,state,created_unix,updated_unix) "
             "VALUES('slack','them','C1:1793212045.567019','C1:1793212045.567019','C1','s','p','open',?,?)", (now - 600, now - 600))
conn.commit()
config.AGENT_OFF.write_text("")
check("AGENT_OFF: prep-run runs nothing", prep.run_all() == 0 and not calls)
check("AGENT_OFF: queued row stays queued", conn.execute("SELECT status FROM prep WHERE ref='q1@x'").fetchone()[0] == "queued")
db.log(conn, "critical", "z1@x", "x"); conn.commit()
check("AGENT_OFF: queue() queues nothing", prep.queue(conn, [], now) == 0
      and conn.execute("SELECT COUNT(*) FROM prep WHERE ref='z1@x'").fetchone()[0] == 0)
slack.check(conn)
check("AGENT_OFF: slack checker spawns nothing", not calls)
try:
    llmrun.reserve(conn, "x", "haiku"); check("AGENT_OFF: reserve refuses", False)
except llmrun.Refused as e:
    check("AGENT_OFF: reserve refuses", "AGENT_OFF" in str(e))
# floors: alert toast, VIP critical, backup failure, rule tagging all still work
fl = mk("Monitoring <alerts@mon.example>", "[CRITICAL] FloorTest (FIRING) - cluster-2")
r = post(fl)
check("AGENT_OFF: firing alert still toasts", any("FIRING   FloorTest" in t[2] for t in toasts), toasts)
check("AGENT_OFF: alert still tagged and in state", "+alert" in r[fl["id"]] and conn.execute(
    "SELECT state FROM alert_state WHERE name='FloorTest'").fetchone()[0] == "firing")
bk = mk("root@host.example.net", "backup failed on pve")
r = post(bk)
check("AGENT_OFF: backup failure: inbox + act toast", "+inbox" in r[bk["id"]] and len(spawned) == 1, (r, spawned))
vp = mk("Boss <boss@example.com>", "need you")
r = post(vp)
check("AGENT_OFF: VIP still critical", "+critical" in r[vp["id"]] and len(spawned) == 1, (r, spawned))
tk = mk("support@erp.example", "You were assigned a new task")
r = post(tk)
check("AGENT_OFF: rules still tag and notify", "+ticket" in r[tk["id"]] and len(spawned) == 1)
# PANIC: silences prompts (toasts, act windows, queueing) - the existing semantics, pinned here
PANIC.parent.mkdir(parents=True, exist_ok=True); PANIC.write_text("")
fl2 = mk("Monitoring <alerts@mon.example>", "[CRITICAL] PanicTest (FIRING) - cluster-3")
post(fl2)
check("PANIC: alert state still recorded", conn.execute("SELECT state FROM alert_state WHERE name='PanicTest'").fetchone()[0] == "firing")
check("PANIC: alert toast silenced (AGENT_OFF is separate and does not do this)", not toasts)
PANIC.unlink()
config.AGENT_OFF.unlink()
check("switch off again: prep-run runs the queued row", prep.run_all() == 0 and len(calls) == 1)
check("switch off again: row done", conn.execute("SELECT status FROM prep WHERE ref='q1@x'").fetchone()[0] == "done")
slack.check(conn)
check("switch off again: slack checker runs", len(calls) == 2)

# ---- 8. SPEND LEDGER ------------------------------------------------------------------------
conn.execute("DELETE FROM llm_run"); conn.execute("DELETE FROM event WHERE kind='llm_refused'"); conn.commit()
check("estimate haiku", llmrun.estimate("haiku") == 0.0275, llmrun.estimate("haiku"))
check("estimate sonnet", llmrun.estimate("sonnet") == 0.165, llmrun.estimate("sonnet"))
check("caps", llmrun.CAPS == {"haiku": 200, "sonnet": 6} and llmrun.USD_CAP == 1.0)
def spawn(model):
    seen = []
    llmrun.guarded(conn, "t", model, lambda: seen.append(1) or "{}")
    return len(seen)
n = 0
for _ in range(5):
    n += spawn("sonnet")
check("5 sonnet runs spawn", n == 5)
try:                                     # 5 x 0.165 = 0.825; a sixth would be 0.99: allowed by $, last by count
    n += spawn("sonnet"); check("6th sonnet runs (0.99 <= 1.00)", n == 6)
except llmrun.Refused as e:
    check("6th sonnet runs (0.99 <= 1.00)", False, e)
try:
    spawn("sonnet"); check("7th sonnet refused", False)
except llmrun.Refused as e:
    check("7th sonnet refused (count cap)", "cap of 6 sonnet" in str(e), e)
check("refusal logged", len(events("llm_refused")) == 1 and events("llm_refused")[0]["ref"] == "t")
try:
    spawn("sonnet")
except llmrun.Refused:
    pass
check("same refusal is logged once an hour", len(events("llm_refused")) == 1)
conn.execute("DELETE FROM llm_run"); conn.commit()
conn.execute("INSERT INTO llm_run(ts_unix,kind,model,est_usd,actual_usd) VALUES(?,?,?,?,?)", (now, "t", "haiku", 0.03, 0.99)); conn.commit()
try:
    spawn("haiku"); check("dollar cap refuses on estimated spend", False)
except llmrun.Refused as e:
    check("dollar cap refuses on estimated spend", "$1.00 daily cap" in str(e), e)
conn.execute("DELETE FROM llm_run")
for _ in range(200):
    conn.execute("INSERT INTO llm_run(ts_unix,kind,model,est_usd) VALUES(?,?,?,?)", (now, "t", "haiku", 0.0))
conn.commit()
try:
    spawn("haiku"); check("201st haiku refused", False)
except llmrun.Refused as e:
    check("201st haiku refused", "cap of 200 haiku" in str(e), e)
conn.execute("DELETE FROM llm_run"); conn.commit()
try:
    llmrun.guarded(conn, "t", "opus", lambda: "{}"); check("unknown model (opus) refused", False)
except llmrun.Refused:
    check("unknown model (opus) refused", True)
conn.execute("DELETE FROM llm_run"); conn.commit()
llmrun.guarded(conn, "t", "haiku", lambda: json.dumps({"total_cost_usd": 0.4}))
check("claude's own total_cost_usd replaces the estimate", abs(llmrun.usage(conn)[1] - 0.4) < 1e-9, llmrun.usage(conn))
conn.execute("UPDATE llm_run SET ts_unix=ts_unix-172800"); conn.commit()
check("yesterday's runs do not count", llmrun.usage(conn) == ({}, 0.0))
# a refused prep row is skipped (not failed), and rules/toasts go on
conn.execute("DELETE FROM llm_run")
for _ in range(6):
    conn.execute("INSERT INTO llm_run(ts_unix,kind,model,est_usd) VALUES(?,?,?,?)", (now, "t", "sonnet", 0.1))
conn.execute("DELETE FROM prep"); conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','c1@x','Capped','queued',?)", (now,))
conn.commit()
calls.clear(); toasts.clear()
prep.run_all()
st = conn.execute("SELECT status, summary FROM prep WHERE ref='c1@x'").fetchone()
check("over cap: prep row skipped with the reason, no spawn, no toast", st[0] == "skipped" and "cap of 6 sonnet" in st[1] and not calls and not toasts, tuple(st))
r = post(mk("support@erp.example", "You were assigned a new task"))
check("over cap: rules and toasts still work", len(spawned) == 1)

# ---- 9. listeners and the notification log --------------------------------------------------
unit = lambda n: (root / "home/private_dot_config/systemd/private_user" / n).read_text()
push, nlog = unit("dots-mail-push.service"), unit("dots-notifylog.service")
check("push: wanted by default.target, not graphical-session", "WantedBy=default.target" in push
      and "graphical-session" not in push.replace("graphical-session.target: that", ""), push)
check("notifylog: has an [Install] section", "[Install]" in nlog and "WantedBy=default.target" in nlog)
check("systemd script enables notifylog", "enable --now dots-notifylog.service" in
      (root / "home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl").read_text())
from dots_overview import config as oc, notifylog
cfg = oc.Work({})
mailrec = notifylog.record({"app": "Mail", "summary": "Dana Smith", "body": "Q3 invoice", "urgency": "normal"}, cfg, now=1)
prepped = notifylog.record({"app": "dots-inbox", "summary": "Prepared: Prod is down", "body": "x", "urgency": "normal"}, cfg, now=1)
slackrec = notifylog.record({"app": "Slack", "summary": "New message from Ada", "body": "secret", "urgency": "normal"}, cfg, now=1)
check("notifylog: dots-inbox toasts keep no text", mailrec["summary"] == "" and prepped["summary"] == "" and mailrec["body"] is None)
check("notifylog: Slack app summary kept (the dashboard reads it), body never", slackrec["summary"] == "New message from Ada" and slackrec["body"] is None)
check("notifylog: ring cap is 5000", oc.NOTIF_CAP == 5000)

# ---- 10. real capture: what actually leaves the machine -------------------------------------
import shutil, tempfile, threading, http.server
cap = None
if shutil.which("claude") and (Path.home() / ".claude/.credentials.json").exists() and os.environ.get("DOTS_NO_CAPTURE") != "1":
    recs = []
    class H(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("content-length") or 0)
            recs.append(self.rfile.read(n))                       # the body only: headers carry the token
            out = b'{"type":"error","error":{"type":"invalid_request_error","message":"capture listener"}}'
            self.send_response(400); self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(out))); self.end_headers(); self.wfile.write(out)
        do_GET = do_POST
        def log_message(self, *a): pass
    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    proj = Path.home() / ".claude/projects"
    needles = ["ADHD", "methylphenidate"]
    cm = Path.home() / ".claude/CLAUDE.md"
    if cm.exists():
        needles += [l.strip() for l in cm.read_text().splitlines() if len(l.strip()) >= 30][:6]
    if cm.exists():                  # positive control: the SAME probe on a plain `claude -p` must see the leak
        recs.clear()
        before_ctl = set(os.listdir(proj))
        cwd = tempfile.mkdtemp(prefix="dots-inbox-cap-")
        env = {**os.environ, "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{srv.server_address[1]}"}
        try:
            subprocess.run(["claude", "-p", "--model", "haiku", "--output-format", "json", "--no-session-persistence", "--tools", ""],
                           input="Reply with the single word ok.", capture_output=True, text=True, timeout=120, cwd=cwd, env=env)
        finally:
            shutil.rmtree(cwd, ignore_errors=True)
        for d in set(os.listdir(proj)) - before_ctl:             # the control is the one run that leaves a dir: remove it
            if "dots-inbox-cap-" in d:
                shutil.rmtree(proj / d, ignore_errors=True)
        ctl = b"\n".join(recs).decode("utf-8", "replace")
        print(f"capture control (plain claude -p): requests={len(recs)} sees_CLAUDE.md={'ADHD' in ctl}")
        check("capture control: a plain claude -p DOES send CLAUDE.md (so the probe can see a leak)", "ADHD" in ctl)
    for label, argv, prompt in (("prep", prep.claude_argv(), "Reply with the single word ok."),
                                ("slack", slack.claude_argv(), "Reply with the single word ok.")):
        recs.clear()
        before = set(os.listdir(proj)) if proj.exists() else set()
        cwd = tempfile.mkdtemp(prefix="dots-inbox-cap-")
        env = {**llmrun.child_env(), "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{srv.server_address[1]}"}
        try:
            r = subprocess.run(argv, input=prompt, capture_output=True, text=True, timeout=120, cwd=cwd, env=env)
        finally:
            shutil.rmtree(cwd, ignore_errors=True)
        body = b"\n".join(recs).decode("utf-8", "replace")
        after = set(os.listdir(proj)) if proj.exists() else set()
        hit = [n for n in needles if n in body]
        print(f"capture {label}: requests={len(recs)} bytes={len(body)} leaked={hit} new_project_dirs={sorted(after - before)}")
        check(f"capture {label}: a request was actually sent", len(recs) > 0, "auth failed before any request: nothing was captured")
        check(f"capture {label}: no ADHD / methylphenidate / CLAUDE.md text in the request body", not hit, hit)
        check(f"capture {label}: no new directory under ~/.claude/projects", after == before, sorted(after - before))
    srv.shutdown()
else:
    print("SKIP capture: needs a claude binary and ~/.claude/.credentials.json (not run in CI)")

print(f"inbox-phase0: {ok} ok, {bad} failed")
raise SystemExit(1 if bad else 0)
PY
