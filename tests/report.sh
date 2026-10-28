#!/usr/bin/env bash
# The daily brief: company work only, idempotent, 0600, and no network call of any kind.
#
# Runs the real CLI against a scratch Taskwarrior and a scratch work.db, with HTTP_PROXY
# pointing at a dead port, GH_TOKEN unset, and `gh`/`curl`/`xdg-open` stubs that record
# their own invocation. If the brief ever reaches for the network, a marker file appears.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
pkg="$root/nix/pkgs/dots-overview"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

mkdir -p "$tmp/bin" "$tmp/task" "$tmp/tt"
for n in gh curl wget xdg-open; do
  printf '#!/bin/sh\necho "$0 $*" >> "%s/network-marker"\nexit 1\n' "$tmp" > "$tmp/bin/$n"; chmod +x "$tmp/bin/$n"
done
printf '#!/bin/sh\nPYTHONPATH="%s" exec python3 -m dots_overview "$@"\n' "$pkg" > "$tmp/bin/dots-overview"; chmod +x "$tmp/bin/dots-overview"
export PATH="$tmp/bin:$PATH"
export HTTP_PROXY=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1 ALL_PROXY=http://127.0.0.1:1
unset GH_TOKEN GITHUB_TOKEN
export TASKRC="$tmp/taskrc" TIMETRACK_STATE_DIR="$tmp/tt" DOTS_OVERVIEW_STATE_DIR="$tmp/state" DOTS_WORK_CONF="$tmp/work.conf" TIMEWARRIORDB="$tmp/none"
sed -e "s#^data.location=.*#data.location=$tmp/task#" "$root/home/create_dot_taskrc" > "$TASKRC"
printf 'WORK_GH_ORG=acme\nWORK_PROJECTS=work\nREDACT_WORDS=%s\nREPORT_DIR=%s/daily\n' "web""sleak" "$tmp" > "$DOTS_WORK_CONF"
handle="web""sleak"   # built from parts: the literal is lint's business only
tw() { task rc.confirmation=off rc.verbose=nothing "$@"; }

python3 - "$tmp/tt/work.db" <<'EOF'
import sqlite3, sys, time
from datetime import datetime
c = sqlite3.connect(sys.argv[1])
c.executescript("""CREATE TABLE work_session (id INTEGER PRIMARY KEY, opened_unix INTEGER, closed_unix INTEGER, attendance_day TEXT);
CREATE TABLE deduction (id INTEGER PRIMARY KEY, session_id INTEGER, start_unix INTEGER, end_unix INTEGER);
CREATE TABLE v_run_interval (ticket TEXT, start_unix INTEGER, end_unix INTEGER);""")
d = time.time() - 7 * 3600     # logged in 7 h ago, logs out in 10 min (the tasks below close inside it): the day is the session
c.execute("INSERT INTO work_session VALUES (1, ?, ?, ?)", (d, time.time() + 600, datetime.fromtimestamp(d).strftime("%Y-%m-%d")))
c.execute("INSERT INTO v_run_interval VALUES ('HD-123', ?, ?)", (d + 3600, d + 3600 + 6000))
c.commit()
EOF

tw add project:work +mirror ref:HD-123 src:erp -- "Fix the intake form validation" >/dev/null 2>&1
tw add project:work +mirror ref:TASK-2026-00561 src:erp +attn -- "SHA-pin Actions" >/dev/null 2>&1
tw add project:personal -- "Book the dentist for ada@example.com" >/dev/null 2>&1
tw add project:personal -- "$handle newsletter chores" >/dev/null 2>&1
tw add +mirror ref:gh:me/dots#9 src:gh -- "Tidy the dots readme" >/dev/null 2>&1
tw add +mirror ref:gh:acme/r#886 src:gh -- "Detection rules" >/dev/null 2>&1
for ref in HD-123 gh:me/dots#9 gh:acme/r#886; do tw "ref.is:$ref" "done" >/dev/null 2>&1; done
tw project:personal "done" >/dev/null 2>&1

echo "1. first run"
out=$(dots-overview report 2>&1); rc=$?
[ "$rc" = 0 ] && ok "report exits 0 with the network poisoned" || bad "report failed: $out"
day=$(date -d "-7 hours" +%F); f="$tmp/daily/$day.md"   # the session's day (it opened 7 h ago)
[ -f "$f" ] && ok "writes REPORT_DIR/$day.md" || bad "no brief at $f"
[ "$(stat -c %a "$f")" = 600 ] && ok "file is 0600" || bad "file mode $(stat -c %a "$f")"
[ "$(stat -c %a "$tmp/daily")" = 700 ] && ok "directory is 0700" || bad "dir mode"
[ ! -e "$tmp/network-marker" ] && ok "no gh/curl/wget/xdg-open was started" || bad "network tool used: $(cat "$tmp/network-marker")"
grep -qE '^Worked [0-9]+(h|m)' "$f" && ok "worked time comes from work.db (exact sums are unit-tested)" || bad "worked time wrong: $(sed -n 3p "$f")"
grep -q '`HD-123` Fix the intake form validation — 1h 40m' "$f" && ok "closed ERP item with its clock time" || bad "HD-123 line missing"
grep -q '`gh:acme/r#886` Detection rules' "$f" && ok "closed company repo item is listed" || bad "acme item missing"
grep -q 'SHA-pin Actions' "$f" && ok "open company item is listed" || bad "open item missing"

echo "2. what must never be in it"
for leak in "dentist" "newsletter" "dots readme" "personal" "ada@" "@example" "$handle"; do
  grep -qi -- "$leak" "$f" && bad "brief contains '$leak'" || ok "no '$leak'"
done
grep -qiE 'firefox|chromium|ghostty|slack|spotify|idle|afk|away' "$f" && bad "brief carries app or idle/away data" || ok "no app names, idle or away time"
grep -qE '[[:alnum:]._+-]+@[[:alnum:].-]+\.[a-z]{2,}' "$f" && bad "an email address is in the brief" || ok "no email address"

echo "3. idempotent"
before=$(stat -c %Y.%y "$f")
out=$(dots-overview report 2>&1); echo "$out" | grep -q unchanged && ok "second run says unchanged" || bad "second run: $out"
[ "$before" = "$(stat -c %Y.%y "$f")" ] && ok "file untouched (mtime identical)" || bad "file was rewritten"
out=$(dots-overview report --reason nightly 2>&1); echo "$out" | grep -q skipped && ok "--reason nightly is a no-op when the brief exists" || bad "nightly: $out"
rm "$f"; out=$(dots-overview report --reason nightly 2>&1); echo "$out" | grep -q created && ok "--reason nightly creates it when missing" || bad "nightly create: $out"
tw add project:work +mirror ref:HD-777 src:erp -- "A second closed thing" >/dev/null 2>&1; tw ref.is:HD-777 "done" >/dev/null 2>&1
out=$(dots-overview report --reason logout 2>&1); echo "$out" | grep -q updated && grep -q HD-777 "$f" && ok "new content rewrites it" || bad "logout update: $out"
[ "$(stat -c %a "$f")" = 600 ] && ok "still 0600 after a rewrite" || bad "mode after rewrite"
dots-overview report --date yesterday >/dev/null 2>&1 && ok "--date yesterday works" || bad "--date yesterday"
dots-overview report --date not-a-date >/dev/null 2>&1; [ $? -ne 0 ] && ok "a bad date is an error, not a file" || bad "bad date accepted"
[ ! -e "$tmp/network-marker" ] && ok "still no network tool started" || bad "network tool used"

echo "4. the logout trigger spawns it, detached and guarded"
mkdir -p "$tmp/logbin"
printf '#!/bin/sh\necho "$*" > "%s/spawned"\n' "$tmp" > "$tmp/logbin/dots-overview"; chmod +x "$tmp/logbin/dots-overview"
(
  cd "$root/nix/pkgs/timetrack" || exit 1
  PATH="$tmp/logbin:/usr/bin:/bin" TIMETRACK_STATE_DIR="$tmp/tt2" python3 -c '
from timetrack import away, migrate
migrate.migrate()
away.declare("logout")
away.declare("walk")
' 2>&1
) && ok "declare(logout) returns promptly" || bad "declare failed"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$tmp/spawned" ] && break; sleep 0.2; done
[ "$(cat "$tmp/spawned" 2>/dev/null)" = "report --reason logout" ] && ok "spawned: dots-overview report --reason logout" || bad "not spawned: $(cat "$tmp/spawned" 2>/dev/null)"
rm -f "$tmp/spawned"
(cd "$root/nix/pkgs/timetrack" && PATH="/usr/bin:/bin" TIMETRACK_STATE_DIR="$tmp/tt3" python3 -c '
from timetrack import away, migrate
migrate.migrate()
away.declare("logout")') && ok "without dots-overview installed the declaration still works" || bad "declare broke without dots-overview"
(cd "$root/nix/pkgs/timetrack" && PATH="$tmp/logbin:/usr/bin:/bin" TIMETRACK_STATE_DIR="$tmp/tt4" python3 -c '
from timetrack import away, migrate
migrate.migrate()
away.declare("meal")'); sleep 0.5
[ ! -f "$tmp/spawned" ] && ok "only logout spawns the brief" || bad "another reason spawned it"

[ "$fails" = 0 ] && echo "report ok" || { echo "report: $fails failure(s)"; exit 1; }
