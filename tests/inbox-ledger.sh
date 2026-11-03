#!/usr/bin/env bash
# dots-inbox ledger + Slack: sent mail opens a waiting item, the reply closes it with the
# purpose in the toast, drafts are RFC 5322 files in Drafts/cur, the Slack hook parses ts /
# permalink / neither and spools when the store is busy, the checker never calls Claude
# without open items and always carries the send tools in --disallowedTools.
#
# Everything is in-process against a temp mail store: the Ollama call, notify, notmuch tagging,
# the detached reply-act spawn and the Claude call are all replaced. No network, no real
# Slack, no real claude, nothing under ~/Mail or ~/.claude is touched.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
pkg="$root/nix/pkgs/dots-inbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Mail/.state" "$tmp/Mail/work" "$tmp/cfg/dots-mail" "$tmp/state" "$tmp/home" "$tmp/ov/declared"
printf 'MAIL_ADDRESS="me@example.test"\n' > "$tmp/cfg/dots-mail/account.conf"
printf '{"v":1,"sess":"sess-1","ref":"TASK-9","uuid":"abcdef0123","title":"t"}\n' > "$tmp/ov/declared/sess-1.json"

export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/cfg" XDG_STATE_HOME="$tmp/state"
export DOTS_INBOX_TEST=1 DOTS_INBOX_MAIL="$tmp/Mail" DOTS_OVERVIEW_STATE_DIR="$tmp/ov" PYTHONPATH="$pkg"
unset DOTS_INBOX_TERMINAL

cat > "$tmp/t.py" <<'PY'
import contextlib, email, email.policy, io, json, os, sqlite3, subprocess, sys, time
from pathlib import Path
from dots_inbox import config, db, ledger, mail, notify, slack

fails = 0
def check(name, cond):
    global fails
    print(("  ok   " if cond else "  FAIL ") + name)
    fails += 0 if cond else 1

# ---- seams ------------------------------------------------------------------------------
LLM = {"fn": None}                      # per-test model behaviour; None = model down
toasts, tags, spawned, asks, claude_calls = [], [], [], [], []
ledger.llm_json = lambda system, user, timeout=25: LLM["fn"](system, user) if LLM["fn"] else None
notify.toast = lambda app, summary, body="", urgency="normal", ms=8000: toasts.append((app, summary, body, urgency))
notify.ask = lambda app, summary, body, actions, timeout, urgency="normal": (asks.append((summary, body, actions)), "done")[1]
mail.tag = lambda mid, *ch: tags.append((mid, ch))
mail.body = lambda m, limit=20000: m.get("_body", "")
ledger.spawn_reply_act = lambda iid: spawned.append(iid)
BODIES = {}
mail.get = lambda mid: BODIES.get(mid)
nm_calls = []
ledger.notmuch_new = lambda: nm_calls.append(1)

def model(sys_hint, **out):
    def fn(system, user):
        return out if sys_hint in system else {}
    return fn

def msg(mid, thread, frm, to, subject, body="", tags=(), date=None, hdr=None, folder="INBOX"):
    return {"id": mid, "thread": thread, "file": None, "folder": folder, "from": frm,
            "from_addr": frm.split("<")[-1].strip("> "), "to": to, "cc": [],
            "subject": subject, "date": date or int(time.time()), "tags": set(tags),
            "headers": hdr or {}, "_body": body}

def reset():
    toasts.clear(); tags.clear(); spawned.clear(); asks.clear(); claude_calls.clear()

conn = db.open_db()
def items(**w):
    conn.commit()                       # the hook opens its own connection: ours must not hold the write lock
    q = "SELECT * FROM item" + (" WHERE " + " AND ".join(f"{k}=?" for k in w) if w else "")
    return conn.execute(q, tuple(w.values())).fetchall()
def events(kind):
    return conn.execute("SELECT * FROM event WHERE kind=?", (kind,)).fetchall()

ME = "me@example.test"
now = int(time.time())

# ---- 1. sent mail opens an item ---------------------------------------------------------
LLM["fn"] = model("expects a reply", expects_reply=True, purpose="the Q3 numbers by Friday")
sent = msg("s1@x", "T1", "Me <me@example.test>", ["ana@example.test"], "Q3 numbers", "Can you send them?",
           tags={"sent"}, date=now - 100, folder="Sent Items")
ledger.on_mail(conn, [sent])
it = items(key="s1@x")
check("sent mail opens a 'them' item", len(it) == 1 and it[0]["direction"] == "them" and it[0]["state"] == "open")
check("purpose comes from the model", it and it[0]["purpose"] == "the Q3 numbers by Friday")
check("counterpart is the first To", it and it[0]["counterpart"] == "ana@example.test")
check("sent message tagged +waiting", ("s1@x", ("+waiting",)) in tags)

# a second sent mail in the same thread does not open a second item
ledger.on_mail(conn, [msg("s1b@x", "T1", "Me <me@example.test>", ["ana@example.test"], "Re: Q3 numbers", tags={"sent"})])
check("one open item per thread", len(items(thread="T1")) == 1)

# model down -> purpose = subject, still remembered
LLM["fn"] = None
ledger.on_mail(conn, [msg("s2@x", "T2", "Me <me@example.test>", ["bob@example.test"], "Access request", tags={"sent"})])
it = items(key="s2@x")
check("model down: item opens with subject as purpose", len(it) == 1 and it[0]["purpose"] == "Access request")

# model says no reply expected / no-reply recipient / list mail
LLM["fn"] = model("expects a reply", expects_reply=False, purpose="fyi")
ledger.on_mail(conn, [msg("s3@x", "T3", "Me <me@example.test>", ["cy@example.test"], "FYI", tags={"sent"})])
check("no reply expected: no item", not items(key="s3@x"))
LLM["fn"] = None
ledger.on_mail(conn, [msg("s4@x", "T4", "Me <me@example.test>", ["noreply@example.test"], "x", tags={"sent"}),
                      msg("s5@x", "T5", "Me <me@example.test>", ["list@example.test"], "x", tags={"sent"},
                          hdr={"list-id": "<l.example.test>"})])
check("no-reply and list recipients open nothing", not items(key="s4@x") and not items(key="s5@x"))
ledger.on_mail(conn, [msg("d1@x", "T6", "Me <me@example.test>", ["ana@example.test"], "draft", tags={"sent"}, folder="Drafts")])
check("drafts are ignored", not items(key="d1@x"))

# ---- 2. the reply closes it, and the toast says what it was for ---------------------------
reset()
LLM["fn"] = model("what the reply says", summary="numbers attached, totals up 4%")
rep = msg("r1@x", "T1", "Ana Ruiz <ana@example.test>", [ME], "Re: Q3 numbers", "Attached.", tags={"people"}, date=now)
ledger.on_mail(conn, [rep])
it = items(key="s1@x")[0]
check("reply marks the item replied", it["state"] == "replied" and it["reply_ref"] == "r1@x" and it["reply_unix"] == now)
check("reply summary stored", it["reply_summary"] == "numbers attached, totals up 4%")
check("reply event logged", any("numbers attached" in e["detail"] and e["ref"] == str(it["id"]) for e in events("reply")))
check("toast names the replier and subject", toasts and toasts[0][1] == "Ana Ruiz replied — Q3 numbers")
check("toast body has purpose and summary", toasts and "You asked: the Q3 numbers by Friday" in toasts[0][2]
      and "They said: numbers attached" in toasts[0][2])
check("normal urgency, app Mail", toasts and toasts[0][0] == "Mail" and toasts[0][3] == "normal")
check("reply-act spawned for the item", spawned == [it["id"]])
check("waiting tag removed", ("s1@x", ("-waiting",)) in tags)

# vip thread -> critical
LLM["fn"] = None
reset()
ledger.on_mail(conn, [msg("r2@x", "T2", "Bob <bob@example.test>", [ME], "Re: Access request", tags={"vip", "people"}, date=now)])
check("vip reply is critical", toasts and toasts[0][3] == "critical")

# unrelated / alert / older-than-ask mail does not close anything
ledger.on_mail(conn, [msg("s6@x", "T7", "Me <me@example.test>", ["dee@example.test"], "Ask", tags={"sent"}, date=now)])
reset()
ledger.on_mail(conn, [msg("a1@x", "T7", "Mon <alerts@example.test>", [ME], "Re: Ask", tags={"alert"}, date=now + 5),
                      msg("a2@x", "T7", "Dee <dee@example.test>", [ME], "Re: Ask", date=now - 9999)])
check("alert-tagged and pre-dating mail do not close an item", items(key="s6@x")[0]["state"] == "open" and not toasts)

# ---- 3. PANIC silences the toasts -------------------------------------------------------
(config.PANIC.parent).mkdir(parents=True, exist_ok=True)
config.PANIC.write_text("")
reset()
ledger.on_mail(conn, [msg("r3@x", "T7", "Dee <dee@example.test>", [ME], "Re: Ask", "ok", date=now + 10)])
check("PANIC: item still closes", items(key="s6@x")[0]["state"] == "replied")
check("PANIC: no toast, no reply-act", not toasts and not spawned)
config.PANIC.unlink()

# ---- 4. the user's own reply closes a 'me' item ------------------------------------------
LLM["fn"] = model("what do they need", needs="approve the access change")
reset()
ledger.on_mail(conn, [msg("i1@x", "T8", "Eve <eve@example.test>", [ME], "Access change", "please approve", tags={"people"})])
owed = items(key="i1@x")
check("direct person mail opens a 'me' item", len(owed) == 1 and owed[0]["direction"] == "me"
      and owed[0]["purpose"] == "approve the access change")
check("no toast for a new 'me' item", not toasts)
ledger.on_mail(conn, [msg("i2@x", "T8", "Me <me@example.test>", ["eve@example.test"], "Re: Access change", tags={"sent"})])
check("sending a reply closes the 'me' item", items(key="i1@x")[0]["state"] == "done")
# list/newsletter mail to me opens nothing
ledger.on_mail(conn, [msg("n1@x", "T9", "News <news@example.test>", [ME], "Digest", tags={"people", "newsletter"})])
check("newsletter opens nothing", not items(key="n1@x"))

# ---- 5. drafts ---------------------------------------------------------------------------
BODIES["s1@x"] = dict(sent, _body="Can you send them?")
BODIES["r1@x"] = dict(rep, headers={"references": "<root@x> <s1@x>"})
LLM["fn"] = lambda system, user: {"reply": "Thanks Ana, got them."}
iid = items(key="s1@x")[0]["id"]
text = ledger.draft(conn, iid)
files = list((config.BOX / "Drafts" / "cur").glob("*"))
check("draft text saved to item.draft", text == "Thanks Ana, got them." and items(key="s1@x")[0]["draft"] == text)
check("draft file lands in Drafts/cur with flags DS", len(files) == 1 and files[0].name.endswith(":2,DS"))
dm = email.message_from_bytes(files[0].read_bytes(), policy=email.policy.default) if files else None
check("draft is RFC 5322 with threading headers", dm is not None and dm["In-Reply-To"] == "<r1@x>"
      and "<s1@x>" in dm["References"] and dm["From"] == ME and "ana@example.test" in dm["To"]
      and dm["Subject"] == "Re: Q3 numbers" and dm["Message-ID"] and dm["Date"]
      and dm.get_content().strip() == "Thanks Ana, got them.")
check("notmuch new was run after writing the draft", nm_calls == [1])
check("draft never touches any send path", not any(hasattr(ledger, n) for n in ("send", "smtp", "sendmail")))
LLM["fn"] = None
check("model down: no draft, no file", ledger.draft(conn, iid) is None and len(list((config.BOX / "Drafts" / "cur").glob("*"))) == 1)

# ---- 6. hygiene --------------------------------------------------------------------------
LLM["fn"] = None
ledger.on_mail(conn, [msg("o1@x", "T10", "Me <me@example.test>", ["fay@example.test"], "Old ask", tags={"sent"}, date=now - 6 * 86400)])
conn.execute("UPDATE item SET created_unix=? WHERE key='o1@x'", (now - 8 * 86400,))
ledger.on_mail(conn, [msg("o2@x", "T11", "Me <me@example.test>", ["fay@example.test"], "Ancient ask", tags={"sent"})])
conn.execute("UPDATE item SET created_unix=? WHERE key='o2@x'", (now - 30 * 86400,))
ledger.sweep(conn); ledger.sweep(conn)
check("3 working days without reply: nudge, once", len([e for e in events("nudge") if e["ref"] == str(items(key="o1@x")[0]["id"])]) == 1)
check("21 days: dropped", items(key="o2@x")[0]["state"] == "dropped")
check("fresh item is not nudged", not [e for e in events("nudge") if e["ref"] == str(items(key="s6@x")[0]["id"])])

# ---- 7. waiting table ----------------------------------------------------------------------
tbl = ledger.render(items(key="o1@x"))
check("waiting table has the columns", all(w in tbl.split("\n")[0] for w in ("id", "src", "who", "age", "subject", "purpose", "state")) and "fay@example.test" in tbl)

# ---- 8. Slack hook -------------------------------------------------------------------------
LLM["fn"] = lambda system, user: {"purpose": "ask Gus for the deploy window"}
def hook(tool_input, response, session="sess-1"):
    conn.commit()
    sys.stdin = io.StringIO(json.dumps({"session_id": session, "tool_name": slack.SEND_TOOL,
                                        "tool_input": tool_input, "tool_response": response, "cwd": "/x"}))
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = slack._cmd_sent(None)
    return rc, out.getvalue()
real = [{"type": "text", "text": json.dumps({"message_link": "https://x.slack.com/archives/C1/p1793212045567019",
        "message_context": {"message_ts": "1793212045.567019", "channel_id": "C1"}})}]
rc, out = hook({"channel_id": "C1", "message": "when is the deploy window?"}, real)
s = items(key="C1:1793212045.567019")
check("hook: exit 0 and silent stdout", rc == 0 and out == "")
check("hook: ts parsed from the real response shape", len(s) == 1 and s[0]["source"] == "slack" and s[0]["direction"] == "them")
check("hook: thread, counterpart, purpose, session, task", s and s[0]["thread"] == "C1:1793212045.567019"
      and s[0]["counterpart"] == "C1" and s[0]["purpose"] == "ask Gus for the deploy window"
      and s[0]["session"] == "sess-1" and s[0]["task_ref"] == "TASK-9")
hook({"channel_id": "C2", "message": "in thread", "thread_ts": "1793000000.000100"}, "posted https://x.slack.com/archives/C2/p1793000111222333")
s = items(key="C2:1793000111.222333")
check("hook: ts parsed from a permalink; thread_ts wins for thread", len(s) == 1 and s[0]["thread"] == "C2:1793000000.000100")
LLM["fn"] = None
hook({"channel_id": "C3", "message": "x" * 300}, {"ok": True})
s = [r for r in items(source="slack") if r["counterpart"] == "C3"]
check("hook: no ts -> channel:session:<unix>, thread unknown", len(s) == 1 and s[0]["key"].startswith("C3:session:") and s[0]["thread"] is None)
check("hook: model down -> purpose is the first 120 chars", s and len(s[0]["purpose"]) == 120)
hook({"channel_id": "C1", "message": "dup"}, real)
check("hook: same message twice is one item", len(items(key="C1:1793212045.567019")) == 1)
check("hook: no channel -> nothing", hook({"message": "x"}, real)[0] == 0)
sys.stdin = io.StringIO("not json at all")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = slack._cmd_sent(None)
check("hook: garbage stdin still exits 0 silently", rc == 0 and buf.getvalue() == "")

# ---- 9. hook with a locked store spools, then imports --------------------------------------
n_before = len(items(source="slack"))
config.mounted = lambda: False
hook({"channel_id": "C4", "message": "while locked"}, "1793300000.000001")
config.mounted = lambda: True
check("locked store: record spooled, not stored", slack.SPOOL.exists() and len(items(source="slack")) == n_before
      and oct(slack.SPOOL.stat().st_mode & 0o777) == "0o600")
slack.import_pending(conn)
check("spool imported on the next run", len(items(key="C4:1793300000.000001")) == 1 and not slack.SPOOL.exists())
# a busy (write-locked) database also spools instead of waiting
slack.LOCK_TIMEOUT = 0.2
other = sqlite3.connect(config.DB, timeout=1, isolation_level=None)
other.execute("BEGIN EXCLUSIVE")
t0 = time.time()
hook({"channel_id": "C5", "message": "while busy"}, "1793300001.000002")
fast = time.time() - t0 < 3
other.execute("ROLLBACK"); other.close()
check("busy store: spooled quickly", slack.SPOOL.exists() and fast and not items(key="C5:1793300001.000002"))
slack.import_pending(conn)
check("busy spool imported later", len(items(key="C5:1793300001.000002")) == 1)

# ---- 10. the checker -----------------------------------------------------------------------
def fake_claude(output):
    def run(argv, prompt, timeout=120):
        claude_calls.append((argv, prompt, timeout))
        if isinstance(output, Exception):
            raise output
        return output
    return run

conn.execute("UPDATE item SET state='done' WHERE source='slack'")
reset()
slack.run_claude = fake_claude("{}")
slack.check(conn)
check("checker: no open Slack items -> claude never invoked", not claude_calls)
conn.execute("INSERT INTO item(source,direction,key,thread,counterpart,subject,purpose,state,created_unix,updated_unix) "
             "VALUES('slack','them','C9:1700000000.000001','C9:1700000000.000001','C9','old','ancient','open',?,?)",
             (now - 20 * 86400,) * 2)
reset()
slack.check(conn)
check("checker: items older than 14 days are not asked about", not claude_calls)
conn.execute("DELETE FROM item WHERE key LIKE 'C9:%'")
conn.execute("UPDATE item SET state='open', created_unix=? WHERE source='slack' AND key LIKE 'C1:%'", (now - 3600,))
conn.execute("UPDATE item SET state='dropped' WHERE source='slack' AND key NOT LIKE 'C1:%'")
cid = items(key="C1:1793212045.567019")[0]["id"]
good = json.dumps({"type": "result", "is_error": False, "result": "Here:\n```json\n" + json.dumps(
    {"items": [{"id": cid, "replies": [{"author": "Gus", "ts": "1793212999.000100", "text": "Tuesday 6am " + "z" * 400}]},
               {"id": 99999, "replies": [{"author": "X", "ts": "1", "text": "not asked"}]}]}) + "\n```"})
slack.run_claude = fake_claude(good)
reset()
slack.check(conn)
argv, prompt, tmo = claude_calls[0]
joined = " ".join(argv)
check("checker: argv is read-only haiku json", argv[:2] == ["claude", "-p"] and "--model haiku" in joined and "--output-format json" in joined)
dis = argv[argv.index("--disallowedTools") + 1].split(",")
check("checker: send/draft/schedule/Bash/Edit/Write are disallowed",
      all(t in dis for t in ("mcp__plugin_slack_slack__slack_send_message", "mcp__plugin_slack_slack__slack_send_message_draft",
                             "mcp__plugin_slack_slack__slack_schedule_message", "Bash", "Edit", "Write")))
alw = argv[argv.index("--allowedTools") + 1].split(",")
check("checker: only the two read tools are allowed", alw == ["mcp__plugin_slack_slack__slack_read_thread", "mcp__plugin_slack_slack__slack_read_channel"])
check("checker: prompt lists the open item; one call, 120 s timeout", "when is the deploy" in prompt or "ask Gus" in prompt or "ts 1793212045.567019" in prompt)
check("checker: exactly one claude call", len(claude_calls) == 1 and tmo == 120)
r = items(key="C1:1793212045.567019")[0]
check("checker: good JSON -> replied (text capped, unasked id ignored)", r["state"] == "replied" and r["reply_summary"].startswith("Gus: Tuesday 6am")
      and len(r["reply_summary"]) <= 240 and r["reply_ref"] == "1793212999.000100")
check("checker: reply event + toast with purpose", events("reply") and any("on Slack" in t[1] and "You asked: ask Gus" in t[2] for t in toasts))
check("checker: reply-act spawned", spawned == [cid])

for name, out in (("garbage", "totally not json"), ("empty", ""), ("no result key", "{}"),
                  ("result without json", json.dumps({"result": "no replies"})),
                  ("wrong shape", json.dumps({"result": '{"items": "nope"}'})),
                  ("bad entries", json.dumps({"result": json.dumps({"items": [None, {"id": "x"}, {"id": cid, "replies": "no"}]})}))):
    conn.execute("UPDATE item SET state='open', reply_summary=NULL WHERE id=?", (cid,))
    reset()
    slack.run_claude = fake_claude(out)
    try:
        slack.check(conn); ok = items(key="C1:1793212045.567019")[0]["state"] == "open" and not toasts
    except Exception as e:
        ok = False
    check(f"checker: {name} output changes nothing and does not crash", ok)
for name, exc in (("timeout", subprocess.TimeoutExpired("claude", 120)), ("claude failure", RuntimeError("exit 1"))):
    reset()
    slack.run_claude = fake_claude(exc)
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        slack.check(conn)
    check(f"checker: {name} is logged to stderr, once, no retry", len(claude_calls) == 1 and "slack-check" in err.getvalue())
config.mounted = lambda: False
reset()
slack.check(conn)
check("checker: locked store -> no claude call", not claude_calls)
config.mounted = lambda: True

# PANIC silences the Slack toast too
config.PANIC.write_text("")
conn.execute("UPDATE item SET state='open' WHERE id=?", (cid,))
reset(); slack.run_claude = fake_claude(good); slack.check(conn)
check("PANIC: Slack reply recorded but silent", items(key="C1:1793212045.567019")[0]["state"] == "replied" and not toasts and not spawned)
config.PANIC.unlink()

# ---- 11. reply-act: Slack gets no mail draft -------------------------------------------------
LLM["fn"] = lambda system, user: {"reply": "Tuesday works, thanks."}
nm_calls.clear()
before = len(list((config.BOX / "Drafts" / "cur").glob("*")))
t = ledger.draft(conn, cid)
check("slack draft: text in item.draft, no mail file", t == "Tuesday works, thanks." and items(key="C1:1793212045.567019")[0]["draft"] == t
      and len(list((config.BOX / "Drafts" / "cur").glob("*"))) == before and not nm_calls)
opened = []
ledger.run_open = lambda it: opened.append(it["source"])
notify.ask = lambda app, summary, body, actions, timeout, urgency="normal": (asks.append((summary, body, actions)), "open")[1]
reset(); ledger.reply_act(conn, cid)
check("reply-act: slack offers open/done only, open goes to Slack", [k for k, _ in asks[0][2]] == ["open", "done"] and opened == ["slack"])
ledger.reply_act(conn, items(key="s1@x")[0]["id"])
check("reply-act: mail offers open/draft/done", [k for k, _ in asks[1][2]] == ["open", "draft", "done"])

sys.exit(1 if fails else 0)
PY

python3 "$tmp/t.py"
rc=$?

# the real entry point, as the hook wrapper calls it: garbage in, exit 0, silence out
out="$(printf 'garbage' | python3 -m dots_inbox slack-sent 2>"$tmp/err")"; hrc=$?
if [ "$hrc" = 0 ] && [ -z "$out" ]; then echo "  ok   slack-sent entry point: exit 0, stdout empty"; else echo "  FAIL slack-sent entry point (rc=$hrc out=$out)"; rc=1; fi
hook="$root/home/private_dot_local/private_bin/executable_dots-inbox-slack-hook"
mkdir -p "$tmp/bin"; printf '#!/bin/sh\ncat >/dev/null; echo LEAK\nexit 3\n' > "$tmp/bin/dots-inbox"; chmod +x "$tmp/bin/dots-inbox"
out="$(echo '{}' | PATH="$tmp/bin:$PATH" sh "$hook")"; hrc=$?
if [ "$hrc" = 0 ] && [ -z "$out" ]; then echo "  ok   hook wrapper: always exit 0, never prints"; else echo "  FAIL hook wrapper (rc=$hrc out=$out)"; rc=1; fi

[ "$rc" = 0 ] && echo "inbox-ledger: all passed" || echo "inbox-ledger: FAILURES"
exit "$rc"
