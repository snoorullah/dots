#!/usr/bin/env bash
# Work tracking (dots-overview): the Taskwarrior schema, the Claude hook, the installer, and
# the end-to-end path  hook -> ingest -> task -> dots-jump  and  GitHub -> mirror -> done.
#
# Everything runs against a scratch TASKRC / TASKDATA / state dir with stub gh, herdr and
# timew on PATH. The stubs LOG every call, so "nothing was written to GitHub" is asserted
# from the log, not assumed. No network, no real herdr, no real Taskwarrior data.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
pkg="$root/nix/pkgs/dots-overview"
stubs="$pkg/tests/stubs"
fix="$pkg/tests/fixtures"
hook="$root/home/private_dot_local/private_bin/executable_dots-track-hook"
rc="$root/home/create_dot_taskrc"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fails=$((fails + 1)); }
check() { # name, command...
  local n=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi
}

# a `dots-overview` on PATH, the way the nix package provides it
mkdir -p "$tmp/bin"
cat > "$tmp/bin/dots-overview" <<EOF
#!/bin/sh
PYTHONPATH="$pkg" exec python3 -m dots_overview "\$@"
EOF
cp "$root/home/private_dot_local/private_bin/executable_dots-jump" "$tmp/bin/dots-jump"
cp "$stubs"/gh "$stubs"/herdr "$stubs"/timew "$tmp/bin/"
chmod +x "$tmp/bin/"*

echo "1. taskrc carries every UDA"
for u in ref src srcstate srcsync url agent sess pane wspace parentref; do
  grep -q "^uda\.$u\.type=" "$rc" && ok "uda.$u" || bad "uda.$u missing from create_dot_taskrc"
done
grep -q '^uda\.parent\.' "$rc" && bad "uda.parent is a reserved core attribute; taskwarrior rejects it" || ok "no reserved uda.parent"
grep -q '^uda.srcsync.type=date' "$rc" && ok "srcsync is a date" || bad "srcsync is not a date"

echo "1b. the documented live 'task config' block works on a bare taskrc"
(
  export TASKRC="$tmp/live-rc" TASKDATA="$tmp/live-data"; mkdir -p "$TASKDATA"; printf 'data.location=%s\n' "$TASKDATA" > "$TASKRC"
  sed -n '/^```sh$/,/^```$/p' "$root/docs/overview-tracking.md" | sed '1d;$d' > "$tmp/live-config.sh"
  bash "$tmp/live-config.sh" >/dev/null 2>&1 \
    && task rc.confirmation=off rc.verbose=nothing add ref:gh:a/b#1 src:gh srcstate:issue:open srcsync:2026-10-28T10:00:00 url:https://x agent:Vega sess:s pane:w1:p1 wspace:w1 parentref:HD-1 -- "uda check" >/dev/null 2>&1
) && ok "every UDA is accepted after the documented commands" || bad "docs/overview-tracking.md task config block failed"
for u in ref src srcstate srcsync url agent sess pane wspace parentref; do
  grep -q "^uda\.$u\.label=" "$rc" || bad "uda.$u has no label in the taskrc"
done

echo "2. scratch Taskwarrior: ref lookup, done with hooks on"
export TASKRC="$tmp/taskrc" TASKDATA="$tmp/task" TIMEW_LOG="$tmp/timew.log" TIMEWARRIORDB="$tmp/timewdb"
mkdir -p "$TASKDATA/hooks"; : > "$TIMEW_LOG"
sed -e "s#^data.location=.*#data.location=$TASKDATA#" "$rc" > "$TASKRC"
# the real on-modify hook if this machine has it, else the same two start/stop rules
if [ -x "$HOME/.task/hooks/on-modify.timewarrior" ]; then cp "$HOME/.task/hooks/on-modify.timewarrior" "$TASKDATA/hooks/"
else cat > "$TASKDATA/hooks/on-modify.timewarrior" <<'EOF'
#!/usr/bin/env bash
read -r old; read -r new
get(){ printf '%s' "$1" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('$2',''))"; }
o=$(get "$old" start); n=$(get "$new" start)
[ -z "$o" ] && [ -n "$n" ] && timew start x :quiet
[ -n "$o" ] && [ -z "$n" ] && timew stop :quiet
printf '%s\n' "$new"
EOF
fi
chmod +x "$TASKDATA/hooks/on-modify.timewarrior"
export PATH="$tmp/bin:$PATH"
tw() { task rc.confirmation=off rc.verbose=nothing "$@"; }
tw add +mirror ref:gh:acme/r#1 src:gh srcstate:issue:open url:https://example.com/1 -- "first" >/dev/null 2>&1
tw add +mirror ref:HD-2 src:erp -- "second" >/dev/null 2>&1
n=$(task rc.json.array=on 'ref.is:gh:acme/r#1' export 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$n" = 1 ] && ok "ref.is: returns exactly one task" || bad "ref.is: returned $n"
n=$(task rc.json.array=on 'ref.is:nope' export 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$n" = 0 ] && ok "ref.is: returns none for an unknown ref" || bad "unknown ref returned $n"
uuid=$(task rc.json.array=on 'ref.is:HD-2' export 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["uuid"])')
tw "$uuid" modify srcstate:hd:resolved srcsync:2026-10-28T10:00:00 >/dev/null 2>&1 && ok "modify srcstate/srcsync with hooks on" || bad "modify with hooks on"
tw "$uuid" "done" >/dev/null 2>&1 && ok "task done with the timewarrior hook on" || bad "task done failed with hooks on"
[ "$(task rc.json.array=on "$uuid" export 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["status"])')" = completed ] && ok "task is completed" || bad "task not completed"
[ ! -s "$TIMEW_LOG" ] && ok "done on a task that never started leaves timewarrior alone" || bad "timew was called: $(cat "$TIMEW_LOG")"
u1=$(task rc.json.array=on 'ref.is:gh:acme/r#1' export 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["uuid"])')
tw "$u1" start >/dev/null 2>&1; tw "$u1" "done" >/dev/null 2>&1 && ok "start then done with hooks on" || bad "start/done failed"
grep -q '^start' "$TIMEW_LOG" && ok "the hook still sees start" || bad "hook did not run on start"
rm -rf "$TASKDATA"/*.sqlite3* "$TASKDATA"/*.data; : > "$TIMEW_LOG"

echo "3. hook binary: silent, exit 0, records, skips what it must"
export HERDR_LOG="$tmp/herdr.log"; : > "$HERDR_LOG"
st="$tmp/state"; export DOTS_OVERVIEW_STATE_DIR="$st"
run_hook() { # action fixture [extra env...]
  local action=$1 file=$2; shift 2
  out=$(env HERDR_ENV=1 HERDR_PANE_ID=w9:p1 "$@" sh "$hook" "$action" < "$file" 2>/dev/null); rc_=$?
  [ -z "$out" ] && [ "$rc_" = 0 ]
}
for pair in "session session.json" "prompt prompt.json" "prompt prompt-ticket.json" "stop stop.json" "end end.json" \
            "prompt subagent-prompt.json" "prompt hostile-session-id.json" "prompt malformed.txt" "prompt empty.txt"; do
  set -- $pair
  run_hook "$1" "$fix/hooks/$2" && ok "$1 < $2: empty stdout, exit 0" || bad "$1 < $2: output or non-zero exit"
done
run_hook bogus "$fix/hooks/prompt.json" && ok "unknown action exits 0" || bad "unknown action"

# every child hangs: the SessionStart path (pane get + name + report-metadata) must still end under
# the installer's 5 s timeout, silent, exit 0
mkdir -p "$tmp/slow"
for c in herdr dots-overview; do printf '#!/bin/sh\nexec sleep 30\n' > "$tmp/slow/$c"; chmod +x "$tmp/slow/$c"; done
t0=$(date +%s%N)
out=$(env PATH="$tmp/slow:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:p1 DOTS_OVERVIEW_STATE_DIR="$tmp/state-slow" sh "$hook" session < "$fix/hooks/session.json" 2>/dev/null); rc_=$?
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
[ -z "$out" ] && [ "$rc_" = 0 ] && ok "hung children: silent, exit 0" || bad "hung children: output or exit $rc_"
[ "$ms" -lt 4900 ] && ok "hung children: session hook ends in ${ms} ms (< 5 s installer timeout)" || bad "session hook took ${ms} ms"
python3 - "$hook" <<'PYT' && ok "child timeouts in the hook sum to <= 4 s" || bad "child timeouts exceed 4 s"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"T_PANE, T_NAME, T_META = ([\d.]+), ([\d.]+), ([\d.]+)", src)
assert m and sum(map(float, m.groups())) <= 4.0
body = src.split("def run(")[1].split("def write_atomic")[0]
assert "min(timeout, DEADLINE" in body
PYT
# sessions.jsonl is a ring: a hand-grown 6000-line log is trimmed by the next hook run
mkdir -p "$tmp/state-ring"
python3 -c "
import json
print('\n'.join(json.dumps({'v':1,'pad':'x'*90,'n':i}) for i in range(6000)))" > "$tmp/state-ring/sessions.jsonl"
run_hook stop "$fix/hooks/stop.json" DOTS_OVERVIEW_STATE_DIR="$tmp/state-ring"
n=$(wc -l < "$tmp/state-ring/sessions.jsonl"); [ "$n" -le 5001 ] && [ "$n" -ge 4900 ] && ok "sessions.jsonl trimmed to the ring ($n lines)" || bad "sessions.jsonl has $n lines"
sid=11111111-2222-3333-4444-555555555555
[ -f "$st/sessions/$sid.json" ] && ok "session record written" || bad "no session record"
[ "$(stat -c %a "$st/sessions/$sid.json" "$st/sessions.jsonl" | sort -u)" = 600 ] && ok "records are mode 0600" || bad "record mode"
[ "$(stat -c %a "$st")" = 700 ] && ok "state dir is mode 0700" || bad "state dir mode"
[ ! -e "$st/sessions/evil.json" ] && [ -z "$(find "$st" -name '*evil*')" ] && ok "hostile session id never becomes a path" || bad "hostile id escaped"
! grep -q 'sub-1\|ZZ-1' "$st/sessions.jsonl" && ok "subagents are skipped" || bad "subagent recorded"
lines=$(wc -l < "$st/sessions.jsonl")
[ "$lines" = 5 ] && ok "5 events recorded (session, 2 prompts, stop, end)" || bad "expected 5 lines, got $lines"
python3 - "$st" <<'EOF' && ok "ticket regex takes the 3-segment id, and the ticket is sticky" || bad "ticket handling"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1] + "/sessions.jsonl")]
by = {}
for r in rows: by.setdefault(r["action"], []).append(r)
assert by["prompt"][1]["ticket"] == "TASK-2026-00512", by["prompt"][1]["ticket"]
assert by["stop"][0]["ticket"] == "TASK-2026-00512"        # sticky within the session
assert by["session"][0]["ticket"] is None                  # a new session starts clean
assert by["prompt"][0]["prompt_head"] == "please fix the intake form validation"
assert all(r["v"] == 1 and r["pane"] == "w9:p1" and r["workspace"] == "w9" and r["tab"] == "w9:t1" for r in rows)
EOF
before=$(wc -l < "$st/sessions.jsonl")
env -u HERDR_ENV HERDR_PANE_ID=w9:p1 sh "$hook" prompt < "$fix/hooks/prompt.json" >/dev/null 2>&1
[ "$(wc -l < "$st/sessions.jsonl")" = "$before" ] && ok "outside herdr it records nothing" || bad "recorded outside herdr"
grep -q 'report-metadata w9:p1 --source dots-track --display-agent' "$HERDR_LOG" && ok "session labels the pane (pane id first)" || bad "no report-metadata call: $(cat "$HERDR_LOG")"
! grep -v '^[[:space:]]*#' "$hook" | grep -qiE '\btask(warrior)?\b' && ok "the hook never calls taskwarrior" || bad "hook code mentions task"

echo "4. installer merges both hooks into a COPY of settings"
home="$tmp/home"; mkdir -p "$home/.claude" "$home/.local/bin"
cat > "$home/.claude/settings.json" <<'EOF'
{"model": "keep-me", "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "herdr-report session"}]}],
 "Notification": [{"hooks": [{"type": "command", "command": "notify-hook"}]}]}}
EOF
printf '#!/bin/sh\nexit 0\n' > "$home/.local/bin/timetrack-ticket-hook"; cp "$home/.local/bin/timetrack-ticket-hook" "$home/.local/bin/dots-track-hook"
chmod +x "$home/.local/bin/"*
HOME="$home" chezmoi execute-template --source "$root/home" < "$root/home/.chezmoiscripts/run_onchange_after_30-claude-hooks.sh.tmpl" > "$tmp/installer.sh" 2>"$tmp/inst.err" \
  && ok "installer template renders" || bad "installer template: $(cat "$tmp/inst.err")"
[ "$(grep -c '^# live: ' "$tmp/installer.sh")" = 1 ] && ok "hash probe is exactly one line" || bad "hash probe is not one line"
HOME="$home" bash "$tmp/installer.sh" >"$tmp/inst1.out" 2>&1 && ok "installer runs" || bad "installer failed: $(cat "$tmp/inst1.out")"
python3 - "$home/.claude/settings.json" <<'EOF' && ok "four events, both hooks on UserPromptSubmit, foreign hooks kept" || bad "settings shape"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "keep-me"
h = d["hooks"]
cmds = lambda ev: [x["command"] for e in h[ev] for x in e["hooks"]]
assert any("dots-track-hook prompt" in c for c in cmds("UserPromptSubmit"))
assert any("timetrack-ticket-hook prompt" in c for c in cmds("UserPromptSubmit"))
assert any("dots-track-hook session" in c for c in cmds("SessionStart")) and "herdr-report session" in cmds("SessionStart")
assert any("dots-track-hook stop" in c for c in cmds("Stop"))
assert any("dots-track-hook end" in c for c in cmds("SessionEnd"))
assert "notify-hook" in cmds("Notification")
assert not any("timetrack-ticket-hook" in c for ev in ("Stop", "SessionEnd") for c in cmds(ev))
assert all(x.get("timeout") == 5 for ev in ("Stop", "SessionEnd") for e in h[ev] for x in e["hooks"])
EOF
cp "$home/.claude/settings.json" "$tmp/settings.after1"
HOME="$home" bash "$tmp/installer.sh" 2>&1 | grep -q 'already registered' && ok "second run is a no-op" || bad "second run changed things"
cmp -s "$home/.claude/settings.json" "$tmp/settings.after1" && ok "settings byte-identical after the second run" || bad "settings drifted"
[ "$(grep -c 'timetrack-ticket-hook\|dots-track-hook' "$home/.claude/settings.json")" = 6 ] && ok "probe counts both markers" || bad "probe count"

echo "5. end to end: hook -> ingest -> task -> dots-jump"
st2="$tmp/state2"; export DOTS_OVERVIEW_STATE_DIR="$st2" DOTS_WORK_CONF="$tmp/none.conf" TIMEWARRIORDB="$tmp/nodb"
sed -e "s#^data.location=.*#data.location=$TASKDATA#" "$rc" > "$TASKRC"; mkdir -p "$TASKDATA"; rm -rf "$TASKDATA/hooks"
run_hook session "$fix/hooks/session.json"; run_hook prompt "$fix/hooks/prompt.json"
dots-overview ingest >/dev/null 2>&1 && ok "ingest runs" || bad "ingest failed"
python3 - <<'EOF' && ok "task carries agent, sess, pane, wspace (and src claude)" || bad "task attributes"
import json, subprocess
t = json.loads(subprocess.run(["task", "rc.json.array=on", "status:pending", "export"], capture_output=True, text=True).stdout)
assert len(t) == 1, t
t = t[0]
assert t["src"] == "claude" and t["sess"] == "11111111-2222-3333-4444-555555555555", t
assert t["pane"] == "w9:p1" and t["wspace"] == "w9" and t["agent"], t
assert t["description"] == "please fix the intake form validation"
EOF
dots-overview ingest >/dev/null 2>&1; [ "$(task rc.json.array=on status:pending export 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" = 1 ] && ok "ingest is idempotent" || bad "second ingest duplicated"
agent=$(dots-overview name 11111111-2222-3333-4444-555555555555)
: > "$HERDR_LOG"
dots-jump "$agent" >/dev/null 2>&1 && ok "dots-jump <agent> runs" || bad "dots-jump failed"
grep -q '^workspace focus w9$' "$HERDR_LOG" && ok "it focuses the workspace" || bad "no workspace focus: $(cat "$HERDR_LOG")"
dots-jump --dry-run "$agent" 2>&1 | grep -q 'herdr workspace focus w9' && ok "dry-run prints the plan" || bad "dry-run output"
dots-jump --resume "$agent" 2>&1 | grep -qx 'claude --resume 11111111-2222-3333-4444-555555555555' && ok "--resume prints the claude command" || bad "--resume output"
dots-jump --last --dry-run 2>&1 | grep -q 'herdr workspace focus w9' && ok "dots-jump --last resolves the newest task with a pane" || bad "dots-jump --last"
# every dots-overview / dots-jump argv the shell's overview module execs must parse and act
dots-overview focus start >/dev/null 2>&1 && grep -q '"state":"running"' "$st2/focus.json" && ok "dots-overview focus start" || bad "focus start"
dots-overview focus break >/dev/null 2>&1 && grep -q '"state":"break"' "$st2/focus.json" && ok "dots-overview focus break" || bad "focus break"
dots-overview focus stop >/dev/null 2>&1 && grep -q '"state":"idle"' "$st2/focus.json" && ok "dots-overview focus stop" || bad "focus stop"
dots-overview focus pause >/dev/null 2>&1; [ $? -ne 0 ] && ok "an unknown focus action is refused" || bad "focus pause accepted"
dots-overview report --help >/dev/null 2>&1 && dots-overview breakdown --help 2>&1 | grep -q -- --start && ok "report and breakdown <ref> --start parse" || bad "report/breakdown argv"
cat > "$tmp/bin/dbus-monitor" <<'DBUS'
#!/bin/sh
cat <<'OUT'
method call time=1.0 sender=:1.5 -> destination=org.freedesktop.Notifications serial=3 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify
   string "notify-send"
   uint32 0
   string ""
   string "Build ok"
   string "nothing private"
   array [
   ]
   array [
   ]
   int32 -1
OUT
DBUS
chmod +x "$tmp/bin/dbus-monitor"
dots-overview notifylog >/dev/null 2>&1 && grep -q '"summary":"Build ok"' "$st2/notifications.jsonl" && ! grep -q 'nothing private' "$st2/notifications.jsonl" \
  && ok "dots-overview notifylog logs the summary, not the body" || bad "notifylog"
dots-overview fast >/dev/null 2>&1 && ok "fast cycle runs" || bad "fast cycle failed"
for f in now activity attention heatmap meta; do [ -f "$st2/$f.json" ] && ok "$f.json written" || bad "$f.json missing"; done

echo "6. GitHub -> mirror -> done, read-only"
export GH_FIX="$fix/gh" GH_LOG="$tmp/gh.log" DOTS_OVERVIEW_GH_SLEEP=0
printf 'WORK_GH_ORG=acme\n' > "$tmp/work.conf"; export DOTS_WORK_CONF="$tmp/work.conf"; : > "$GH_LOG"
dots-overview sync >"$tmp/sync.out" 2>&1 && ok "sync runs" || bad "sync failed: $(cat "$tmp/sync.out")"
dots-overview sync >/dev/null 2>&1
n=$(task rc.json.array=on +mirror src:gh status:pending export 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$n" = 4 ] && ok "4 mirror tasks after two syncs (idempotent)" || bad "expected 4 gh mirror tasks, got $n"
python3 - <<'EOF' && ok "only company items carry +work; reviews carry +attn" || bad "tags"
import json, subprocess
t = {x["ref"]: x for x in json.loads(subprocess.run(["task", "rc.json.array=on", "src:gh", "export"], capture_output=True, text=True).stdout)}
assert "work" in t["gh:acme/r#1"]["tags"] and "work" not in t["gh:me/dots#9"]["tags"], t
assert "attn" in t["gh:acme/r#3"]["tags"] and "attn" not in t["gh:acme/r#2"]["tags"]
assert t["gh:acme/r#3"]["srcstate"] == "review:open"
EOF
dots-overview detect >"$tmp/detect.out" 2>&1 && ok "detect runs" || bad "detect failed: $(cat "$tmp/detect.out")"
python3 - <<'EOF' && ok "closed issue, merged PR and submitted review are completed; the open one is not" || bad "completion"
import json, subprocess
t = {x["ref"]: x for x in json.loads(subprocess.run(["task", "rc.json.array=on", "src:gh", "export"], capture_output=True, text=True).stdout)}
assert t["gh:acme/r#1"]["status"] == "completed" and t["gh:acme/r#1"]["srcstate"] == "issue:closed", t["gh:acme/r#1"]
assert t["gh:acme/r#2"]["status"] == "completed" and t["gh:acme/r#2"]["srcstate"] == "pr:merged"
assert t["gh:acme/r#3"]["status"] == "completed" and t["gh:acme/r#3"]["srcstate"] == "review:reviewed"
assert t["gh:me/dots#9"]["status"] == "pending"
assert "srcsync" in t["gh:acme/r#1"]
EOF
python3 - "$st2" <<'EOF' && ok "mirror.json lists closed refs with closedAt" || bad "mirror.json"
import json, sys
m = json.load(open(sys.argv[1] + "/mirror.json"))
r = {x["ref"]: x for x in m["refs"]}
assert r["gh:acme/r#1"]["closedAt"] and r["gh:acme/r#3"]["reviewedAt"] and r["gh:me/dots#9"]["closedAt"] is None
EOF
! grep -qE -- '(^| )(-X|--method|-f|--field|--raw-field)( |$)|^(pr|issue) (comment|review|merge|close|reopen|edit|create)' "$GH_LOG" \
  && ok "gh was only ever asked to read ($(wc -l < "$GH_LOG") calls)" || bad "a write-shaped gh call: $(grep -E -- '-X|--method|comment|merge|close' "$GH_LOG")"
searches=$(grep -c '^search' "$GH_LOG"); [ "$searches" -le 12 ] && ok "search calls stay within budget ($searches over 2 syncs)" || bad "too many searches: $searches"
GH_QUOTA=2 dots-overview sync >/dev/null 2>&1; : > "$GH_LOG"; GH_QUOTA=2 dots-overview sync >/dev/null 2>&1
! grep -q '^search' "$GH_LOG" && ok "low search quota aborts before any search" || bad "searched with no quota"
dots-overview doctor >"$tmp/doctor.out" 2>&1; rcd=$?
[ "$rcd" = 0 ] && ok "doctor passes on a healthy tree" || bad "doctor failed: $(cat "$tmp/doctor.out")"
rm "$st2/mirror.json"; dots-overview doctor >/dev/null 2>&1 && bad "doctor passed with a missing source file" || ok "doctor exits non-zero on a missing file"

echo "6b. breakdown + start with the local model, clean and hostile"
printf '#!/bin/sh\ncat "$LLM_OUT"\n' > "$tmp/bin/llm"
printf '#!/bin/sh\necho "$*" >> "%s/open.log"\n' "$tmp" > "$tmp/bin/xdg-open"; chmod +x "$tmp/bin/llm" "$tmp/bin/xdg-open"
export LLM_OUT="$tmp/llm.out"
tw add +mirror ref:HD-50 src:erp url:https://erp.example.com/app/hd-ticket/HD-50 project:work -- "Parent ticket title" >/dev/null 2>&1
printf '["Read the ticket body", "Reproduce the problem", "Ship a fix"]' > "$LLM_OUT"
dots-overview breakdown HD-50 --start >"$tmp/bd.out" 2>&1 && ok "breakdown --start runs" || bad "breakdown failed: $(cat "$tmp/bd.out")"
python3 - <<'EOF' && ok "3 subtasks with parentref + project, the first one started" || bad "subtasks"
import json, subprocess
t = json.loads(subprocess.run(["task", "rc.json.array=on", "+sub", "export"], capture_output=True, text=True).stdout)
assert len(t) == 3, len(t)
assert all(x["parentref"] == "HD-50" and x["project"] == "work" and "mirror" in x["tags"] for x in t)
assert [bool(x.get("start")) for x in sorted(t, key=lambda x: x["description"])].count(True) == 1
EOF
grep -qx 'https://erp.example.com/app/hd-ticket/HD-50' "$tmp/open.log" && ok "opened the ticket url" || bad "xdg-open not called: $(cat "$tmp/open.log" 2>/dev/null)"
tw add +mirror ref:HD-51 src:erp -- "Second parent ticket" >/dev/null 2>&1
printf '$(touch %s/PWNED) `touch %s/PWNED2`; [' "$tmp" "$tmp" > "$LLM_OUT"
dots-overview breakdown HD-51 >/dev/null 2>&1 && ok "hostile model output still succeeds (fallback)" || bad "hostile output broke breakdown"
[ ! -e "$tmp/PWNED" ] && [ ! -e "$tmp/PWNED2" ] && ok "nothing the model said was executed" || bad "model output was executed"
[ "$(task rc.json.array=on parentref:HD-51 export 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" = 1 ] && ok "fallback is one subtask" || bad "fallback count"
: > "$LLM_OUT"; dots-overview breakdown HD-51 >/dev/null 2>&1 && ok "an empty model answer still succeeds" || bad "empty answer broke breakdown"

echo "7. static: nothing in the package can write to GitHub"
if grep -rnE 'gh api -X|"-X"|--method|-X (POST|PUT|PATCH|DELETE)' "$pkg/dots_overview" "$root/home/private_dot_local/lib/dots-ops/jobs/overview-sync.sh"; then bad "write-shaped GitHub call in the source"; else ok "no gh api -X / --method anywhere"; fi

echo "8. python unit tests"
if out=$(cd "$pkg" && python3 -m unittest discover -s tests 2>&1); then ok "$(echo "$out" | grep -E '^Ran')"; else bad "unit tests failed"; echo "$out" | tail -n 30; fi

echo "9. work.conf.example is placeholders only"
ex="$root/home/private_dot_config/dots-work/work.conf.example"
grep -q '^ERP_MODE=off' "$ex" && ok "ERP defaults to off" || bad "ERP_MODE is not off in the example"
grep -qiE "$(printf 'pnow|proficient|kaarbaaz|code42|%s|@' "web""sleak")" "$ex" && bad "the example names a company or address" || ok "example names no company or address"
grep -qE 'example-org|example\.com' "$ex" && ok "uses placeholder values" || bad "placeholders missing"

[ "$fails" = 0 ] && echo "track ok" || { echo "track: $fails failure(s)"; exit 1; }
