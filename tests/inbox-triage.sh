#!/usr/bin/env bash
# dots-inbox triage + alerts, end to end on message dicts. No notmuch, no ollama, no desktop:
# mail.tag, notify.toast/ask, triage.spawn and the model are replaced by recorders.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$root/nix/pkgs/dots-inbox" || exit 1
DOTS_INBOX_TEST=1 DOTS_INBOX_MAIL="$tmp" XDG_CONFIG_HOME="$tmp/cfg" XDG_STATE_HOME="$tmp/state" \
  python3 - <<'PY'
import sys, time
sys.dont_write_bytecode = True
from dots_inbox import alerts, config, db, mail, notify, triage

ok = bad = 0
def check(name, cond, extra=""):
    global ok, bad
    if cond:
        ok += 1
    else:
        bad += 1
        print(f"FAIL {name} {extra}")

CFG = {
    "me": ["me@example.com"],
    "vip": ["boss@example.com", "@client.example"],
    "people": {"domains": ["example.com"]},
    "alerts": {"from": r"alerts@mon\.example"},
    "auth": {"tenant_domains": ["mon.example"]},     # the alert sender is "internal" to this test tenant
    "backup": {"from": r"root@.*\.example\.net", "ok": "backup successful",
               "fail": "backup (failed|error)"},
    "rule": [
        {"name": "github", "from": r".*@github\.com", "policy": "github"},
        {"name": "impersonation", "from": "support@erp.example", "subject": "being impersonated",
         "add": ["security"], "notify": "critical", "critical": "account impersonation"},
        {"name": "ticket", "from": "support@erp.example", "subject": "assigned a new task",
         "add": ["ticket", "erp"], "notify": "now", "critical": "ticket assigned"},
        {"name": "erp noise", "from": "support@erp.example", "add": ["erp", "fyi"], "inbox": False},
        {"name": "lists", "header": {"list-id": "."}, "add": ["newsletter"], "inbox": False},
    ],
}
config.rules = lambda: CFG
config.me = lambda: "me@example.com"
config.panic = lambda: False

tags, toasts, spawned, asked, bodies = [], [], [], [], {}
mail.tag = lambda mid, *ch: tags.append((mid, ch))
mail.body = lambda m, limit=20000: bodies.get(m["id"], "")
notify.toast = lambda app, s, b="", urgency="normal", ms=8000: toasts.append((app, s, b, urgency))
notify.ask = lambda app, s, b, actions, timeout, urgency="normal": asked.append((s, actions)) or ANSWER[0]
ANSWER = [None]
triage.spawn = lambda argv, **kw: spawned.append(argv)
MODEL = [None]
triage._ask_model = lambda prompt: MODEL[0]

conn = db.open_db()
N = [0]
def msg(frm, subject, folder="INBOX", headers=None, age=60, to=None):
    N[0] += 1
    addr = frm.split("<")[-1].rstrip(">")
    return {"id": f"m{N[0]}@t", "thread": "t", "file": None, "folder": folder, "from": frm,
            "from_addr": addr.lower(), "to": to or ["me@example.com"], "cc": [], "subject": subject,
            "date": int(time.time()) - age, "tags": set(), "headers": headers or {}}

def reset():
    tags.clear(); toasts.clear(); spawned.clear(); asked.clear()
def post(*ms):
    """What dots-inbox post-new does, minus the stages that are other agents'."""
    reset()
    new = list(ms)
    triage.run(conn, new); alerts.run(conn, new); triage.notify(conn, new)
    conn.commit()
    return {m["id"]: set(c for t in [x[1] for x in tags if x[0] == m["id"]] for c in t) for m in new}
def t1(m):
    return post(m)[m["id"]]

# ---- folder rules
r = t1(msg("Me <me@example.com>", "Re: x", "Sent Items")); check("sent", "+sent" in r and "+inbox" not in r, r)
r = t1(msg("a@b.example", "x", "Junk Email")); check("junk", "+junk" in r and "+inbox" not in r, r)
r = t1(msg("a@b.example", "x", "Deleted Items")); check("deleted", "+deleted" in r and "+inbox" not in r, r)
check("trash", "+deleted" in t1(msg("a@b.example", "x", "Trash")))
r = t1(msg("a@b.example", "draft", "Drafts")); check("drafts", "+inbox" not in r and not toasts, r)
r = t1(msg("Me <me@example.com>", "copy of mine")); check("own mail in inbox -> sent", "+sent" in r and "+inbox" not in r, r)

# ---- vip, people, rules
m = msg("Boss <boss@example.com>", "need you")
r = t1(m); check("vip tags", {"+vip", "+people", "+inbox", "+critical"} <= r, r)
check("vip critical toast", len(spawned) == 1 and "--urgent" in spawned[0], spawned)
check("vip critical event", conn.execute("SELECT count(*) FROM event WHERE kind='critical' AND ref=?", (m["id"],)).fetchone()[0] == 1)
r = t1(msg("Colleague <pal@example.com>", "lunch?")); check("people domain", {"+people", "+inbox"} <= r, r)
check("people batch toast", len(toasts) == 1 and toasts[0][1].startswith("1 new: 1 people"), toasts)
r = t1(msg("noreply <no-reply@example.com>", "robot")); check("automated is not people", "+people" not in r, r)
m = msg("Support <support@erp.example>", "Mo assigned a new task HD Ticket Fix it")
r = t1(m); check("ticket", {"+ticket", "+erp", "+inbox", "+critical"} <= r, r)
check("ticket event", conn.execute("SELECT count(*) FROM event WHERE kind='critical' AND ref=?", (m["id"],)).fetchone()[0] == 1)
check("ticket toast now", len(spawned) == 1 and "--urgent" not in spawned[0])
m = msg("Support <support@erp.example>", "Security Alert: Your account is being impersonated")
r = t1(m); check("impersonation", {"+security", "+inbox"} <= r, r)
check("impersonation urgent", len(spawned) == 1 and "--urgent" in spawned[0])
r = t1(msg("Support <support@erp.example>", "Work Anniversary Reminder")); check("erp noise", "+fyi" in r and "+inbox" not in r and not toasts and not spawned, r)
r = t1(msg("L <l@lists.example>", "weekly", headers={"list-id": "<x.lists.example>"})); check("list header", "+newsletter" in r and "+inbox" not in r, r)

# ---- GitHub, each reason
def gh(reason, subject="Re: [org/repo] fix thing (PR #7)", frm="Alice <notifications@github.com>", body=""):
    m = msg(frm, subject, headers={"x-github-reason": reason})
    bodies[m["id"]] = body
    return m
for reason in ("review_requested", "mention", "team_mention", "assign", "author"):
    m = gh(reason); r = t1(m)
    check(f"gh {reason} inbox", "+inbox" in r and "+github" in r, r)
    check(f"gh {reason} toast", len(spawned) == 1 and not toasts, (spawned, toasts))
m = gh("review_requested"); r = t1(m); check("gh review is pr", "+pr" in r, r)
reset(); m = gh("review_requested"); post(m)
check("gh toast titled with repo and PR", triage.describe(m)[0] == "org/repo PR #7", triage.describe(m))
for reason in ("push", "subscribed", "comment", "manual"):
    r = t1(gh(reason)); check(f"gh {reason} quiet", {"+github", "+fyi"} <= r and "+inbox" not in r and not spawned and not toasts, r)
r = t1(gh("state_change", body="Merged #7. You are receiving this because you authored the thread."))
check("gh own PR merged -> inbox batch", "+inbox" in r and len(toasts) == 1 and not spawned, (r, toasts))
r = t1(gh("state_change", body="Closed. You are receiving this because you are subscribed to this thread."))
check("gh others' PR merged quiet", "+inbox" not in r and not toasts, r)
r = t1(gh("ci_activity", subject="Re: [org/repo] Run failed: CI - main (PR #7)")); check("gh ci failure now", "+inbox" in r and len(spawned) == 1, (r, spawned))
r = t1(gh("ci_activity", subject="Re: [org/repo] Run passed: CI - main (PR #7)")); check("gh ci success quiet", "+inbox" not in r and not spawned, r)
r = t1(gh("author", frm='"bot[bot]" <notifications@github.com>')); check("gh bot comment: inbox, no toast", "+inbox" in r and not spawned and not toasts, r)
r = t1(gh("security_alert", subject="[GitHub] Your Dependabot alerts for the week", frm="GitHub <noreply@github.com>")); check("gh dependabot digest", "+fyi" in r and "+inbox" not in r, r)
acct = lambda s: msg("GitHub <noreply@github.com>", s)
r = t1(acct("[GitHub] A new SSH authentication public key was added to your account")); check("gh ssh key added", {"+security", "+inbox"} <= r and len(toasts) == 1, (r, toasts))
r = t1(acct("[GitHub] A personal access token (classic) was regenerated")); check("gh token regenerated", "+security" in r, r)
r = t1(acct("[GitHub] Your OAuth application was added")); check("gh oauth added", "+security" in r, r)
r = t1(acct("[GitHub] Your personal access token is expiring soon")); check("gh expiry: inbox, silent", "+inbox" in r and "+security" not in r and not toasts and not spawned, (r, toasts))
r = t1(acct("[GitHub] Payment Receipt for Org")); check("gh billing quiet", "+inbox" not in r and "+fyi" in r, r)
r = t1(acct("[GitHub] organization has received personal access token requests")); check("gh org token requests not security", "+security" not in r, r)
r = t1(acct("ubuntu-latest migration begins")); check("gh announcement quiet", "+inbox" not in r, r)

# ---- model
MODEL[0] = '{"class": "vendor"}'
r = t1(msg("Shop <hi@shop.example>", "your order")); check("model vendor", "+vendor" in r and "+inbox" not in r, r)
MODEL[0] = '{"class": "people"}'
r = t1(msg("Human <h@else.example>", "question")); check("model people", {"+people", "+inbox"} <= r, r)
MODEL[0] = '{"class": "bogus"}'
r = t1(msg("X <x@else.example>", "what")); check("model garbage -> inbox", "+inbox" in r, r)
MODEL[0] = None
r = t1(msg("X <x@else.example>", "what")); check("model down -> inbox", "+inbox" in r, r)

# ---- alerts
def al(state, name="NodeNotReady", scope="cluster-1", age=0, sev="CRITICAL"):
    return msg("Alerts <alerts@mon.example>", f"[{sev}] {name} ({state}) — {scope}", age=age,
               headers={"x-ms-exchange-organization-authas": "Internal"})
def row(name="NodeNotReady", scope="cluster-1"):
    return conn.execute("SELECT * FROM alert_state WHERE name=? AND scope=?", (name, scope)).fetchone()
H = 3600
r = t1(al("FIRING", age=5 * H + 1800)); r0 = row()
check("alert tags", "+alert" in r and "+inbox" not in r, r)
check("first firing: state", r0 and r0["state"] == "firing" and r0["repeats"] == 1)
check("first firing: toast", len(toasts) == 1 and toasts[0][1] == "Alerts: 1 firing, 0 resolved", toasts)
check("first firing: event", conn.execute("SELECT count(*) FROM event WHERE kind='alert_firing'").fetchone()[0] == 1)
t1(al("FIRING", age=4 * H)); t1(al("FIRING", age=3 * H))
check("repeats silent", not toasts and row()["repeats"] == 3, (toasts, dict(row())))
check("repeat adds no event", conn.execute("SELECT count(*) FROM event WHERE kind='alert_firing'").fetchone()[0] == 1)
t1(al("RESOLVED", age=60))
check("resolve >= 30 min notifies", len(toasts) == 1 and toasts[0][1] == "Alerts: 0 firing, 1 resolved", toasts)
check("resolve state+event", row()["state"] == "resolved" and conn.execute("SELECT count(*) FROM event WHERE kind='alert_resolved'").fetchone()[0] == 1)
t1(al("FIRING", age=30))
check("re-fire within 6 h silent", not toasts and row()["state"] == "firing", toasts)
check("re-fire still logs event", conn.execute("SELECT count(*) FROM event WHERE kind='alert_firing'").fetchone()[0] == 2)
t1(al("RESOLVED", age=10))
check("short fire resolves silently", not toasts and row()["state"] == "resolved", toasts)
# a new alert fired 10 minutes ago and resolved now: under 30 min, silent
t1(al("FIRING", name="Short", age=600)); t1(al("RESOLVED", name="Short", age=0))
check("<30 min resolution silent", not toasts and row("Short")["state"] == "resolved", toasts)
# stale: firing, no mail for 7 h -> not listed, not notified; a later fire notifies again
conn.execute("INSERT INTO alert_state VALUES('Old','c','CRITICAL','firing',?,?,4,NULL)", (int(time.time()) - 9 * H, int(time.time()) - 7 * H))
check("stale not in firing list", all(r["name"] != "Old" for r in alerts.firing(conn)))
t1(al("FIRING", name="Old", scope="c", age=0))
check("fire after stale notifies", len(toasts) == 1 and "Old" in toasts[0][2], toasts)
# batching: several transitions, ONE toast
m1, m2, m3 = al("FIRING", name="A1"), al("FIRING", name="A2"), al("FIRING", name="A3")
post(m1, m2, m3)
check("one batched toast per run", len(toasts) == 1 and toasts[0][1] == "Alerts: 3 firing, 0 resolved" and toasts[0][2].count("\n") == 2, toasts)
r = t1(al("FIRING", name="Backlog", age=2 * 86400)); check("old mail is backlog, no toast", not toasts and row("Backlog")["state"] == "firing", toasts)

# ---- backup
r = t1(msg("Pve <root@host1.example.net>", "vzdump backup status (host1): backup successful"))
check("backup ok silent", {"+backup"} <= r and "+inbox" not in r and "+alert" not in r and not toasts and not spawned, (r, toasts))
m = msg("Pve <root@host1.example.net>", "vzdump backup status (host1): backup failed")
r = t1(m); check("backup failure alerts", {"+alert", "+inbox"} <= r, r)
check("backup failure notifies now", len(spawned) == 1, spawned)
check("backup failure not in alert_state", conn.execute("SELECT count(*) FROM alert_state WHERE name LIKE '%vzdump%'").fetchone()[0] == 0)

# ---- batching + PANIC
reset()
people = [msg("P%d <p%d@example.com>" % (i, i), "hello %d" % i) for i in range(3)]
sec = msg("Support <support@erp.example>", "Work Anniversary")  # fyi, must not count
post(*people, sec)
check("batch: one summary toast", len(toasts) == 1 and toasts[0][1] == "3 new: 3 people", toasts)
config.panic = lambda: True
post(msg("Boss <boss@example.com>", "urgent"), msg("Pal <pal@example.com>", "hi"), al("FIRING", name="Quiet"))
check("PANIC silences everything", not toasts and not spawned, (toasts, spawned))
config.panic = lambda: False

# ---- backlog cap
reset()
many = [gh("review_requested", subject=f"Re: [org/repo] change {i} (PR #{i})") for i in range(8)]
post(*many)
check("max individual toasts, rest folded", len(spawned) == triage.MAX_NOW and len(toasts) == 1 and toasts[0][1].startswith("3 new"), (len(spawned), toasts))
old = gh("review_requested"); old["date"] = int(time.time()) - 3 * 86400
post(old); check("old mail never toasts", not spawned and not toasts)

# ---- act
class A: id = "m1@t"; urgent = False
mail.get = lambda mid: msg("Alice <notifications@github.com>", "Re: [org/repo] x (PR #3)", headers={"x-github-reason": "review_requested"})
ANSWER[0] = "done"; reset(); triage.act(A)
check("act done tags", tags == [("m1@t", ("-inbox", "+done"))], tags)
check("act offers open and done", [k for k, _ in asked[0][1]] == ["open", "done"], asked)
ANSWER[0] = "open"; reset(); triage.act(A)
check("act open spawns aerc", spawned and spawned[0][0] == "ghostty" and spawned[0][-1] == "aerc", spawned)
ANSWER[0] = None; reset(); triage.act(A); check("act no answer: nothing", not tags and not spawned)

# ---- retriage never re-inboxes archived mail
d = triage.decide(msg("Boss <boss@example.com>", "hi"), CFG)
ch = triage._changes(d, {"tags": {"done"}}, retriage=True)
check("retriage keeps done mail out of inbox", "+inbox" not in ch, ch)

print(f"inbox-triage: {ok} ok, {bad} failed")
sys.exit(1 if bad else 0)
PY
