#!/usr/bin/env bash
# layout: tests for dots-layout (save / status / restore / undo / startup / note), the layout
# timer units and the static rules. No compositor and no herdr: hyprctl and herdr are fakes
# that read fixtures and log what they were asked to run.
#   1  save        clients (class, workspace, geometry, argv from /proc), herdr panes, agents PAUSED, 0600
#   2  guard       a pending prompt blocks saving; an empty desktop saves nothing; old files are pruned
#   3  status      the prompt summary, pending until answered, "Back to last set" after
#   4  restore     plan: argv only, workspace rules, skips what is open, never resumes agents; apply; undo
#   5  startup     a named set onto a workspace; note get/set/save
#   6  static      no shell, no network, no hex, units well formed
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
tool="$root/home/private_dot_local/private_bin/executable_dots-layout"
units="$root/home/private_dot_config/systemd/private_user"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
ok()  { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# ---- fakes -------------------------------------------------------------------------------
mkdir -p "$work/bin" "$work/proc" "$work/state"
cat > "$work/bin/hyprctl" <<'PY'
#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_LOG"]
a = sys.argv[1:]
if a[:2] == ["clients", "-j"]:
    p = os.environ["FAKE_CLIENTS"]
    sys.stdout.write(open(p).read() if os.path.exists(p) else "[]")
elif a and a[0] == "dispatch":
    open(log, "a").write("dispatch " + a[1] + "\n"); print("ok")
elif a and a[0] == "--batch":
    open(log, "a").write("batch " + a[1] + "\n"); print("ok\nok")
else:
    sys.exit(1)
PY
cat > "$work/bin/herdr" <<'PY'
#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_LOG"]
a = sys.argv[1:]
def out(o): print(json.dumps(o))
if a[:2] == ["pane", "list"]:
    out({"result": {"panes": json.load(open(os.environ["FAKE_PANES"]))}})
elif a[:2] == ["workspace", "list"]:
    out({"result": {"workspaces": json.load(open(os.environ["FAKE_WSS"]))}})
elif a[:2] == ["workspace", "create"]:
    open(log, "a").write("herdr " + " ".join(a) + "\n"); out({"result": {"workspace": {"workspace_id": "wN1"}}})
elif a[:2] == ["tab", "create"]:
    open(log, "a").write("herdr " + " ".join(a) + "\n"); out({"result": {"tab": {"tab_id": "wN1:t2"}}})
elif a[1:2] == ["close"]:
    open(log, "a").write("herdr " + " ".join(a) + "\n"); out({"result": {}})
else:
    sys.exit(1)
PY
chmod +x "$work/bin/hyprctl" "$work/bin/herdr"

# a synthetic desktop: nothing here names a real machine
cat > "$work/clients.json" <<'JSON'
[
 {"address":"0x1a","mapped":true,"class":"term","pid":101,"workspace":{"id":3,"name":"3"},"floating":false,"at":[10,40],"size":[900,600],"grouped":[]},
 {"address":"0x1b","mapped":true,"class":"term","pid":102,"workspace":{"id":3,"name":"3"},"floating":false,"at":[910,40],"size":[900,600],"grouped":["0x1b","0x1c"]},
 {"address":"0x1c","mapped":true,"class":"term","pid":103,"workspace":{"id":3,"name":"3"},"floating":false,"at":[910,40],"size":[900,600],"grouped":["0x1b","0x1c"]},
 {"address":"0x2a","mapped":true,"class":"browser","pid":104,"workspace":{"id":2,"name":"2"},"floating":false,"at":[0,0],"size":[1800,900],"grouped":[]},
 {"address":"0x3a","mapped":true,"class":"notes","pid":105,"workspace":{"id":-99,"name":"special:scratch-dev"},"floating":true,"at":[100,100],"size":[700,500],"grouped":[]},
 {"address":"0x4a","mapped":true,"class":"leaky","pid":106,"workspace":{"id":4,"name":"4"},"floating":false,"at":[0,0],"size":[800,600],"grouped":[]},
 {"address":"0x5a","mapped":false,"class":"ghost","pid":107,"workspace":{"id":4,"name":"4"},"floating":false,"at":[0,0],"size":[1,1],"grouped":[]}
]
JSON
mkproc() { mkdir -p "$work/proc/$1"; printf '%s\0' "${@:2}" > "$work/proc/$1/cmdline"; }
mkproc 101 term --class term
mkproc 102 term --class term
mkproc 103 term --class term
mkproc 104 browser --profile work --password-store=basic "--new-window=a b"
mkproc 105 notes
mkproc 106 leaky --api-key=abc123
cat > "$work/panes.json" <<'JSON'
[
 {"pane_id":"w1:p1","workspace_id":"w1","cwd":"/srv/alpha","agent":"agentx","agent_status":"working"},
 {"pane_id":"w1:p2","workspace_id":"w1","cwd":"/srv/alpha/sub"},
 {"pane_id":"w2:p1","workspace_id":"w2","cwd":"/srv/beta","agent":"agentx","agent_status":"done"},
 {"pane_id":"w2:p2","workspace_id":"w2","cwd":"/srv/beta/docs"}
]
JSON
cat > "$work/wss.json" <<'JSON'
[{"workspace_id":"w1","label":"alpha"},{"workspace_id":"w2","label":"beta"}]
JSON
echo '[]' > "$work/empty.json"

export PATH="$work/bin:$PATH" FAKE_LOG="$work/log" FAKE_CLIENTS="$work/clients.json" FAKE_PANES="$work/panes.json" FAKE_WSS="$work/wss.json"
export DOTS_LAYOUT_DIR="$work/state" DOTS_PROC="$work/proc" DOTS_HYPRCTL="$work/bin/hyprctl" DOTS_HERDR="$work/bin/herdr"
export DOTS_LAYOUT_PAUSE=0 DOTS_STARTUP_SETS="$work/startup.json"
dl() { python3 -I "$tool" "$@"; }
pj() { python3 -I -c "import json,sys; d=json.load(sys.stdin); $1"; }

# ---- 1. save -----------------------------------------------------------------------------
export DOTS_BOOT_ID=boot-A DOTS_UPTIME=99999 DOTS_NOW=2026-11-19T23:27:00
out="$(dl save)"
f="$work/state/2026-11-19.json"
[ -f "$f" ] && ok "1 save writes <date>.json" || bad "1 save wrote no file: $out"
[ "$(stat -c %a "$f")" = "600" ] && [ "$(stat -c %a "$work/state")" = "700" ] && ok "1 file 0600, directory 0700" || bad "1 permissions"
python3 -I - "$f" <<'PY' && ok "1 clients: class, workspace, geometry, argv; unmapped and secret-carrying argv dropped" || bad "1 file content"
import json, sys
d = json.load(open(sys.argv[1]))
cl = d["clients"]
assert d["boot_id"] == "boot-A" and d["saved_at"].startswith("2026-11-19T23:27"), d
assert [c["class"] for c in cl] == ["term", "term", "term", "browser", "notes", "leaky"], [c["class"] for c in cl]
t = cl[0]; assert t["workspace"] == 3 and t["at"] == [10, 40] and t["size"] == [900, 600] and t["argv"] == ["term", "--class", "term"], t
assert cl[3]["argv"] == ["browser", "--profile", "work", "--password-store=basic", "--new-window=a b"], cl[3]
assert cl[4]["workspace"] < 0 and cl[4]["workspace_name"] == "special:scratch-dev" and cl[4]["floating"], cl[4]
assert cl[5]["argv"] == [], "a window whose argv carries a key is not relaunched"
assert cl[1]["group"] == cl[2]["group"] >= 0 and cl[0]["group"] == -1, "grouped windows share a group id"
assert "title" not in t, "titles are not stored"
PY
python3 -I - "$tool" <<'PY' && ok "1 secret flags: names caught, --password-store kept" || bad "1 has_secret"
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("dl", sys.argv[1]); sp = importlib.util.spec_from_loader("dl", ld); m = importlib.util.module_from_spec(sp); ld.exec_module(m)
for argv in (["x", "--token=abc"], ["x", "--api-key", "abc"], ["x", "--client-secret=z"], ["x", "API_TOKEN=q"], ["x", "--password=p"]):
    assert m.has_secret(argv), argv
for argv in (["chrome", "--password-store=basic"], ["chrome", "--password-store=gnome-libsecret"], ["x", "--token-file=/p"], ["x", "--user-data-dir=/tmp/x"]):
    assert not m.has_secret(argv), argv
PY
python3 -I - "$f" <<'PY' && ok "1 herdr: panes by workspace, agents recorded PAUSED, done agents finished" || bad "1 herdr content"
import json, sys
h = json.load(open(sys.argv[1]))["herdr"]["workspaces"]
assert [w["label"] for w in h] == ["alpha", "beta"], h
a = h[0]["panes"]; assert a[0] == {"cwd": "/srv/alpha", "agent": "agentx", "state": "paused"}, a
assert a[1]["agent"] == "" and a[1]["state"] == "", a
assert h[1]["panes"][0]["state"] == "finished", h
PY

# ---- 2. guard and pruning ----------------------------------------------------------------
export DOTS_BOOT_ID=boot-B DOTS_UPTIME=60 DOTS_NOW=2026-11-20T08:00:00
out="$(dl save)"
echo "$out" | pj 'assert d["saved"] is False and d["why"] == "restore pending", d' && ok "2 a pending prompt blocks saving right after login" || bad "2 guard: $out"
[ ! -f "$work/state/2026-11-20.json" ] && ok "2 the earlier layout was not overwritten" || bad "2 new file written"
DOTS_UPTIME=99999 dl save | pj 'assert d["saved"], d' && ok "2 the guard expires after 30 minutes (a missing shell must not stop saving)" || bad "2 guard never expires"
rm -f "$work/state/2026-11-20.json"
FAKE_CLIENTS="$work/empty.json" FAKE_PANES="$work/empty.json" FAKE_WSS="$work/empty.json" DOTS_UPTIME=99999 dl save | pj 'assert d["saved"] is False and d["why"] == "nothing open", d' && ok "2 an empty desktop saves nothing" || bad "2 empty desktop saved"
for d in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16; do echo '{"version":1,"boot_id":"x","clients":[]}' > "$work/state/2026-10-$d.json"; done
DOTS_BOOT_ID=boot-B DOTS_UPTIME=99999 DOTS_NOW=2026-11-20T09:00:00 dl save >/dev/null
[ "$(ls "$work/state" | grep -c '^2026-.*json$')" = "14" ] && ok "2 only the newest 14 files are kept" || bad "2 pruning: $(ls "$work/state" | wc -l)"
rm -f "$work/state"/2026-10-*.json "$work/state/2026-11-20.json"

# ---- 3. status ---------------------------------------------------------------------------
export DOTS_BOOT_ID=boot-B DOTS_UPTIME=60
dl status | pj '
assert d["pending"] is True, d
l = d["layout"]
assert l["windows"] == 6 and l["workspaces"] == [2, 3, 4] and l["groups"] == 1, l
assert l["apps"] == ["term", "browser", "notes", "leaky"], l
assert l["panes"] == 2 and l["agents"] == 1 and l["finished"] == 1, l
assert l["saved_at"].startswith("2026-11-19T23:27"), l
assert {"class": "term", "workspace": 3, "group": -1} in l["clients"], l["clients"]
' && ok "3 status: pending with counts for the prompt" || bad "3 status"
DOTS_BOOT_ID=boot-A dl status | pj 'assert d["pending"] is False and d["layout"]["windows"] == 6, d' && ok "3 same boot: not pending, the last set stays readable" || bad "3 same boot"
dl dismiss | pj 'assert d["ok"]'
dl status | pj 'assert d["pending"] is False, d' && ok "3 Start clean answers the prompt" || bad "3 dismiss"
DOTS_UPTIME=60 dl save | pj 'assert d["saved"], d' && ok "3 saving resumes once answered" || bad "3 save after dismiss"
rm -f "$work/state/2026-11-20.json" "$work/state/state.json"

# ---- 4. restore --------------------------------------------------------------------------
# after a reboot nothing is open yet: the live desktop is empty
export FAKE_CLIENTS="$work/empty.json" FAKE_WSS="$work/empty.json"
: > "$work/log"
dl restore > "$work/plan.json"
python3 -I - "$work/plan.json" <<'PY' && ok "4 plan: argv only, workspace rules, geometry for floats, grouped windows kept in place" || bad "4 plan"
import json, sys
d = json.load(open(sys.argv[1])); s = d["steps"]
assert d["applied"] is False
l = [x for x in s if x["kind"] == "launch"]
assert len(l) == 5, [x["class"] for x in l]
assert l[0]["argv"] == ["term", "--class", "term"] and "workspace 3 silent" in l[0]["dispatch"][2], l[0]
assert l[0]["dispatch"][:2] == ["hyprctl", "dispatch"] and l[0]["dispatch"][2].startswith("hl.dsp.exec_cmd([==["), l[0]
assert "'--new-window=a b'" in [x for x in l if x["class"] == "browser"][0]["dispatch"][2], "args are shell-quoted for Hyprland"
n = [x for x in l if x["class"] == "notes"][0]["dispatch"][2]
assert "workspace special:scratch-dev silent; float; size 700 500; move 100 100" in n, n
assert any(x["kind"] == "skip" and x["class"] == "leaky" for x in s), "no saved command: skipped"
h = [x for x in s if x["kind"] == "herdr"]
assert [x["label"] for x in h] == ["alpha", "beta"], h
alpha = h[0]["panes"]; assert [p["cwd"] for p in alpha] == ["/srv/alpha", "/srv/alpha/sub"], alpha
assert [p["cwd"] for p in h[1]["panes"]] == ["/srv/beta/docs"], "finished agents are listed only, not reopened"
assert "agentx" not in json.dumps([x["dispatch"] for x in l]), "no agent is ever started"
PY
dl restore --parts apps | pj 'assert not [x for x in d["steps"] if x["kind"] == "herdr"] and "workspace" not in str([x["dispatch"] for x in d["steps"] if x["kind"] == "launch"]), d' && ok "4 parts: apps alone places nothing and opens no panes" || bad "4 parts"
dl restore --parts finished,panes | pj 'h=[x for x in d["steps"] if x["kind"]=="herdr"]; assert [len(x["panes"]) for x in h] == [1, 2], h' && ok "4 parts: finished agents come back only when asked" || bad "4 finished part"
dl restore --workspaces 3 | pj 'l=[x for x in d["steps"] if x["kind"]=="launch"]; assert [x["class"] for x in l] == ["term","term","term"] and not [x for x in d["steps"] if x["kind"]=="herdr"], d' && ok "4 workspaces filter: one profile's set only" || bad "4 workspaces"
printf '[{"address":"0x9z","class":"term","pid":1,"workspace":{"id":3,"name":"3"}},{"address":"0x9y","class":"term","pid":1,"workspace":{"id":3,"name":"3"}},{"address":"0x9x","class":"term","pid":1,"workspace":{"id":3,"name":"3"}}]' > "$work/open.json"
FAKE_CLIENTS="$work/open.json" dl restore --workspaces 3 | pj 'assert not [x for x in d["steps"] if x["kind"]=="launch"] and len([x for x in d["steps"] if x["kind"]=="skip"]) == 3, d' && ok "4 apps already open are not opened twice" || bad "4 skip open"
[ ! -s "$work/log" ] && ok "4 a plan runs nothing" || bad "4 plan ran something: $(cat "$work/log")"
res="$(dl restore --apply)"
echo "$res" | pj 'assert d["ok"] and d["applied"] and d["launched"] == 8 and d["failed"] == 0 and d["skipped"] == 1, d' && ok "4 apply: 5 apps and 3 herdr workspaces/tabs started" || bad "4 apply: $res"
grep -c '^dispatch hl.dsp.exec_cmd' "$work/log" | grep -qx 5 && grep -q 'herdr workspace create --cwd /srv/alpha --label alpha --no-focus' "$work/log" && grep -q 'herdr tab create --workspace wN1 --cwd /srv/alpha/sub --no-focus' "$work/log" && ok "4 apply: the dispatches and herdr calls the plan named" || bad "4 apply log: $(cat "$work/log")"
dl status | pj 'assert d["pending"] is False' && ok "4 restoring answers the prompt" || bad "4 still pending"
# undo closes only what appeared after the restore and was launched by it
printf '[{"address":"0xaa","class":"term","pid":1,"workspace":{"id":3,"name":"3"}},{"address":"0xbb","class":"other","pid":2,"workspace":{"id":3,"name":"3"}}]' > "$work/after.json"
: > "$work/log"
FAKE_CLIENTS="$work/after.json" dl undo | pj 'assert d["ok"] and d["closed"] == 1, d' && ok "4 undo closes the restored windows, not the others" || bad "4 undo"
grep -q 'address:0xaa' "$work/log" && ! grep -q '0xbb' "$work/log" && grep -q 'herdr workspace close wN1' "$work/log" && ok "4 undo: focus then close by address, herdr workspace closed" || bad "4 undo log: $(cat "$work/log")"
{ dl undo || true; } | pj 'assert d["ok"] is False' && ok "4 a second undo has nothing to do" || bad "4 double undo"
if grep -nE 'hl\.dsp\.exec_cmd\(\[==\[[^]]*(;|&&|\|\|)\s*(rm|curl|sh)' "$work/plan.json"; then bad "4 shell metacharacters outside quotes"; else ok "4 no unquoted shell metacharacters in any dispatch"; fi

# ---- 5. startup sets and notes -----------------------------------------------------------
echo '{"Dev": [["term", "--class", "dev term"], ["editor"]], "Bad": "x"}' > "$work/startup.json"
dl startup --workspace 3 --name Dev --plan | pj 'l=d["steps"]; assert len(l)==2 and "workspace 3 silent" in l[0]["dispatch"][2] and "'"'"'dev term'"'"'" in l[0]["dispatch"][2], d' && ok "5 startup set: argv onto the profile's workspace" || bad "5 startup plan"
{ dl startup --workspace 3 --name Nope || true; } | pj 'assert d["ok"] is False' && ok "5 an unknown set says so" || bad "5 unknown set"
{ dl startup --workspace 3 --name Bad || true; } | pj 'assert d["ok"] is False' && ok "5 a malformed set is refused" || bad "5 malformed set"
: > "$work/log"; dl startup --workspace 3 --name Dev | pj 'assert d["ok"] and d["launched"] == 2, d' && [ "$(grep -c '^dispatch' "$work/log")" = 2 ] && ok "5 startup apply launches both" || bad "5 startup apply"
printf 'db-02 needs two vCPUs\nsecond line' | dl note set --profile Dev | pj 'assert d["ok"]'
dl note set --profile Dev --text $'argv note\nline two' | pj 'assert d["ok"]' && dl note get --profile Dev | pj 'assert d["text"] == "argv note\nline two", d' && ok "5 note set takes --text (no stdin plumbing in the UI)" || bad "5 note --text"
printf 'db-02 needs two vCPUs\nsecond line' | dl note set --profile Dev | pj 'assert d["ok"]'
dl note get --profile Dev | pj 'assert d["text"] == "db-02 needs two vCPUs\nsecond line", d' && ok "5 note round-trips per profile" || bad "5 note get"
dl note get --profile Web | pj 'assert d["text"] == ""' && ok "5 another profile starts empty" || bad "5 note isolation"
{ dl note get --profile '../../etc/passwd' || true; } | pj 'assert d["ok"] is False' && [ "$(stat -c %a "$work/state/notes/dev.txt")" = 600 ] && ok "5 a profile name cannot leave the notes directory; notes are 0600" || bad "5 note path/perm"
dl note save --profile Dev | pj 'assert d["ok"] and d["file"].endswith(".md") and "/saved/" in d["file"], d' && ok "5 Save to notes writes a dated local copy" || bad "5 note save"
head -c 70000 /dev/zero | tr '\0' a | { dl note set --profile Dev || true; } | pj 'assert d["ok"] is False' && ok "5 an oversized note is refused" || bad "5 note size"

# tiling preset per profile
{ dl pref get --profile Dev || true; } | pj 'assert d["ok"] and d["value"] == ""' && dl pref set --profile Dev --value main-stack | pj 'assert d["ok"]' && dl pref get --profile Dev | pj 'assert d["value"] == "main-stack", d' && ok "5 each profile remembers its tiling preset" || bad "5 pref"
{ dl pref set --profile Dev --value 'x; rm' || true; } | pj 'assert d["ok"] is False' && ok "5 a preset name is validated" || bad "5 pref validation"

# ---- 6. static rules ---------------------------------------------------------------------
if grep -nE 'shell\s*=\s*True|os\.system|os\.popen|"(sh|bash|zsh)"|import (socket|urllib|http|requests)|https?://' "$tool" | grep -vE '^[0-9]+:\s*#'; then bad "6 shell or network in dots-layout"; else ok "6 no shell and no network in dots-layout"; fi
if grep -nE '#[0-9a-fA-F]{6}\b' "$tool"; then bad "6 hex in dots-layout"; else ok "6 no hex"; fi
python3 -I -m py_compile "$tool" && ok "6 dots-layout compiles" || bad "6 compile"
if grep -nE 'OnUnitActiveSec=10min' "$units/dots-layout-save.timer" >/dev/null && grep -q 'dots-layout save' "$units/dots-layout-save.service" && grep -q 'WantedBy=timers.target' "$units/dots-layout-save.timer" && grep -q 'Type=oneshot' "$units/dots-layout-save.service"; then ok "6 units: oneshot save, timer every 10 min"; else bad "6 units malformed"; fi
if grep -q 'ExecStop=.*dots-layout save --force' "$units/dots-layout-logout.service" && grep -q 'RemainAfterExit=yes' "$units/dots-layout-logout.service" && grep -q 'WantedBy=graphical-session.target' "$units/dots-layout-logout.service"; then ok "6 logout unit: save --force on session stop"; else bad "6 logout unit malformed"; fi
if grep -nE 'HD [0-9]|TASK-|k8s|ovh|proficient' "$tool" "$units"/dots-layout-* "$root/tests/layout.sh" | grep -v 'grep -nE'; then bad "6 a company name in the sources"; else ok "6 no company names"; fi

[ "$fails" -eq 0 ] && { echo "layout ok"; exit 0; }
echo "layout: $fails failure(s)"; exit 1
