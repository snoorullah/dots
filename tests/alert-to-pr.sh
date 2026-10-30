#!/usr/bin/env bash
# Alert -> ticket -> draft PR: the offer on a prepared alert, the single local task it makes,
# the agent launch with its deny rules, and proof that the read-only prep call is unchanged.
# Real `task` against a scratch TASKRC; stub herdr and notify-send; no claude, mail or network.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pkg="$root/nix/pkgs/dots-overview"
mkdir -p "$tmp/bin" "$tmp/data" "$tmp/work/example-app"
cat > "$tmp/bin/dots-overview" <<EOS
#!/bin/sh
PYTHONPATH="$pkg" exec python3 -m dots_overview "\$@"
EOS
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/notify-send"
chmod +x "$tmp/bin/"*
cp "$root/home/create_dot_taskrc" "$tmp/taskrc"
printf 'data.location=%s\n' "$tmp/data" >> "$tmp/taskrc"
export PATH="$tmp/bin:$PATH" TASKRC="$tmp/taskrc" TASKDATA="$tmp/data" HOME="$tmp/home"
mkdir -p "$HOME"
export DOTS_INBOX_TEST=1 DOTS_INBOX_MAIL="$tmp/Mail" DOTS_OVERVIEW_STATE_DIR="$tmp/ov" \
       XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" TMP="$tmp"
cd "$root/nix/pkgs/dots-inbox"
PYTHONPATH="$pkg" python3 - <<'PY'
import json, os, subprocess, sys, time
from pathlib import Path

from dots_inbox import alertpr, config, db, mail, notify, prep
from dots_overview import launch, tw, attention

fails = []
def check(name, got, want):
    if got != want: fails.append(f"{name}: got {got!r}, want {want!r}")

tmp = Path(os.environ["TMP"])
config.PANIC = tmp / "config" / "timetrack" / "PANIC"
now = int(time.time())
toasts, asks = [], []
notify.toast = lambda app, summary, body="", **k: toasts.append(summary)
prep.notify.toast = notify.toast
alertpr._nt.toast = notify.toast
mail.messages = lambda q, limit=None: []
conn = db.open_db()
repo = str(tmp / "work" / "example-app")
CFG = {"alerts": {"repos": {"HighCPU*": {"project": "platform", "repo": repo}}}}
config.rules = lambda: CFG
md = tmp / "p1.md"; md.write_text("# analysis\n")

def row(ref, kind="alert"):
    return {"kind": kind, "ref": ref, "title": ref.split("|")[0]}
def events(kind): return conn.execute("SELECT ref FROM event WHERE kind=?", (kind,)).fetchall()
def ptasks(): return [t for t in tw.pending() if "alert" in (t.get("tags") or [])]

# 1. mapping: glob, case-insensitive; no match -> default project, no repo
check("map hit", alertpr.mapping("highcpu-node", CFG), ("platform", repo))
check("map miss", alertpr.mapping("DiskFull", CFG), ("alerts", None))

# 2. unanswered = nothing at all
alertpr.ask = lambda *a, **k: (asks.append(a), None)[1]
check("unanswered returns None", alertpr.offer(conn, row("HighCPU|n1"), "s", md, 7 * 86400, CFG), None)
check("unanswered: no task, no event", (ptasks(), events("alert_ignored"), events("alert_ticketed")), ([], [], []))
check("asked with exactly the two buttons", asks[0][3], [("create", "Create ticket"), ("ignore", "Ignore")])

# 3. Ignore records the name; no second offer within the window
alertpr.ask = lambda *a, **k: "ignore"
check("ignore", alertpr.offer(conn, row("HighCPU|n1"), "s", md, 7 * 86400, CFG), "ignore")
check("ignore recorded by name", [r[0] for r in events("alert_ignored")], ["HighCPU"])
check("no task from ignore", ptasks(), [])
alertpr.ask = lambda *a, **k: (_ for _ in ()).throw(AssertionError("asked again"))
check("no repeat for same name, other scope", alertpr.offer(conn, row("HighCPU|n2"), "s", md, 7 * 86400, CFG), "skipped")

# 4. Create: exactly one task, right project and annotations
alertpr.ask = lambda *a, **k: "create"
check("create", alertpr.offer(conn, row("DiskFull|n1"), "s", md, 7 * 86400, {"alerts": {"repos": {"Disk*": {"project": "platform", "repo": repo}}}}), "create")
ts = ptasks()
check("one task", len(ts), 1)
t = ts[0]
check("project", t.get("project"), "platform")
check("title", t["desc"], "Alert: DiskFull")
check("tags", sorted(set(t["tags"]) & {"alert", "attn", "claude"}), ["alert", "attn", "claude"])
check("ref is local", (t.get("ref") or "").startswith("local:"), True)
check("annotations", sorted(a["description"] for a in t["annotations"]), sorted([f"prep: {md}", f"repo: {repo}"]))
check("ticketed event", [r[0] for r in events("alert_ticketed")], ["DiskFull"])
check("a second Create for the same prep file makes no second task",
      (alertpr.create(conn, "DiskFull", md, {"alerts": {"repos": {"Disk*": {"project": "platform", "repo": repo}}}}), len(ptasks())) [1], 1)

# 5. no mapping: task exists, project alerts, no repo annotation
md2 = tmp / "p2.md"; md2.write_text("x\n")
alertpr.ask = lambda *a, **k: "create"
alertpr.offer(conn, row("Unmapped|n1"), "s", md2, 7 * 86400, CFG)
t2 = [x for x in ptasks() if x["desc"] == "Alert: Unmapped"][0]
check("unmapped project", t2.get("project"), "alerts")
check("unmapped has no repo annotation", [a["description"] for a in t2["annotations"]], [f"prep: {md2}"])

# 6. attention: kind alert + canBreakdown
items = attention.from_tasks(ptasks(), now)
check("attention kind", sorted({i["kind"] for i in items}), ["alert"])
check("attention canBreakdown", all(i["canBreakdown"] for i in items), True)

# 7. launch: a mapped task starts claude with the deny file; an unmapped one asks
class H:
    def __init__(s): s.calls = []
    def __call__(s, args, timeout=5):
        s.calls.append(list(args))
        if args[:2] == ["api", "snapshot"]: return json.dumps({"result": {"snapshot": {"workspaces": [{"workspace_id": "w5", "label": "Hangar"}], "panes": []}}})
        if args[:2] == ["tab", "create"]: return json.dumps({"result": {"root_pane": {"pane_id": "w5:p2", "tab_id": "w5:t2"}, "tab": {"tab_id": "w5:t2"}}})
        return "{}"
from dots_overview import config as occ
cfg = occ.Work({"AGENT_CWD": str(tmp / "home")})
for tk, mapped in ((t, True), (t2, False)):
    h = H()
    launch.launch(tk, ["Fix it please"], "Fix it please", {"uuid": "0123abcd-0000-4000-8000-000000000001"}, cfg=cfg, run=h, sleep=lambda s: None)
    start = next(c for c in h.calls if c[:2] == ["agent", "start"])
    prompt = next(c for c in h.calls if c[:2] == ["agent", "prompt"])[3]
    check(f"claude kind ({mapped})", start[start.index("--kind") + 1], "claude")
    check(f"settings passed after -- ({mapped})", start[start.index("--") + 1], "--settings")
    mk = next(c for c in h.calls if c[:2] == ["tab", "create"])
    check(f"cwd ({mapped})", mk[mk.index("--cwd") + 1], repo if mapped else str(tmp / "home"))
    if mapped:
        check("settings file deny == ALERT_DENY", json.loads(Path(start[start.index("--") + 2]).read_text())["permissions"]["deny"], list(launch.ALERT_DENY))
        check("prompt: worktree + branch + draft", all(x in prompt for x in ("worktree add -b fix/local-", "gh pr create --draft", str(md))), True)
        check("prompt: branch has no colon", "fix/local:" in prompt, False)
    else:
        check("unmapped prompt: stops and asks", ("No repository is mapped" in prompt, "worktree add" in prompt), (True, False))
    check(f"prompt forbids merge ({mapped})", all(x in prompt for x in ("gh pr merge", "git merge", "git push --force", "main or master", "kubectl", "terraform apply")), True)

# 8. the deny list holds every required pattern
D = set(launch.ALERT_DENY)
for p in ("Bash(gh pr merge:*)", "Bash(git merge:*)", "Bash(git push --force:*)", "Bash(git push -f:*)",
          "Bash(git push --force-with-lease:*)", "Bash(git push origin main:*)", "Bash(git push origin master:*)",
          "Bash(git push * HEAD:main)", "Bash(kubectl:*)", "Bash(helm:*)", "Bash(argocd:*)",
          "Bash(terraform apply:*)", "mcp__k8s-ro__save_secret_to_file",
          "mcp__plugin_slack_slack", "mcp__claude_ai_Gmail", "mcp__pnow-erp", "Bash(dots-mail:*)", "Bash(sendmail:*)"):
    check(f"deny has {p}", p in D, True)
check("settings file only denies", list(json.loads(Path(launch.alert_settings()).read_text())), ["permissions"])
check("settings permissions only deny", list(json.loads(Path(launch.alert_settings()).read_text())["permissions"]), ["deny"])

# 9. the read-only prep call is untouched by all of this
argv = prep.claude_argv()
dis = argv[argv.index("--disallowedTools") + 1].split(",")
check("prep still denies Bash/Edit/Write", all(x in dis for x in ("Bash", "Edit", "Write")), True)
check("prep argv has no settings override", "--settings" in argv, False)
check("prep argv shape", argv[:8], ["claude", "-p", "--model", "sonnet", "--output-format", "json", "--max-turns", "25"])

# 10. run_one: an alert row offers (no plain toast), a mail row still toasts
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('alert','Fresh|n1','Fresh','running',?)", (now,))
conn.execute("INSERT INTO prep(kind,ref,title,status,created_unix) VALUES('mail','m9@x','Mail one','running',?)", (now,))
conn.commit()
mail.get = lambda mid: {"id": mid, "thread": "t", "file": None, "folder": "INBOX", "from": "a <a@x>", "from_addr": "a@x",
                        "to": [], "cc": [], "subject": "S", "date": now, "tags": set(), "headers": {}}
mail.body = lambda m, limit=20000: "b"
prep.run = lambda argv, input=None, **kw: subprocess.CompletedProcess(argv, 0, json.dumps({"result": "# Done\n"}), "")
prep.mail.get = mail.get
offered = []
alertpr.ask = lambda *a, **k: (offered.append(a[1]), None)[1]
toasts.clear()
for r in conn.execute("SELECT * FROM prep WHERE status='running'").fetchall():
    prep.run_one(conn, r)
check("alert row offered", offered, ["Prepared: Fresh"])
check("mail row toasted, alert row not", toasts, ["Prepared: Mail one"])

if fails:
    print("FAIL\n" + "\n".join(fails)); sys.exit(1)
print("ok alert-to-pr")
PY
