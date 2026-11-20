#!/usr/bin/env python3
"""Build the fixtures and the case list for tests/launcher-modes.sh.

  mkcases.py <workdir> <repo root>        writes <workdir>/cases.json and one bin dir per case

Every case gets its own wrapper `dots-launch-<mode>` scripts that run the REAL helper with the
case's environment, so the QML providers in the scene talk to real helpers over real fixtures.
Nothing here touches the network, the compositor, kubectl or ssh: actions are logged, not run.
"""
import json, os, stat, struct, sys, zlib

W = os.path.abspath(sys.argv[1])
ROOT = os.path.abspath(sys.argv[2])
BIN = os.path.join(ROOT, "home", "private_dot_local", "private_bin")
PHOS = os.path.join(ROOT, "home", "private_dot_config", "quickshell", "dots", "modules", "common", "PhosphorIcons.qml")
MODES = ["files", "dict", "fonts", "windows", "snippets", "emoji", "hosts", "kube"]
cases = []


def wr(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
    if mode:
        os.chmod(path, mode)
    return path


def png(path, w=64, h=40):
    rows = b""
    for y in range(h):
        rows += b"\x00" + b"".join(bytes([40 + x * 3 % 200, 90 + y * 4 % 150, 160]) for x in range(w))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


def case(tag, mode, query="", sel=0, steps=None, env=None, files=None, **frame):
    d = os.path.join(W, "case", tag)
    bindir = os.path.join(d, "bin")
    e = {"DOTS_LAUNCHER_STATE": os.path.join(d, "state"), "DOTS_LAUNCH_EXEC_LOG": os.path.join(d, "exec.log"),
         "DOTS_HERDR_PANES": os.path.join(d, "no-panes.json"), "DOTS_PHOSPHOR_QML": PHOS}
    e.update(env or {})
    e = {k: v for k, v in e.items() if v is not None}
    for m in MODES:
        lines = ["#!/bin/sh"]
        for k, v in e.items():
            lines.append("export %s=%s" % (k, "'" + str(v).replace("'", "'\\''") + "'"))
        pre = (files or {}).get("pre_" + m, "")
        lines.append(pre)
        lines.append('exec python3 %s "$@"' % ("'" + os.path.join(BIN, "executable_dots-launch-" + m) + "'"))
        wr(os.path.join(bindir, "dots-launch-" + m), "\n".join(lines) + "\n", 0o755)
    cases.append(dict(tag=tag, mode=mode, query=query, sel=sel, steps=steps or [], bin=bindir, frame=frame))
    return d


def save_json(path, o):
    wr(path, json.dumps(o))


# ---- files ------------------------------------------------------------------------------
home = os.path.join(W, "home")
wr(home + "/work/docs/runbooks/restore.md", "## Restore\n1. Stop writes.\n2. Run restore with the latest snapshot.\n3. Verify row counts.\n")
png(home + "/Pictures/restore-drill-2026.png")
wr(home + "/powerhouse/notes/Restore drill plan.md", "# Restore drill plan\nDate to be agreed.\n")
for t, s in (("files-default", 0), ("files-image", 1), ("files-note", 2)):
    case(t, "files", "restore", s, env={"DOTS_FILES_ROOT": home}, prefix="f:")
case("files-empty", "files", "", 0, env={"DOTS_FILES_ROOT": home}, prefix="f:")
case("files-nomatch", "files", "zzzzqq", 0, env={"DOTS_FILES_ROOT": home}, prefix="f:")

# ---- dictionary ---------------------------------------------------------------------------
wn = os.path.join(W, "wordnet")
os.makedirs(wn, exist_ok=True)
gloss = 'having the same result however many times it is applied; "an idempotent apply changes nothing the second time"'
wr(wn + "/data.adj", "  1 license header\n")
off = os.path.getsize(wn + "/data.adj")
open(wn + "/data.adj", "a").write("%08d 00 a 01 idempotent 0 000 | %s\n" % (off, gloss))
wr(wn + "/index.adj", "idempotent a 1 0 1 0 %08d\n" % off)
for n in ("noun", "verb", "adv"):
    wr(wn + "/index." + n, "  1 header\n")
    wr(wn + "/data." + n, "  1 header\n")
llm = wr(os.path.join(W, "fake-llm"), "#!/usr/bin/env python3\nimport sys\nt = sys.argv[-1].split('<<<')[1].split('>>>')[0].strip()\nprint(t.replace('Their going', \"They're going\").replace('the the', 'the'))\n", 0o755)
case("dict-word", "dict", "idempotent", 0, env={"WNSEARCHDIR": wn, "DOTS_LLM": llm}, prefix="d:")
case("dict-grammar", "dict", "Their going to restart the the node tonight.", 0,
     steps=[{"op": "activate", "row": 0, "action": 0}], env={"WNSEARCHDIR": wn, "DOTS_LLM": llm}, prefix="d:")
case("dict-error", "dict", "idempotent", 0, env={"WNSEARCHDIR": os.path.join(W, "nowordnet"), "HOME": os.path.join(W, "emptyhome")}, prefix="d:")

# ---- fonts ---------------------------------------------------------------------------------
fc = wr(os.path.join(W, "fake-fc"), "#!/bin/sh\nprintf 'JetBrains Mono:spacing=100\\nBricolage Grotesque:\\nDejaVu Sans Mono:spacing=100\\nDejaVu Serif:\\n'\n", 0o755)
case("fonts-font", "fonts", "mono", 0, env={"DOTS_FC_LIST": fc}, prefix="t:", steps=[{"op": "select", "key": "font:JetBrains Mono"}])
case("fonts-sans", "fonts", "bric", 0, env={"DOTS_FC_LIST": fc}, prefix="t:")
case("fonts-icon", "fonts", "terminal", 0, env={"DOTS_FC_LIST": fc}, prefix="t:")

# ---- windows -------------------------------------------------------------------------------
def client(addr, cls, title, ws, fh, name=None):
    return {"address": addr, "class": cls, "title": title, "workspace": {"id": ws, "name": name or str(ws)}, "focusHistoryID": fh, "mapped": True}


CLIENTS = [client("0x08", "thunderbird", "Inbox", 6, 0), client("0x02", "code", "router.go (api-service)", 1, 1),
           client("0x01", "foot", "herdr: api-service", 2, 2), client("0x09", "code", "ingress.yaml", 1, 3),
           client("0x03", "zen-beta", "Ingress change: design doc", 3, 4), client("0x04", "zen-beta", "Build dashboard", 5, 5),
           client("0x05", "mpv", "Focus mix", -98, 6, "special:scratch"), client("0x06", "notes", "Capacity notes", 6, 7),
           client("0x07", "foot", "herdr: infra", 4, 8)]
PANES = {"panes": [
    {"pane_id": "w1:p1", "tab_id": "w1:t1", "agent": "claude", "agent_status": "idle", "terminal_title_stripped": "refactor-x", "tokens": {"ticket": "HD 4412"}},
    {"pane_id": "w1:p2", "tab_id": "w1:t2", "agent_status": "working", "terminal_title_stripped": "tests: watch api"},
    {"pane_id": "w1:p3", "tab_id": "w1:t3", "agent_status": "unknown", "terminal_title_stripped": "shell: ~/src/api-service"},
    {"pane_id": "w1:p4", "tab_id": "w1:t4", "agent_status": "unknown", "terminal_title_stripped": "logs: tail api"}]}
wcfg = save_json(os.path.join(W, "win", "w.json"), {"profiles": {"Dev": [1, 2, 3], "Ops": [4, 5], "Admin": [6, -98]}, "deny": ["thunderbird"], "terminals": ["foot"]})
save_json(os.path.join(W, "win", "clients.json"), CLIENTS)
save_json(os.path.join(W, "win", "one.json"), CLIENTS[1:2])
save_json(os.path.join(W, "win", "after.json"), [c for c in CLIENTS if c["address"] != "0x09"])
save_json(os.path.join(W, "win", "panes.json"), PANES)
wenv = {"DOTS_HYPR_CLIENTS": W + "/win/clients.json", "DOTS_WINDOWS_CONF": W + "/win/w.json", "DOTS_HERDR_PANES": W + "/win/panes.json", "DOTS_AUDIO_ADDRS": "0x05"}
for tag, q, extra in [("recent", "", {}), ("typed", "ing", {}), ("panes", "refac", {}), ("task", "HD 4412", {}), ("empty", "kubecfg", {})]:
    case("windows-" + tag, "windows", q, 0, env=wenv, prefix="w:")
case("windows-focus", "windows", "", 0, env=wenv, prefix="w:", props={"focusProfile": "Dev"})
case("windows-privacy", "windows", "", 0, env=wenv, prefix="w:", props={"masked": True})
case("windows-single", "windows", "", 0, env=dict(wenv, DOTS_HYPR_CLIENTS=W + "/win/one.json"), prefix="w:")
case("windows-error", "windows", "", 1, env=wenv, prefix="w:", steps=[{"op": "select", "key": "0x09"}, {"op": "activate", "key": "0x09", "action": 0}],
     files={"pre_windows": 'if [ "$1" = act ]; then touch "$DOTS_LAUNCHER_STATE.acted"; fi; if [ -e "$DOTS_LAUNCHER_STATE.acted" ]; then export DOTS_HYPR_CLIENTS=%s/win/after.json; fi' % W})
case("windows-salah", "windows", "", 0, env=wenv, prefix="w:", closed={"title": "Salah lock is active", "detail": "The window list stays closed. Focus changes go through the lock panel until the lock ends.", "button": "Open lock panel"})

# ---- snippets ------------------------------------------------------------------------------
def snippets(tag_dir, pinned=("rd", "rs", "tl", "pd", "su", "ml")):
    SN = [("rd", "restart a deployment", "command", "kubectl rollout restart deploy/{name} -n {namespace}", ["k8s"], {}),
          ("rs", "rollout status", "command", "kubectl rollout status deploy/{name} -n {namespace}", ["k8s"], {}),
          ("tl", "tail logs", "command", "kubectl logs -f deploy/{name} -n {namespace} --tail={lines}", ["k8s"], {}),
          ("pd", "polite decline", "reply", "Thanks for thinking of me. I can not take this on right now, but {when} could work if it is still open.", ["reply"],
           {"alt": {"shorter": "Thanks for thinking of me. I can not take this on right now."}}),
          ("su", "standup update", "block", "Update for {date}\nYesterday: {yesterday}\nToday: {today}\nBlockers: {blockers}", ["reply", "daily"], {}),
          ("ml", "meeting running late", "reply", "Running about {minutes} minutes late. Start without me and I will catch up.", ["reply"], {}),
          ("gc", "commit with ticket", "command", 'git commit -m "{ticket}: {message}"', ["git"], {}),
          ("gr", "reset a staged file", "command", "git restore --staged {file}", ["git"], {}),
          ("hc", "window manager config", "path", "~/.config/hypr/hyprland.lua", ["paths"], {})]
    for a, t, k, x, tags, extra in SN:
        save_json("%s/%s.json" % (tag_dir, a), dict(abbr=a, title=t, kind=k, text=x, tags=tags, pinned=a in pinned, **extra))
    return tag_dir


import time
sdir = snippets(os.path.join(W, "snips"))
usage = {"rd": {"n": 41, "last_used": time.time() - 7200, "values": {"name": "web", "namespace": "apps"}},
         "rs": {"n": 38, "last_used": time.time() - 7300, "values": {"name": "web", "namespace": "apps"}},
         "tl": {"n": 27, "last_used": time.time() - 90000, "values": {"name": "web", "lines": "100"}},
         "pd": {"n": 14, "last_used": time.time() - 3 * 86400, "values": {"when": "next week"}},
         "su": {"n": 52, "last_used": time.time() - 86400, "values": {"yesterday": "review fixes", "today": "docs pass", "blockers": "none"}},
         "ml": {"n": 9, "last_used": time.time() - 8 * 86400, "values": {"minutes": "10"}}}
BI = json.dumps({"date": "2026-11-03", "repo": "sample-app", "branch": "feature/login-fix", "clipboard": "kubectl get pods -A", "ticket": "TASK-1042"})
senv = {"DOTS_SNIPPETS_DIR": sdir, "DOTS_BUILTINS": BI}


def sn_case(tag, q="", sel=0, steps=None, env=None, **fr):
    d = case(tag, "snippets", q, sel, steps=steps, env=dict(senv, **(env or {})), prefix="s:", **fr)
    save_json(os.path.join(d, "state", "snippets.json"), usage)
    return d


sn_case("snippets-default")
sn_case("snippets-typing", "rs", 0)
sn_case("snippets-filling", "tl", 0, steps=[{"op": "fill", "row": 0, "name": "name", "value": "web"}], expand=True)
sn_case("snippets-copied", "tl", 0, steps=[{"op": "fill", "row": 0, "name": "name", "value": "web"}, {"op": "fill", "row": 0, "name": "namespace", "value": "apps"},
                                           {"op": "activate", "row": 0, "action": 0}])
d = sn_case("snippets-sent", "tl", 0, steps=[{"op": "fill", "row": 0, "name": "name", "value": "web"}, {"op": "fill", "row": 0, "name": "namespace", "value": "apps"},
                                             {"op": "activate", "row": 0, "action": 1}], env={"DOTS_HERDR_PANES": W + "/snippet-panes.json"})
save_json(W + "/snippet-panes.json", {"panes": [{"pane_id": "w1:p1", "focused": True}]})
case("snippets-empty", "snippets", "", 0, env={"DOTS_SNIPPETS_DIR": os.path.join(W, "empty-snips"), "DOTS_BUILTINS": BI}, prefix="s:")
sn_case("snippets-nomatch", "bring web back up")
sn_case("snippets-adding", "", 0, steps=[{"op": "beginAdd"}], env={"DOTS_BUILTINS": json.dumps({"clipboard": "kubectl get pods -A", "date": "2026-11-03"})})
TOK = "ghp_" + "a1B2c3D4e5" * 4
sn_case("snippets-sensitive", "", 0, steps=[{"op": "beginAdd"}], env={"DOTS_BUILTINS": json.dumps({"clipboard": "deploy with token = " + TOK, "date": "2026-11-03"})})
bad = os.path.join(W, "bad-snips")
wr(bad + "/broken.json", "{not json")
case("snippets-error", "snippets", "", 0, env={"DOTS_SNIPPETS_DIR": bad, "DOTS_BUILTINS": BI}, prefix="s:")

# ---- emoji ---------------------------------------------------------------------------------
eenv = {"DOTS_FC_CHARSET_MISSING": ""}
case("emoji-empty", "emoji", "", 0, env=eenv, prefix="e:", layout="grid")
d = case("emoji-browse", "emoji", "", 0, env=eenv, prefix="e:", layout="grid")
save_json(d + "/state/emoji.json", {"recent": [0x2713, 0x1F44D, 0x2192, 0x1F389, 0x2014, 0x1F680, 0x1F525, 0xB0, 0x20AC]})
case("emoji-search", "emoji", "ok", 0, env=eenv, prefix="e:", layout="grid")
case("emoji-tray", "emoji", "thumbs", 0, env=eenv, prefix="e:", layout="grid",
     steps=[{"op": "activate", "row": 0, "action": 2}, {"op": "query", "text": "party"}, {"op": "activate", "row": 0, "action": 2}, {"op": "query", "text": "rocket"}, {"op": "activate", "row": 0, "action": 2}])
case("emoji-copied", "emoji", "thumbs", 0, env=eenv, prefix="e:", layout="grid", steps=[{"op": "activate", "row": 0, "action": 0}])
case("emoji-nomatch", "emoji", "qqqqzzzz", 0, env=eenv, prefix="e:", layout="grid")
case("emoji-tofu", "emoji", "shaking face", 0, env={"DOTS_FC_CHARSET_MISSING": "1fae8"}, prefix="e:", layout="grid")

# ---- hosts ---------------------------------------------------------------------------------
cfg = ""
for a, user, host, port, via, key, tags in [
        ("db-02", "ops", "db-02.example.test", 22, "bastion-01", "id_ed25519_ops", "db prod"), ("web-01", "deploy", "web-01.example.test", 22, "", "id_ed25519_deploy", "web prod"),
        ("bastion-01", "ops", "bastion-01.example.test", 2222, "", "id_ed25519_ops", "jump"), ("build-01", "ci", "build-01.example.test", 22, "", "id_ed25519_ci", "ci dev"),
        ("nas-01", "admin", "nas-01.example.test", 22, "", "id_rsa_home", "storage home"), ("cache-01", "ops", "cache-01.example.test", 22, "bastion-01", "id_ed25519_ops", "cache dev"),
        ("db-01", "ops", "db-01.example.test", 22, "bastion-01", "id_ed25519_ops", "db dev"), ("lab-pi-01", "pi", "lab-pi-01.example.test", 22, "", "id_ed25519_lab", "lab")]:
    cfg += "# tags: %s\nHost %s\n  HostName %s\n  User %s\n  Port %d\n  IdentityFile ~/.ssh/%s\n%s\n" % (tags, a, host, user, port, key, ("  ProxyJump %s\n" % via) if via else "")
sshcfg = wr(W + "/ssh/config", cfg)
henv = {"DOTS_SSH_CONFIG": sshcfg}
hstate = {"db-02": {"last": time.time() - 240, "count": 12}, "web-01": {"last": time.time() - 7200, "count": 5}, "bastion-01": {"last": time.time() - 86400, "count": 3},
          "build-01": {"last": time.time() - 3 * 86400, "count": 2}, "nas-01": {"last": time.time() - 5 * 86400, "count": 1}}
for tag, q, fr in [("default", "", {}), ("filtered", "db", {}), ("actions", "", {"actionsOpen": True}), ("adhoc", "ops@lab-gw.example.test:2222", {})]:
    d = case("hosts-" + tag, "hosts", q, 0, env=henv, prefix="h:", **fr)
    save_json(d + "/state/hosts.json", hstate)
d = case("hosts-open", "hosts", "", 1, env=dict(henv, DOTS_HERDR_PANES=W + "/hosts-panes.json"), prefix="h:")
save_json(W + "/hosts-panes.json", {"panes": [{"pane_id": "w1:p1", "tab_id": "w1:t1", "terminal_title_stripped": "ssh web-01"}]})
save_json(d + "/state/hosts.json", hstate)
case("hosts-empty", "hosts", "", 0, env={"DOTS_SSH_CONFIG": W + "/ssh/none"}, prefix="h:")

# ---- kube ----------------------------------------------------------------------------------
FAKE = r'''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
D = os.environ["FAKE_KUBE_DIR"]
cur = open(D + "/cur").read().strip() if os.path.exists(D + "/cur") else "staging-a"
CTX = [("staging-a", "stg-east", "apps"), ("dev-sandbox", "dev-1", "default"), ("prod-main", "prd-east", "payments"), ("local-kind", "kind-local", "default"),
       ("staging-b", "stg-west", "apps"), ("prod-eu", "prd-eu", "payments"), ("lab-test", "lab-0", "default")]
if os.path.exists(D + "/empty"):
    print("{}")
elif a[:2] == ["config", "view"]:
    print(json.dumps({"current-context": cur, "clusters": [{"name": c, "cluster": {"server": "https://%s.example.test:6443" % c}} for _, c, _ in CTX],
                      "contexts": [{"name": n, "context": {"cluster": c, "user": "u", "namespace": ns}} for n, c, ns in CTX]}))
elif a[:2] == ["config", "use-context"]:
    open(D + "/cur", "w").write(a[2])
elif a[:2] == ["config", "set-context"]:
    pass
elif "namespaces" in a:
    print(json.dumps({"items": [{"metadata": {"name": n}} for n in ("apps", "default", "monitoring", "ingress", "kube-system")]}))
'''
fake = wr(W + "/fake-kubectl", FAKE, 0o755)


def kube_case(tag, q="", sel=0, steps=None, cur="staging-a", state=None, env=None, **fr):
    kd = os.path.join(W, "kube-" + tag)
    os.makedirs(kd, exist_ok=True)
    wr(kd + "/cur", cur)
    wr(kd + "/kc", "x")
    e = {"DOTS_KUBECTL": fake, "FAKE_KUBE_DIR": kd, "DOTS_KUBE_TIERS": W + "/none.json", "DOTS_KUBECONFIG_FILE": kd + "/kc",
         "DOTS_LAUNCH_EXEC_LOG": None, "DOTS_KUBE_CONFIRM": "all", "DOTS_HERDR_PANES": W + "/kube-panes.json"}
    e.update(env or {})
    d = case("kube-" + tag, "kube", q, sel, steps=steps, env=e, prefix="k:", **fr)
    st = {"last": {"dev-sandbox": time.time() - 720, "prod-main": time.time() - 2 * 86400, "local-kind": time.time() - 3 * 86400, "staging-b": time.time() - 5 * 86400,
                   "prod-eu": time.time() - 9 * 86400, "lab-test": time.time() - 21 * 86400},
          "nodes": {"staging-a": "6", "dev-sandbox": "3", "prod-main": "14", "local-kind": "1", "prod-eu": "9", "lab-test": "2"},
          "ns": {"staging-a": "apps"}, "unreach": ["staging-b"], "seen_mtime": os.path.getmtime(kd + "/kc")}
    st.update(state or {})
    save_json(d + "/state/kube.json", st)
    return d


save_json(W + "/kube-panes.json", {"panes": [{"pane_id": "w1:p1", "focused": True}]})
kube_case("default")
kube_case("changed", state={"seen_mtime": 1.0})
kube_case("filter", "stag")
kube_case("nomatch", "stagin-c")
kube_case("prod", "prod", 0)
kube_case("confirm", "prod", 0, steps=[{"op": "activate", "row": 0, "action": 0}])
kube_case("ns", "", 0, steps=[{"op": "activate", "row": 0, "action": 1}])
kube_case("switched", "dev", 0, steps=[{"op": "activate", "row": 0, "action": 0}, {"op": "query", "text": ""}], env={"DOTS_KUBE_CONFIRM": "prod"})
kube_case("peek", "prod", 0, steps=[{"op": "activate", "row": 0, "action": 2}], env={"DOTS_LAUNCH_EXEC_LOG": W + "/kube-peek.log"})
kube_case("onprod", "", 0, cur="prod-main", state={"prev": "staging-a", "prev_at": time.time()}, toast="now: prod-main")
kube_case("unreach", "", 4)
kube_case("mismatch", "", 0, props={"shellContext": "staging-a", "viewContext": "prod-eu"})
kube_case("nokube", "", 0)
kd = os.path.join(W, "kube-nokube")
wr(kd + "/empty", "1")
os.remove(kd + "/kc")
case_idle = case("kube-idle", "kube", "", 0, prefix="k:", env={"DOTS_KUBECTL": fake, "FAKE_KUBE_DIR": W + "/kube-default"},
                 closed={"title": "Kube mode is closed", "detail": "The lock screen shows no cluster or context names. The typed filter was cleared.", "button": ""})

json.dump(cases, open(os.path.join(W, "cases.json"), "w"), indent=1)
print(len(cases), "cases")
