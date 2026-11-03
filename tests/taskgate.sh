#!/usr/bin/env bash
# Task discipline: "no Claude agent works without a declared task".
#
#   dots-task        declare / new / switch / none / list / current / promote
#   dots-task-hook   the PreToolUse gate, the context injection, the Stop steering check
#   installer        merges the hook into a COPY of settings.json, idempotently
#
# Everything runs against a scratch TASKRC / TASKDATA / state dir with a stub herdr (which LOGS
# every call) and a stub Ollama on a loopback port. No network, no real herdr, no real
# Taskwarrior data, nothing under ~/.claude is read or written.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
pkg="$root/nix/pkgs/dots-overview"
stubs="$pkg/tests/stubs"
bindir="$root/home/private_dot_local/private_bin"
rc="$root/home/create_dot_taskrc"
tmp="$(mktemp -d)"
cleanup() { [ -n "${llm_pid:-}" ] && kill "$llm_pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# this suite may itself run inside a Claude session: none of that may leak in
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ATTENDED DOTS_SESSION_ID DOTS_TASK_GATE TIMETRACK_TICKET
mkdir -p "$tmp/bin" "$tmp/task" "$tmp/work"
cat > "$tmp/bin/dots-overview" <<EOF
#!/bin/sh
PYTHONPATH="$pkg" exec python3 -m dots_overview "\$@"
EOF
cp "$bindir/executable_dots-task" "$tmp/bin/dots-task"
cp "$bindir/executable_dots-task-hook" "$tmp/bin/dots-task-hook"
cp "$bindir/executable_dots-statusline" "$tmp/bin/dots-statusline"
cp "$stubs/herdr" "$tmp/bin/herdr"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
hook="$tmp/bin/dots-task-hook"
export TASKRC="$tmp/taskrc" TASKDATA="$tmp/task" TIMEWARRIORDB="$tmp/none-timew" HERDR_LOG="$tmp/herdr.log"
export DOTS_OVERVIEW_STATE_DIR="$tmp/state" DOTS_WORK_CONF="$tmp/work.conf"
export TIMETRACK_STATE_DIR="$tmp/timetrack"   # never the real work.db: the report day comes from its sessions
export HTTP_PROXY=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1
sed -e "s#^data.location=.*#data.location=$TASKDATA#" "$rc" > "$TASKRC"
: > "$HERDR_LOG"
st="$tmp/state"
S1=aaaaaaaa-0000-4000-8000-000000000001
S2=bbbbbbbb-0000-4000-8000-000000000002
tw() { task rc.confirmation=off rc.verbose=nothing "$@"; }
tasks() { task rc.json.array=on "$@" export 2>/dev/null; }
pyj() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# a loopback Ollama: the answer comes from $tmp/llm.mode (same | different | slow | garbage)
cat > "$tmp/ollama.py" <<'PY'
import http.server, json, os, sys, time
mode_file, count_file = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        with open(count_file, "a") as f: f.write("x\n")
        mode = open(mode_file).read().strip()
        if mode == "slow": time.sleep(20)
        body = {"response": "not json" if mode == "garbage" else json.dumps({"verdict": mode})}
        out = json.dumps(body).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[3], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
echo same > "$tmp/llm.mode"; : > "$tmp/llm.count"
python3 "$tmp/ollama.py" "$tmp/llm.mode" "$tmp/llm.count" "$tmp/llm.port" & llm_pid=$!
for _ in $(seq 50); do [ -s "$tmp/llm.port" ] && break; sleep 0.1; done
export DOTS_OLLAMA_URL="http://127.0.0.1:$(cat "$tmp/llm.port")"

# hook helpers: hk <event> <json> [env ...] -> stdout of the hook; always exit 0
hk() { local ev=$1 js=$2; shift 2; printf '%s' "$js" | env HERDR_ENV=1 HERDR_PANE_ID=w9:p1 "$@" sh "$hook" "$ev" 2>/dev/null; }
pre() { # tool session command [env...]
  local tool=$1 sess=$2 cmd=$3; shift 3
  local js; js=$(python3 -c "import json,sys; print(json.dumps({'session_id':sys.argv[2],'cwd':sys.argv[4],'hook_event_name':'PreToolUse','tool_name':sys.argv[1],'tool_input':{'command':sys.argv[3],'file_path':'/x/y'}}))" "$tool" "$sess" "$cmd" "$tmp/work")
  hk pretool "$js" "$@"
}
denied() { grep -q '"permissionDecision": "deny"'; }
cli() { env DOTS_SESSION_ID="$SESS" dots-task "$@"; }

echo "1. dots-task: new, declare, switch, none, list, current, promote"
SESS=$S1
tw add ref:HD-7 src:erp project:work -- "Existing ticket seven" >/dev/null 2>&1
tw add ref:HD-8 src:erp project:work -- "Existing ticket eight" >/dev/null 2>&1
out=$(cli current 2>&1); rc_=$?
[ "$rc_" = 1 ] && ok "current before any declaration exits 1" || bad "current exit $rc_: $out"
cli list 2>&1 | grep -q 'HD-7 .*work .*Existing ticket seven' && ok "list shows ref, project, title" || bad "list: $(cli list 2>&1)"
cli declare HD-7 >/dev/null 2>&1 && ok "declare by ref" || bad "declare HD-7: $(cli declare HD-7 2>&1)"
tasks ref.is:HD-7 | pyj 't=d[0]; assert t["sess"]=="'$S1'" and t["agent"] and t.get("start"), t' && ok "declare sets sess + agent and starts it" || bad "UDAs after declare"
cli current 2>&1 | grep -q 'HD-7' && ok "current names the task" || bad "current"
python3 - "$st/declared/$S1.json" <<'EOF' && ok "declaration file written (0600)" || bad "declaration file"
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["ref"] == "HD-7" and d["uuid"] and d["title"] == "Existing ticket seven" and d["project"] == "work", d
assert oct(os.stat(sys.argv[1]).st_mode & 0o777) == "0o600"
EOF
cli new 'Hostile "$(touch PWNED)"; +tag ref:evil' --project demo >"$tmp/new.out" 2>&1 && ok "new creates and declares" || bad "new failed: $(cat "$tmp/new.out")"
[ ! -e PWNED ] && [ ! -e "$tmp/PWNED" ] && ok "a hostile title is data, not syntax" || bad "title was executed"
tasks +claude | pyj 't=d[0]; assert t["src"]=="claude" and t["ref"].startswith("local:") and t["project"]=="demo" and "claude" in t["tags"] and t["sess"]=="'$S1'" and t.get("start"), t; assert "evil" not in str(t.get("ref")), t' \
  && ok "new: src=claude, tag claude, ref local:<short>, project, session bound, started" || bad "new task attributes"
tasks ref.is:HD-7 | pyj 't=d[0]; assert not t.get("start") and not t.get("sess"), t' && ok "switching away stops the old clock and releases the session" || bad "old task still bound/started"
newref=$(tasks +claude | pyj 'print(d[0]["ref"])')
cli new "no project" >/dev/null 2>&1 && bad "new without --project accepted" || ok "new without --project or --parent is refused"
cli new "Child" --parent "$newref" >/dev/null 2>&1 && tasks parentref:"$newref" | pyj 'assert d[0]["project"]=="demo"' && ok "--parent inherits the project and sets parentref" || bad "--parent"
cli switch HD-8 >/dev/null 2>&1 && tasks ref.is:HD-8 | pyj 'assert d[0]["sess"]=="'$S1'" and d[0].get("start")' && ok "switch moves the session" || bad "switch"
[ "$(tasks status:pending sess:"$S1" | pyj 'print(len(d))')" = 1 ] && ok "exactly one pending task carries the session" || bad "session on several tasks"
grep -q '"kind":"switch"' "$st/task-log.jsonl" && grep -q '"kind":"new"' "$st/task-log.jsonl" && ok "log records new and switch" || bad "task-log: $(cat "$st/task-log.jsonl")"
cli declare nonsense-ref >/dev/null 2>&1 && bad "declare of an unknown ref succeeded" || ok "declare of an unknown ref fails"
# ingest's prompt-head placeholder for the same session is replaced, not kept
tw add src:claude sess:$S2 -- "please fix the form" >/dev/null 2>&1
SESS=$S2 cli declare HD-7 >/dev/null 2>&1
[ "$(tasks status:pending sess:$S2 | pyj 'print(len(d))')" = 1 ] && tasks status:pending ref.is:HD-7 | pyj 'assert d[0]["sess"]=="'$S2'"' && ok "declare removes the session's placeholder task" || bad "placeholder survived"
SESS=$S2 cli none "ok" >/dev/null 2>&1 && bad "none with a one-word reason accepted" || ok "none needs a reason"
SESS=$S2 cli none "quick question about git, no files touched" >/dev/null 2>&1 && grep -q '"kind":"none"' "$st/task-log.jsonl" && ok "none records an exemption" || bad "none"
SESS=$S2 cli current 2>&1 | grep -q 'untracked' && ok "current reports untracked" || bad "current after none"
tasks ref.is:"$newref" | pyj 'assert "claude" in d[0]["tags"]' && cli promote "$newref" HD-99 >/dev/null 2>&1 && tasks ref.is:HD-99 | pyj 'assert "claude" not in d[0]["tags"]' && ok "promote renames the ref and drops the claude tag" || bad "promote"
cli promote HD-99 HD-98 >/dev/null 2>&1 && bad "promote of a non-local task accepted" || ok "only local: tasks promote"
grep -q 'report-metadata w9:p1 --source dots-task --token ticket=' "$HERDR_LOG" && ok "declare sets the herdr ticket token (pane id first)" \
  || { HERDR_PANE_ID=w9:p1 cli declare HD-8 >/dev/null 2>&1; grep -q 'report-metadata w9:p1 --source dots-task --token ticket=HD-8 --ttl-ms 14400000' "$HERDR_LOG" && ok "declare sets the herdr ticket token (pane id first, ttl 4 h)" || bad "no token call: $(cat "$HERDR_LOG")"; }
# declare writes the ticket into the overview recorder's session record when there is one
mkdir -p "$st/sessions"; printf '{"v":1,"ts":%s,"action":"prompt","sess":"%s","pane":"w9:p1","cwd":"%s","ticket":null}\n' "$(date +%s)" "$S1" "$tmp/work" > "$st/sessions/$S1.json"
cli declare HD-7 >/dev/null 2>&1; python3 -c "import json; assert json.load(open('$st/sessions/$S1.json'))['ticket']=='HD-7'" && ok "declare writes the ticket into sessions/<sess>.json" || bad "session record ticket"

echo "1b. which session is this?"
env -u DOTS_SESSION_ID CLAUDE_CODE_SESSION_ID=$S1 dots-task current 2>&1 | grep -q HD-7 && ok "CLAUDE_CODE_SESSION_ID (exported to Bash tool subprocesses) wins" || bad "env resolution"
env -u DOTS_SESSION_ID HERDR_PANE_ID=w9:p1 dots-task current 2>&1 | grep -q HD-7 && ok "HERDR_PANE_ID -> newest record for that pane" || bad "pane resolution"
env -u DOTS_SESSION_ID -u HERDR_PANE_ID sh -c "cd '$tmp/work' && dots-task current" 2>&1 | grep -q HD-7 && ok "no env, no pane: newest record for the cwd" || bad "cwd resolution"
env -u DOTS_SESSION_ID -u HERDR_PANE_ID sh -c "cd / && dots-task declare HD-7" >/dev/null 2>&1 && bad "resolved a session from nowhere" || ok "unresolvable session is an error, not a guess"
env DOTS_SESSION_ID='../../evil' dots-task declare HD-7 >/dev/null 2>&1 && bad "hostile session id accepted" || ok "a hostile DOTS_SESSION_ID is not used"

echo "2. context injection (SessionStart / UserPromptSubmit)"
ctx() { python3 -c "import json,sys; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])"; }
mk() { python3 -c "import json,sys; print(json.dumps({'session_id':sys.argv[1],'cwd':sys.argv[2],'hook_event_name':sys.argv[3],'prompt':sys.argv[4]}))" "$@"; }
S3=cccccccc-0000-4000-8000-000000000003
out=$(hk session "$(mk $S3 "$tmp/work" SessionStart '')")
echo "$out" | ctx | grep -q 'dots-task list.*dots-task declare <ref>.*dots-task new' && ok "undeclared session: told to declare" || bad "no-task context: $out"
echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName']=='SessionStart'" && ok "hookEventName matches" || bad "hookEventName"
echo "$out" | ctx | grep -q 'ask the user whether to log it' && ok "tells the agent to ask before logging different work" || bad "ask-the-user clause"
: > "$HERDR_LOG"
out=$(hk prompt "$(mk $S1 "$tmp/work" UserPromptSubmit 'continue with the form')")
echo "$out" | ctx | grep -q 'HD-7.*Existing ticket seven.*project work' && ok "declared session: names ref, title, project" || bad "task context: $out"
grep -q 'report-metadata w9:p1 --source dots-task --token ticket=HD-7 --ttl-ms 14400000' "$HERDR_LOG" && ok "every prompt refreshes the herdr token (ttl 4 h)" || bad "token not refreshed: $(cat "$HERDR_LOG")"
hk prompt "$(mk $S3 "$tmp/work" UserPromptSubmit 'x')" >/dev/null; grep -q 'ticket=no-task' "$HERDR_LOG" && ok "undeclared pane shows no-task" || bad "no-task token"
hk prompt "$(mk $S1 "$tmp/work" UserPromptSubmit 'hi')" DOTS_TASK_GATE=off | grep -q . && bad "kill switch still injects context" || ok "kill switch: silent"
sub=$(python3 -c "import json; print(json.dumps({'session_id':'$S3','agent_id':'sub1','hook_event_name':'UserPromptSubmit','prompt':'x'}))")
[ -z "$(hk prompt "$sub")" ] && ok "subagent prompts get no injection" || bad "subagent injection"

echo "3. PreToolUse gate"
for t in Edit Write MultiEdit NotebookEdit; do
  pre $t $S3 "" | denied && ok "$t denied with no task" || bad "$t not denied"
done
out=$(pre Bash $S3 "npm install left-pad"); echo "$out" | denied && ok "Bash denied with no task" || bad "Bash not denied"
echo "$out" | python3 -c "import json,sys; r=json.load(sys.stdin)['hookSpecificOutput']; assert r['hookEventName']=='PreToolUse'; t=r['permissionDecisionReason']; assert 'dots-task list' in t and 'dots-task new' in t and 'dots-task none' in t" && ok "the deny reason says how to declare" || bad "deny reason"
pre Read $S3 "" | grep -q . && bad "Read was gated" || ok "other tools (Read, Grep, ...) are never gated"
for c in "dots-task list" "dots-task declare HD-7" 'dots-task new "Fix: the (odd) title; really" --project p' "dots-task none 'trivial, no files'" "~/.local/bin/dots-task current" \
         "task ref.is:HD-7 export" "task list" "task 123 info" "git status" "git log --oneline -5" "git diff HEAD~1" "ls -la src" "cat README.md" "rg -n foo src" "grep -rn 'a;b' ." ; do
  pre Bash $S3 "$c" | grep -q . && bad "allowlisted command denied: $c" || ok "allowed before declaring: $c"
done
for c in "dots-task list; rm -rf ~" "dots-task list && rm x" "ls | sh" 'cat $(whoami)' 'ls `id`' "git status > out" "cat < /etc/passwd" 'dots-task new "$(rm x)" --project p' 'dots-task new "a`id`" --project p' "ls
rm x" "ls &" "ls \\; id" "task add evil" "task done 1" "task modify 1 x" "task rc.hooks=1 list" "git push" "git -c core.pager=x log" "git diff --output=/tmp/x" "rg --pre ./x foo" "rm -rf x" "echo hi" "bash -c ls" "/tmp/evil/git status" "ls 'unterminated"; do
  pre Bash $S3 "$c" | denied && ok "denied before declaring: $(printf '%s' "$c" | tr '\n' '~')" || bad "slipped through: $c"
done
pre Edit $S1 "" | grep -q . && bad "declared session was gated" || ok "Edit allowed once a task is declared"
pre Bash $S1 "make build" | grep -q . && bad "declared session Bash was gated" || ok "Bash allowed once a task is declared"
pre Bash $S2 "make build" | grep -q . && bad "exempt session was gated" || ok "dots-task none opens the gate"
pre Edit $S3 "" DOTS_TASK_GATE=off | grep -q . && bad "kill switch env ignored" || ok "DOTS_TASK_GATE=off opens the gate"
touch "$tmp/task-gate-off"; pre Edit $S3 "" | grep -q . && bad "kill switch file ignored" || ok "task-gate-off file opens the gate"; rm -f "$tmp/task-gate-off"
pre Edit $S3 "" | denied && ok "...and removing the file closes it again" || bad "gate stayed open"
pre Edit $S3 "" CLAUDE_CODE_ENTRYPOINT=sdk-cli | grep -q . && bad "claude -p (sdk entrypoint) gated" || ok "claude -p / SDK runs are exempt (entrypoint sdk-*)"
: > "$HERDR_LOG"
hk prompt "$(mk $S3 "$tmp/work" UserPromptSubmit 'do a thing in the background')" CLAUDE_CODE_ENTRYPOINT=sdk-cli | grep -q . && bad "claude -p got context" || ok "claude -p gets no injection"
grep -q report-metadata "$HERDR_LOG" && bad "claude -p rewrote the pane's ticket token" || ok "claude -p leaves the launching pane's ticket token alone"
pre Edit $S3 "" CLAUDE_CODE_ENTRYPOINT=cli | denied && ok "an interactive session (entrypoint cli) is gated" || bad "interactive session not gated"
out=$(printf '%s' "$(python3 -c "import json; print(json.dumps({'session_id':'$S3','hook_event_name':'PreToolUse','tool_name':'Edit','tool_input':{}}))")" | env -u HERDR_PANE_ID -u HERDR_ENV setsid -w sh "$hook" pretool 2>/dev/null)
[ -n "$out" ] && ok "no pane and no terminal is NOT a pass: only the sdk entrypoint exempts" || bad "tty-less interactive session slipped through"
# a subagent inherits the parent's declaration
subj() { python3 -c "import json,sys; print(json.dumps({'session_id':sys.argv[1],'cwd':sys.argv[2],'agent_id':'sub1','agent_type':'Explore','hook_event_name':'PreToolUse','tool_name':'Edit','tool_input':{}}))" "$@"; }
hk pretool "$(subj $S1 "$tmp/work")" | grep -q . && bad "subagent with the parent's session id gated" || ok "subagent (same session id) inherits the declaration"
hk pretool "$(subj sub-own-session-id "$tmp/work")" | denied && ok "an undeclared session id is gated even from a subagent (no pane guessing)" || bad "pane guess let an undeclared session through"
for bad_in in '' 'not json' '[]' '{"session_id":"../x","tool_name":"Edit"}' '{"tool_name":"Edit"}'; do
  out=$(printf '%s' "$bad_in" | env HERDR_ENV=1 HERDR_PANE_ID=w9:p1 sh "$hook" pretool 2>/dev/null); rc_=$?
  [ -z "$out" ] && [ "$rc_" = 0 ] && ok "malformed input fails open: ${bad_in:-empty}" || bad "malformed input: $out"
done
[ -z "$(printf '{}' | PATH=/usr/bin:/bin sh "$hook" pretool 2>/dev/null)" ] && ok "dots-overview missing: fails open" || bad "missing dots-overview blocked"

# an agent dispatched by Break down & start arrives with DOTS_TASK_DECLARE: declared at SessionStart
S6=ffffffff-0000-4000-8000-000000000006
u7=$(task rc.verbose=nothing ref:HD-7 export 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["uuid"])')
hk session "$(python3 -c "import json; print(json.dumps({'session_id':'$S6','cwd':'/x','hook_event_name':'SessionStart'}))")" DOTS_TASK_DECLARE="$u7" >/dev/null
pre Edit $S6 "" | grep -q . && bad "dispatched agent still gated" || ok "a dispatched agent (DOTS_TASK_DECLARE) is declared at SessionStart"
SESS=$S6 cli current 2>/dev/null | grep -q 'HD-7' && ok "...on the step it was sent for" || bad "dispatched agent declared on the wrong task"
hk session "$(python3 -c "import json; print(json.dumps({'session_id':'eeeeeeee-0000-4000-8000-000000000007','cwd':'/x','hook_event_name':'SessionStart'}))")" 'DOTS_TASK_DECLARE=$(id)' >/dev/null
pre Edit eeeeeeee-0000-4000-8000-000000000007 "" | denied && ok "a malformed DOTS_TASK_DECLARE declares nothing" || bad "malformed declare opened the gate"

echo "4. Stop: steering check"
stop_in() { python3 -c "import json,sys; print(json.dumps({'session_id':sys.argv[1],'cwd':sys.argv[2],'hook_event_name':'Stop','stop_hook_active':sys.argv[3]=='1'}))" "$@"; }
S4=dddddddd-0000-4000-8000-000000000004
SESS=$S4 cli declare HD-8 >/dev/null 2>&1
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'now please redesign the billing export pipeline from scratch')" >/dev/null
echo same > "$tmp/llm.mode"
[ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)")" ] && ok "verdict same: no block" || bad "blocked on a match"
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'now please write a poem about the ocean at night')" >/dev/null
echo different > "$tmp/llm.mode"; : > "$tmp/llm.count"
out=$(hk stop "$(stop_in $S4 "$tmp/work" 1)")
[ -z "$out" ] && [ ! -s "$tmp/llm.count" ] && ok "stop_hook_active: never blocks, never asks the model" || bad "blocked or asked while stop_hook_active"
out=$(hk stop "$(stop_in $S4 "$tmp/work" 0)")
echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['decision']=='block'; r=d['reason']; assert 'HD-8' in r and 'dots-task switch' in r and 'dots-task new' in r and 'log this as a ticket' in r" && ok "clearly different work: blocks with switch / new / ask-the-user" || bad "no block on mismatch: $out"
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'Another Claude session sent a message: a poem about the ocean at night, written in full')" >/dev/null
[ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)")" ] && ok "a harness-started turn (subagent report) is never judged" || bad "blocked a subagent report"
n=$(wc -l < "$tmp/llm.count")
out=$(hk stop "$(stop_in $S4 "$tmp/work" 0)")
[ -z "$out" ] && [ "$(wc -l < "$tmp/llm.count")" = "$n" ] && ok "the same prompt never blocks twice (cached verdict, no second model call)" || bad "blocked twice or re-asked"
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'ok')" >/dev/null
[ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)")" ] && ok "a trivial prompt is not classified" || bad "trivial prompt blocked"
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'something else entirely, unrelated to the ticket at hand')" >/dev/null
echo slow > "$tmp/llm.mode"
t0=$(date +%s%N); out=$(hk stop "$(stop_in $S4 "$tmp/work" 0)"); ms=$(( ($(date +%s%N) - t0) / 1000000 ))
[ -z "$out" ] && ok "model timeout: allows" || bad "blocked on a timeout"
[ "$ms" -lt 5500 ] && ok "hung model: stop hook ends in ${ms} ms (< 6 s installer timeout)" || bad "stop hook took ${ms} ms"
echo garbage > "$tmp/llm.mode"; [ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)")" ] && ok "unparseable model answer: allows" || bad "blocked on garbage"
echo different > "$tmp/llm.mode"
out=$(hk stop "$(stop_in $S4 "$tmp/work" 0)")
echo "$out" | grep -q '"decision": "block"' && ok "a timeout is not cached: the next Stop asks again and can block" || bad "failure was cached"
hk prompt "$(mk $S3 "$tmp/work" UserPromptSubmit 'write a long essay about something entirely different')" >/dev/null
[ -z "$(hk stop "$(stop_in $S3 "$tmp/work" 0)")" ] && ok "no declaration: Stop stays out of it (the gate's job)" || bad "stop blocked an undeclared session"
hk prompt "$(mk $S4 "$tmp/work" UserPromptSubmit 'another unrelated request that is long enough to count')" >/dev/null
[ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)" DOTS_TASK_GATE=off)" ] && ok "kill switch silences Stop" || bad "kill switch ignored by Stop"
[ -z "$(hk stop "$(stop_in $S4 "$tmp/work" 0)" DOTS_OLLAMA_URL=http://203.0.113.9:11434)" ] && ok "a non-loopback model URL is refused (allowed, never contacted)" || bad "non-loopback URL used"
printf '%s' "$(python3 -c "import json; print(json.dumps({'session_id':'$S4','agent_id':'sub','hook_event_name':'Stop'}))")" | env HERDR_ENV=1 HERDR_PANE_ID=w9:p1 sh "$hook" stop 2>/dev/null | grep -q . && bad "subagent Stop blocked" || ok "subagent Stop is ignored"

echo "5. timing: every child hangs, the hooks still end under their installer timeouts"
mkdir -p "$tmp/slow"; printf '#!/bin/sh\nexec sleep 30\n' > "$tmp/slow/herdr"; chmod +x "$tmp/slow/herdr"
t0=$(date +%s%N)
out=$(hk prompt "$(mk $S3 "$tmp/work" UserPromptSubmit 'hello there')" PATH="$tmp/slow:$PATH"); ms=$(( ($(date +%s%N) - t0) / 1000000 ))
[ "$ms" -lt 4900 ] && echo "$out" | grep -q additionalContext && ok "prompt with a hung herdr: ${ms} ms, context still delivered" || bad "prompt hook: ${ms} ms, out=$out"
t0=$(date +%s%N); pre Bash $S3 "make" PATH="$tmp/slow:$PATH" | denied; ms=$(( ($(date +%s%N) - t0) / 1000000 ))
[ "$ms" -lt 2000 ] && ok "the gate decision costs ${ms} ms and never waits on herdr" || bad "pretool took ${ms} ms"
python3 - "$pkg/dots_overview/gate.py" "$hook" <<'EOF' && ok "budget constants: model 3.0 s, hook budget 4.0 s, shell cap 4.6 s (< 5 s)" || bad "budget constants"
import re, sys
g = open(sys.argv[1]).read()
assert float(re.search(r"^BUDGET = ([\d.]+)", g, re.M).group(1)) <= 4.0
assert float(re.search(r"^LLM_TIMEOUT = ([\d.]+)", g, re.M).group(1)) <= 3.5
assert float(re.search(r"timeout -k [\d.]+ ([\d.]+)", open(sys.argv[2]).read()).group(1)) < 5
EOF

echo "6. installer: merge into a COPY of settings, idempotent, foreign entries kept"
home="$tmp/home"; mkdir -p "$home/.claude" "$home/.local/bin"
cat > "$home/.claude/settings.json" <<'EOF'
{"model": "keep-me", "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "herdr-report session"}]}],
 "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "foreign-guard"}]}],
 "Notification": [{"hooks": [{"type": "command", "command": "notify-hook"}]}]}}
EOF
for h in timetrack-ticket-hook dots-track-hook dots-task-hook; do printf '#!/bin/sh\nexit 0\n' > "$home/.local/bin/$h"; chmod +x "$home/.local/bin/$h"; done
HOME="$home" chezmoi execute-template --source "$root/home" < "$root/home/.chezmoiscripts/run_onchange_after_30-claude-hooks.sh.tmpl" > "$tmp/installer.sh" 2>"$tmp/inst.err" \
  && ok "installer template renders" || bad "installer template: $(cat "$tmp/inst.err")"
[ "$(grep -c '^# live: ' "$tmp/installer.sh")" = 1 ] && ok "hash probe is exactly one line" || bad "hash probe"
grep '^# live: ' "$root/home/.chezmoiscripts/run_onchange_after_30-claude-hooks.sh.tmpl" | grep -q 'dots-task-hook' && ok "the probe counts dots-task-hook too" || bad "probe misses dots-task-hook"
HOME="$home" bash "$tmp/installer.sh" >"$tmp/inst1.out" 2>&1 && ok "installer runs" || bad "installer failed: $(cat "$tmp/inst1.out")"
python3 - "$home/.claude/settings.json" <<'EOF' && ok "task hook on 4 events, PreToolUse matcher set, foreign entries untouched" || bad "settings shape"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "keep-me"
h = d["hooks"]
def mine(ev): return [e for e in h[ev] for x in e["hooks"] if "dots-task-hook" in x["command"]]
for ev, act in (("SessionStart", "session"), ("UserPromptSubmit", "prompt"), ("PreToolUse", "pretool"), ("Stop", "stop")):
    es = mine(ev)
    assert len(es) == 1 and es[0]["hooks"][0]["command"].endswith("dots-task-hook " + act), (ev, es)
pt = mine("PreToolUse")[0]
assert pt["matcher"] == "Edit|Write|MultiEdit|NotebookEdit|Bash" and pt["hooks"][0]["timeout"] == 5
assert mine("Stop")[0]["hooks"][0]["timeout"] == 6 and "matcher" not in mine("Stop")[0]
assert {"matcher": "Bash", "hooks": [{"type": "command", "command": "foreign-guard"}]} in h["PreToolUse"]
assert {"hooks": [{"type": "command", "command": "herdr-report session"}]} in h["SessionStart"]
assert {"hooks": [{"type": "command", "command": "notify-hook"}]} in h["Notification"]
assert any("dots-track-hook stop" in x["command"] for e in h["Stop"] for x in e["hooks"])
EOF
cp "$home/.claude/settings.json" "$tmp/settings.after1"
HOME="$home" bash "$tmp/installer.sh" 2>&1 | grep -q 'already registered' && ok "second run is a no-op" || bad "second run changed things"
cmp -s "$home/.claude/settings.json" "$tmp/settings.after1" && ok "settings byte-identical after the second run" || bad "settings drifted"
python3 - "$home/.claude/settings.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for e in d["hooks"]["PreToolUse"]:
    for x in e["hooks"]:
        if "dots-task-hook" in x["command"]: x["command"] = "/old/path/dots-task-hook pretool"; e["matcher"] = "Bash"
json.dump(d, open(sys.argv[1], "w"))
EOF
HOME="$home" bash "$tmp/installer.sh" 2>&1 | grep -q 'dots-task-hook PreToolUse (updated)' && ok "a stale entry (old path, old matcher) is repaired in place" || bad "stale entry not repaired"
[ "$(grep -c 'dots-task-hook' "$home/.claude/settings.json")" = 4 ] && ok "still exactly 4 task-hook entries" || bad "duplicate entries"

echo "7. status line"
js=$(printf '{"session_id":"%s"}' "$S1")
[ "$(printf '%s' "$js" | dots-overview task statusline)" = "HD-7 Existing ticket seven" ] && ok "statusline segment: ref + short title" || bad "statusline: $(printf '%s' "$js" | dots-overview task statusline)"
[ "$(printf '{"session_id":"%s"}' "$S3" | dots-overview task statusline)" = "no task" ] && ok "undeclared session shows 'no task'" || bad "statusline no task"
out=$(printf '%s' "$js" | DOTS_STATUSLINE_BASE="cat" dots-statusline); echo "$out" | head -1 | grep -q session_id && echo "$out" | grep -q '^task: HD-7' && ok "dots-statusline = base line + task line" || bad "dots-statusline: $out"
[ -z "$(printf 'garbage' | DOTS_STATUSLINE_BASE=true dots-statusline)" ] && ok "dots-statusline survives garbage input" || bad "statusline garbage"

echo "8. daily brief"
printf 'WORK_PROJECTS=work\nREPORT_DIR=%s/daily\n' "$tmp" > "$DOTS_WORK_CONF"
SESS=$S1 cli new "Agent found some extra work" --project work >/dev/null 2>&1
SESS=$S1 cli new "Personal tinkering" --project hobby >/dev/null 2>&1
dots-overview report >/dev/null 2>&1
b="$tmp/daily/$(date +%F).md"
grep -q '## Agent work logged as new local tasks' "$b" && grep -q 'Agent found some extra work' "$b" && ok "brief lists the new local task" || bad "brief section missing: $(cat "$b" 2>/dev/null | head -20)"
! grep -q 'Personal tinkering' "$b" && ok "company-only rule still applies (hobby project absent)" || bad "personal task leaked into the brief"
grep -q 'Exemptions: 1 session' "$b" && ok "brief counts exemptions" || bad "exemption count"
grep -q 'dots-task promote' "$b" && ok "brief says how to promote" || bad "promote hint"

echo "9. static: nothing leaves the machine"
if grep -nE 'https?://' "$pkg/dots_overview/gate.py" "$pkg/dots_overview/task.py" "$bindir"/executable_dots-task* "$bindir/executable_dots-statusline" | grep -vE 'https?://(127\.0\.0\.1|localhost)(:[0-9]+)?(/|$|")'; then bad "non-loopback URL literal"; else ok "every URL literal is loopback"; fi
if grep -nE '\b(curl|wget|gh |requests|httpx|smtplib|socket\.)' "$pkg/dots_overview/gate.py" "$pkg/dots_overview/task.py" "$bindir/executable_dots-task-hook" | grep -vE '^\S+:[0-9]+:\s*#'; then bad "network client in the task code"; else ok "no network client, no gh, no curl"; fi
grep -q 'DOTS_TASK_GATE.*off' "$pkg/dots_overview/sources_erp.py" && ok "the ERP mcp job (claude -p) sets DOTS_TASK_GATE=off" || bad "overview-sync claude -p is not exempted"

[ "$fails" = 0 ] && echo "taskgate ok" || { echo "taskgate: $fails failure(s)"; exit 1; }
