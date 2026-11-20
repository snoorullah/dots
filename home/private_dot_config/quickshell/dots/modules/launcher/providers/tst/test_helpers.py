"""Tests for the launcher-mode helpers. Run: python3 -m unittest discover -s <this dir> -p 'test_*.py'"""
import json, os, stat, sys, time, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers_common import Env, load, helper_path


class Files(Env):
    ENV = ("DOTS_FILES_ROOT", "DOTS_FD")

    def setUp(self):
        super().setUp()
        self.m = load("files")
        os.environ["DOTS_FILES_ROOT"] = self.tmp
        os.environ.pop("DOTS_FD", None)
        self.write("docs/restore.md", "## Restore\n1. Stop writes.\n2. Run restore.\n")
        self.write("docs/restore-drill-notes.txt", "drill\n")
        self.write("pics/restore-drill.png", "\x89PNG\0\0")
        self.write(".ssh/restore_key", "SECRET")
        self.write("misc/other.bin", "\0\1\2")

    def test_ranks_basename_match_and_previews_text(self):
        o = self.m.query("restore")
        titles = [r["title"] for r in o["rows"]]
        self.assertEqual(titles[0], "docs/restore.md")
        self.assertIn("## Restore", o["rows"][0]["preview"]["body"])
        self.assertEqual(o["rows"][0]["icon"], "file-code")

    def test_image_row_carries_the_path_for_preview(self):
        r = [x for x in self.m.query("drill.png")["rows"]][0]
        self.assertEqual(r["icon"], "image")
        self.assertTrue(r["preview"]["image"].endswith("restore-drill.png"))

    def test_secret_dirs_never_listed(self):
        self.assertFalse([r for r in self.m.query("restore_key")["rows"]])

    def test_binary_has_no_text_preview(self):
        r = self.m.query("other.bin")["rows"][0]
        self.assertIn("No text preview", r["preview"]["body"])

    def test_empty_query_gives_a_hint_not_a_walk(self):
        o = self.m.query("  ")
        self.assertEqual(o["rows"], [])
        self.assertTrue(o["hint"])

    def test_missing_fd_is_an_error_row(self):
        os.environ["DOTS_FD"] = "/nonexistent/fd"
        self.assertIn("fd", self.m.query("x")["error"])

    def test_actions_run_argv_lists(self):
        p = os.path.join(self.tmp, "docs/restore.md")
        self.m.act("open", p)
        self.m.act("copy", p)
        self.assertEqual(self.logged(), [["xdg-open", p], ["wl-copy", p]])

    def test_send_to_agent_is_a_stub(self):
        self.assertIn("not wired", self.m.act("agent", "/x")["toast"])
        self.assertEqual(self.logged(), [])

    def test_cli_roundtrip(self):
        rc, o = self.run_cli("files", "query", "restore")
        self.assertEqual(rc, 0)
        self.assertTrue(o["rows"])


class Dict(Env):
    ENV = ("WNSEARCHDIR", "DOTS_LLM")

    def setUp(self):
        super().setUp()
        self.m = load("dict")
        d = os.path.join(self.tmp, "wn")
        os.makedirs(d)
        gloss = 'having the same result however many times it is applied; "an idempotent apply changes nothing the second time"'
        line = "00000001 00 a 02 idempotent 0 repeatable 0 000 | " + gloss + "\n"
        open(os.path.join(d, "data.adj"), "w").write("  1 license header\n")
        off = os.path.getsize(os.path.join(d, "data.adj"))
        open(os.path.join(d, "data.adj"), "a").write(line.replace("00000001", "%08d" % off))
        open(os.path.join(d, "index.adj"), "w").write("  1 header\nidempotent a 1 0 1 0 %08d\n" % off)
        for n in ("noun", "verb", "adv"):
            open(os.path.join(d, "index." + n), "w").write("  1 header\n")
            open(os.path.join(d, "data." + n), "w").write("  1 header\n")
        os.environ["WNSEARCHDIR"] = d
        fake = self.write("fake-llm", "#!/usr/bin/env python3\nimport sys\nsys.stdout.write(sys.argv[-1].split('<<<')[1].split('>>>')[0].strip().replace('Their going','They\\'re going').replace('the the','the'))\n", 0o755)
        os.environ["DOTS_LLM"] = fake
        self.fake = fake

    def test_word_lookup_gives_definition_and_example(self):
        o = self.m.query("idempotent")
        r = o["rows"][0]
        self.assertEqual((r["title"], r["sub"]), ("idempotent", "adjective"))
        self.assertIn("same result", r["preview"]["body"])
        self.assertIn("Used in: an idempotent apply", r["preview"]["body"])
        self.assertIn("Also: repeatable", r["preview"]["body"])
        self.assertEqual(o["rows"][-1]["key"], "grammar")

    def test_unknown_word_still_offers_grammar(self):
        o = self.m.query("zzzq")
        self.assertIn("No definition", o["hint"])
        self.assertEqual([r["key"] for r in o["rows"]], ["grammar"])

    def test_long_text_goes_straight_to_grammar(self):
        o = self.m.query("their going to restart the node")
        self.assertEqual([r["key"] for r in o["rows"]], ["grammar"])
        self.assertEqual(o["rows"][0]["actions"][0]["arg"], "their going to restart the node")

    def test_grammar_uses_local_llm_argv_and_counts_fixes(self):
        o = self.m.grammar("Their going to restart the the node tonight.")
        r = o["rows"][0]
        self.assertIn("They're going to restart the node tonight.", r["preview"]["body"])
        self.assertIn("2 fixes", r["title"])
        self.assertEqual(r["actions"][0]["verb"], "copy")

    def test_grammar_failure_is_an_error_not_a_crash(self):
        os.environ["DOTS_LLM"] = "/nonexistent/llm"
        self.assertIn("unavailable", self.m.grammar("some text here to check")["error"])

    def test_no_wordnet_is_named(self):
        os.environ["WNSEARCHDIR"] = "/nonexistent"
        o = self.m.query("idempotent")
        if not self.m.dict_dir():
            self.assertIn("wordnet", o["error"])

    def test_copy_is_wl_copy_argv(self):
        self.m.act("copy", "idempotent")
        self.assertEqual(self.logged(), [["wl-copy", "--sensitive", "idempotent"]])


class Fonts(Env):
    ENV = ("DOTS_FC_LIST", "DOTS_PHOSPHOR_QML")

    def setUp(self):
        super().setUp()
        self.m = load("fonts")
        fc = self.write("fake-fc", "#!/bin/sh\nprintf 'JetBrains Mono:spacing=100\\nBricolage Grotesque\\nDejaVu Serif,DejaVu Serif Condensed\\n'\n", 0o755)
        os.environ["DOTS_FC_LIST"] = fc
        q = self.write("Phos.qml", '  readonly property var table: ({\n    "terminal-window": [0x1, 0x2],\n    "arrow-right": [0x3, 0]\n  })\n')
        os.environ["DOTS_PHOSPHOR_QML"] = q

    def test_font_row_has_family_preview_and_css(self):
        r = self.m.query("mono")["rows"][0]
        self.assertEqual(r["title"], "JetBrains Mono")
        self.assertEqual(r["preview"]["font"], "JetBrains Mono")
        self.assertIn("font-family: 'JetBrains Mono', monospace;", [a["arg"] for a in r["actions"]])
        self.assertTrue([a for a in r["actions"] if a["label"] == "Install"][0]["disabled"])

    def test_icon_rows_come_from_the_registry(self):
        rows = self.m.query("terminal")["rows"]
        self.assertEqual(rows[0]["title"], "Icon: terminal-window")
        self.assertEqual(rows[0]["icon"], "terminal-window")

    def test_serif_fallback(self):
        r = self.m.query("dejavu")["rows"][0]
        self.assertIn("serif", [a["arg"] for a in r["actions"]][1])

    def test_empty_and_nomatch(self):
        self.assertTrue(self.m.query("")["hint"])
        self.assertEqual(self.m.query("zzzz")["rows"], [])


class Emoji(Env):
    ENV = ("DOTS_FC_CHARSET_MISSING",)

    def setUp(self):
        super().setUp()
        self.m = load("emoji")
        os.environ["DOTS_FC_CHARSET_MISSING"] = ""

    def test_name_and_keyword_search(self):
        self.assertEqual(self.m.query("thumbs")["rows"][0]["glyph"], "\U0001F44D")
        self.assertEqual(self.m.query("celebrate")["rows"][0]["glyph"], "\U0001F389")

    def test_alias_arrow(self):
        self.assertEqual(self.m.query("->")["rows"][0]["glyph"], "→")

    def test_type_is_refused_and_not_offered(self):
        r = self.m.act("type", "\U0001F44D")
        self.assertIn("error", r)
        self.assertEqual(self.logged(), [])
        labels = [a["label"] for a in self.m.query("thumbs")["rows"][0]["actions"]]
        self.assertNotIn("Type", labels)
        self.assertFalse(hasattr(self.m, "has_wtype"))

    def test_copy_logs_argv_and_remembers(self):
        self.m.act("copy", "\U0001F44D")
        self.assertEqual(self.logged(), [["wl-copy", "\U0001F44D"]])
        rows = self.m.query("")["rows"]
        self.assertEqual(rows[0]["glyph"], "\U0001F44D")
        self.assertEqual(rows[0]["group"], "Recent")

    def test_empty_query_browses_grouped_when_no_recents(self):
        groups = [r["group"] for r in self.m.query("")["rows"] if r.get("group")]
        self.assertIn("Arrows", groups)

    def test_tofu_is_flagged(self):
        os.environ["DOTS_FC_CHARSET_MISSING"] = "1fae8"
        r = self.m.row({"cp": 0x1FAE8, "name": "shaking face", "cat": "Emoji"})
        self.assertTrue(r["tofu"])
        self.assertIn("box", r["preview"]["body"])

    def test_copy_code_action(self):
        r = self.m.query("thumbs")["rows"][0]
        self.assertIn("U+1F44D", [a["arg"] for a in r["actions"]])

    def test_no_match_hint(self):
        self.assertIn("No glyph", self.m.query("qqqqzzzz")["hint"])


class Hosts(Env):
    ENV = ("DOTS_SSH_CONFIG",)

    def setUp(self):
        super().setUp()
        self.m = load("hosts")
        self.write("ssh/extra", "Host cache-01\n  HostName cache-01.example.test\n")
        cfg = ("# tags: db prod\nHost db-02\n  HostName db-02.example.test\n  User ops\n  ProxyJump bastion-01\n  IdentityFile ~/.ssh/id_ops\n\n"
               "Host bastion-01\n  HostName bastion-01.example.test\n  Port 2222\n\nHost *.internal *\n  User dflt\n\nHost web-?? \n  User x\n"
               "Include extra\n")
        os.environ["DOTS_SSH_CONFIG"] = self.write("ssh/config", cfg)

    def test_entries_tags_via_and_no_wildcards(self):
        rows = {r["key"]: r for r in self.m.query("")["rows"]}
        self.assertEqual(set(rows), {"db-02", "bastion-01", "cache-01"})
        self.assertEqual(rows["db-02"]["sub"], "ops@db-02.example.test:22 · via bastion-01")
        self.assertIn({"t": "prod", "tone": "warn"}, rows["db-02"]["chips"])
        self.assertEqual(rows["bastion-01"]["sub"], "dflt@bastion-01.example.test:2222")

    def test_alias_ranks_above_hostname(self):
        self.write("ssh/config", "Host zeta\n  HostName db.example.test\nHost db-01\n  HostName a.example.test\n")
        keys = [r["key"] for r in self.m.query("db")["rows"]]
        self.assertEqual(keys, ["db-01", "zeta"])

    def test_adhoc_connect_row(self):
        o = self.m.query("ops@lab-gw.example.test:2222")
        self.assertEqual(o["rows"][0]["actions"][0]["label"], "Connect")
        self.assertEqual(o["rows"][0]["group"], "Connect")

    def test_plain_words_are_not_adhoc(self):
        self.assertEqual(self.m.query("bring web back up")["rows"], [])

    def test_no_config_is_the_empty_state(self):
        os.environ["DOTS_SSH_CONFIG"] = os.path.join(self.tmp, "none")
        o = self.m.query("")
        self.assertEqual(o["rows"], [])
        self.assertIn("No hosts", o["hint"])

    def test_unreadable_config_is_an_error(self):
        os.environ["DOTS_SSH_CONFIG"] = self.tmp  # a directory
        self.assertIn("error", self.m.query(""))

    def test_connect_splits_the_focused_pane_and_runs_ssh_argv(self):
        pl = self.write("panes.json", json.dumps({"panes": [{"pane_id": "w1:p1", "focused": False}, {"pane_id": "w1:p2", "focused": True}]}))
        os.environ["DOTS_HERDR_PANES"] = pl
        o = self.m.act("connect", "db-02")
        self.assertTrue(o["close"])
        self.assertEqual(self.logged(), [["herdr", "pane", "split", "w1:p2"], ["herdr", "pane", "run", "w1:p2", "ssh", "db-02"]])
        self.assertEqual(self.m.load_state()["db-02"]["count"], 1)

    def test_open_session_is_focused_not_duplicated(self):
        pl = self.write("panes.json", json.dumps({"panes": [{"pane_id": "w1:p1", "tab_id": "w1:t1", "terminal_title_stripped": "ssh db-02"}]}))
        os.environ["DOTS_HERDR_PANES"] = pl
        r = self.m.query("db-02")["rows"][0]
        self.assertEqual((r["open"], r["actions"][0]["label"], r["actions"][0]["verb"]), (1, "Focus", "focus"))
        self.m.act("focus", "db-02")
        self.assertEqual(self.logged(), [["herdr", "tab", "focus", "w1:t1"]])

    def test_option_injection_is_refused(self):
        for bad in ("-oProxyCommand=touch_x", "-F/etc/passwd", "a b", "x;y"):
            o = self.m.act("connect", bad)
            self.assertIn("error", o, bad)
        self.assertEqual(self.logged(), [])

    def test_forget_and_copy_use_argv(self):
        self.m.act("forget", "db-02")
        self.m.act("copy-ssh", "db-02")
        self.assertEqual(self.logged(), [["ssh-keygen", "-R", "db-02.example.test"], ["wl-copy", "ssh db-02"]])

    def test_nothing_probes_the_network(self):
        src = open(helper_path("hosts")).read()
        self.assertNotIn("socket", src)
        self.assertNotIn("ping", src)
        self.assertEqual(self.m.query("")["rows"][0]["reach"], "unk")


FAKE_KUBECTL = r'''#!/usr/bin/env python3
import json, sys, os
a = sys.argv[1:]
log = os.environ.get("FAKE_KUBECTL_LOG")
if log:
    open(log, "a").write(json.dumps(a) + "\n")
cur = open(os.environ["FAKE_KUBECTL_CUR"]).read().strip() if os.path.exists(os.environ.get("FAKE_KUBECTL_CUR", "/x")) else "stg-a"
if a[:3] == ["config", "view", "-o"]:
    names = ["stg-a", "dev-sandbox", "prod-main", "local-kind", "lab-test", "prod-eu"]
    ns = {"stg-a": "apps", "prod-main": "payments", "prod-eu": "payments"}
    print(json.dumps({"current-context": cur,
        "clusters": [{"name": "c-" + n, "cluster": {"server": "https://c-%s.example.test:6443" % n}} for n in names],
        "contexts": [{"name": n, "context": {"cluster": "c-" + n, "user": "u", **({"namespace": ns[n]} if n in ns else {})}} for n in names]}))
elif a[:2] == ["config", "use-context"]:
    open(os.environ["FAKE_KUBECTL_CUR"], "w").write(a[2])
elif "namespaces" in a:
    print(json.dumps({"items": [{"metadata": {"name": n}} for n in ("default", "apps", "ingress", "kube-system")]}))
elif "nodes" in a and "--no-headers" in a:
    print("n1 Ready\nn2 Ready\nn3 Ready")
'''


class Kube(Env):
    ENV = ("DOTS_KUBECTL", "DOTS_KUBE_TIERS", "FAKE_KUBECTL_CUR", "FAKE_KUBECTL_LOG", "DOTS_KUBE_CONFIRM", "DOTS_KUBECONFIG_FILE")

    def setUp(self):
        super().setUp()
        self.m = load("kube")
        fake = self.write("fake-kubectl", FAKE_KUBECTL, 0o755)
        self.kl = os.path.join(self.tmp, "kubectl.log")
        os.environ.update(DOTS_KUBECTL=fake, FAKE_KUBECTL_CUR=os.path.join(self.tmp, "cur"), FAKE_KUBECTL_LOG=self.kl,
                          DOTS_KUBE_TIERS=os.path.join(self.tmp, "none.json"))
        os.environ.pop("DOTS_KUBE_CONFIRM", None)
        self.write("kc", "x")
        os.environ["DOTS_KUBECONFIG_FILE"] = os.path.join(self.tmp, "kc")

    def klog(self):
        try:
            return [json.loads(x) for x in open(self.kl).read().splitlines()]
        except OSError:
            return []

    def test_tiers_are_inferred_and_unset_is_never_safe(self):
        rows = {r["key"]: r for r in self.m.query("")["rows"]}
        self.assertEqual([rows[k]["tierLabel"] for k in ("stg-a", "dev-sandbox", "prod-main", "local-kind", "lab-test")],
                         ["STAGING", "DEV", "PROD", "LOCAL", "TIER UNSET"])

    def test_current_first_and_prod_never_wins_a_tie(self):
        keys = [r["key"] for r in self.m.query("")["rows"]]
        self.assertEqual(keys[0], "stg-a")
        self.assertLess(keys.index("dev-sandbox"), keys.index("prod-main"))
        self.assertLess(keys.index("lab-test"), keys.index("prod-eu"))

    def test_tier_word_filters(self):
        self.assertEqual(sorted(r["key"] for r in self.m.query("prod")["rows"]), ["prod-eu", "prod-main"])

    def test_fuzzy_filter_and_highlight(self):
        r = self.m.query("stag")["rows"][0]
        self.assertEqual((r["key"], r["hl"]), ("stg-a", []))  # alias is stg-a: fuzzy on name+cluster+ns, no substring in alias
        r = self.m.query("sand")["rows"][0]
        self.assertEqual(r["hl"], [4, 5, 6, 7])

    def test_no_match_names_the_nearest(self):
        o = self.m.query("stagin-c")
        self.assertEqual(o["rows"], [])
        self.assertIn("Closest", o["hint"])

    def test_every_switch_asks_unless_set_to_prod_only(self):
        self.assertTrue(self.m.act("confirm", "stg-a")["confirm"])
        os.environ["DOTS_KUBE_CONFIRM"] = "prod"
        self.assertFalse(self.m.act("confirm", "dev-sandbox")["confirm"])
        c = self.m.act("confirm", "prod-main")
        self.assertTrue(c["confirm"] and c["spec"]["danger"])
        self.assertEqual(c["spec"]["alt"], {"label": "Peek instead (safer)", "verb": "peek", "arg": "prod-main"})
        self.assertIn("PROD", c["spec"]["title"])

    def test_use_context_is_a_kubectl_argv_and_undo_restores(self):
        o = self.m.act("use", "dev-sandbox")
        self.assertEqual(o["toast"], "now: dev-sandbox")
        self.assertEqual([x[1:] for x in self.logged()], [["config", "use-context", "dev-sandbox"]])
        o = self.m.act("undo", "dev-sandbox")
        self.assertIn("restored: stg-a", o["toast"])
        self.assertEqual(self.logged()[-1][-3:], ["config", "use-context", "stg-a"])

    def test_bad_names_never_reach_kubectl(self):
        for bad in ("--kubeconfig=/x", "a b", "-x", ""):
            self.assertIn("error", self.m.act("use", bad), bad)
        self.assertEqual(self.logged(), [])

    def test_namespaces_recent_first(self):
        self.m.act("set-ns", "stg-a/ingress")
        rows = self.m.namespaces("stg-a")["rows"]
        self.assertEqual(rows[0]["title"], "ingress")
        self.assertEqual(self.logged()[-1][-5:], ["config", "set-context", "stg-a", "--namespace", "ingress"])

    def test_peek_never_changes_the_global_context(self):
        pl = self.write("panes.json", json.dumps({"panes": [{"pane_id": "w1:p1", "focused": True}]}))
        os.environ["DOTS_HERDR_PANES"] = pl
        o = self.m.act("peek", "prod-main")
        self.assertIn("global stays stg-a", o["toast"])
        self.assertNotIn("use-context", json.dumps(self.logged()))
        self.assertEqual(self.logged()[-1][-6:], ["--context", "prod-main", "get", "nodes", "-o", "wide"][-6:])

    def test_probe_records_nodes_and_unreachable(self):
        self.m.act("probe", "stg-a")
        self.assertEqual(self.logged()[-1][-6:], ["--context", "stg-a", "get", "nodes", "--no-headers", "--request-timeout=3s"])
        self.assertIn("stg-a", self.m.load_state()["nodes"])  # exec is logged, not run, so the empty answer counts 0 nodes

    def test_tiers_file_overrides(self):
        self.write("tiers.json", json.dumps({"contexts": {"lab-test": "dev"}, "aliases": {"lab-test": "Lab"}}))
        os.environ["DOTS_KUBE_TIERS"] = os.path.join(self.tmp, "tiers.json")
        r = {x["key"]: x for x in self.m.query("")["rows"]}["lab-test"]
        self.assertEqual((r["tierLabel"], r["title"]), ("DEV", "Lab"))

    def test_no_kubeconfig_state(self):
        os.environ["DOTS_KUBECTL"] = self.write("empty-kubectl", "#!/bin/sh\necho '{}'\n", 0o755)
        os.environ["DOTS_KUBECONFIG_FILE"] = os.path.join(self.tmp, "absent")
        o = self.m.query("")
        self.assertEqual((o["rows"], o["state"]), ([], "nokube"))
        self.assertIn("never creates", o["hint"])

    def test_missing_kubectl_is_named(self):
        os.environ["DOTS_KUBECTL"] = "/nonexistent/kubectl"
        self.assertIn("kubectl", self.m.query("")["error"])

    def test_read_only_verbs_only(self):
        src = open(helper_path("kube")).read()
        for forbidden in ('"delete"', '"apply"', '"exec"', '"edit"', '"patch"', '"scale"', '"drain"'):
            self.assertNotIn(forbidden, src)


class Snippets(Env):
    ENV = ("DOTS_SNIPPETS_DIR", "DOTS_BUILTINS")

    def setUp(self):
        super().setUp()
        self.m = load("snippets")
        self.dir = os.path.join(self.tmp, "snips")
        os.environ["DOTS_SNIPPETS_DIR"] = self.dir
        os.environ["DOTS_BUILTINS"] = json.dumps({"date": "2026-11-03", "repo": "sample-app", "branch": "main", "clipboard": "", "ticket": ""})
        for abbr, title, kind, text, extra in [
            ("rd", "restart a deployment", "command", "kubectl rollout restart deploy/{name} -n {namespace}", {}),
            ("rs", "rollout status", "command", "kubectl rollout status deploy/{name} -n {namespace}", {}),
            ("tl", "tail logs", "command", "kubectl logs -f deploy/{name} -n {namespace} --tail={lines}", {}),
            ("su", "standup update", "block", "Update for {date}\nYesterday: {yesterday}", {"pinned": True}),
            ("ml", "meeting running late", "reply", "Running about {minutes} minutes late.", {"alt": {"shorter": "Running {minutes} min late."}}),
            ("hc", "window manager config", "path", "~/.config/hypr/hyprland.lua", {}),
        ]:
            self.write("snips/%s.json" % abbr, json.dumps(dict(abbr=abbr, title=title, kind=kind, text=text, tags=["k8s"] if kind == "command" else [], **extra)))
        self.m.save_usage({"rd": {"n": 41, "last_used": time.time() - 7200, "values": {"name": "web", "namespace": "apps"}},
                           "tl": {"n": 27, "last_used": time.time() - 90000, "values": {"name": "web", "lines": "100"}}})

    def test_default_shows_pinned_never_blank(self):
        o = self.m.query("")
        self.assertEqual(o["rows"][0]["group"], "Pinned")
        self.assertEqual([r["key"] for r in o["rows"]], ["su"])

    def test_default_without_pins_is_last_used_first(self):
        os.remove(os.path.join(self.dir, "su.json"))
        keys = [r["key"] for r in self.m.query("")["rows"]]
        self.assertEqual(keys[:2], ["rd", "tl"])

    def test_exact_abbreviation_first_then_frequency(self):
        keys = [r["key"] for r in self.m.query("rs")["rows"]]
        self.assertEqual(keys[0], "rs")
        o = self.m.query("rollout")
        self.assertEqual(o["rows"][0]["key"], "rs") if False else self.assertIn("rd", [r["key"] for r in o["rows"]])

    def test_fuzzy_highlight_indexes(self):
        r = self.m.query("rad")["rows"][0]
        self.assertEqual(r["key"], "rd")
        self.assertEqual(len(r["hl"]), 3)

    def test_blank_states_filled_ghost_empty_builtin(self):
        r = self.m.render("tl", {"name": "api"})["row"]
        st = {f["name"]: (f["state"], f["value"]) for f in r["preview"]["fields"]}
        self.assertEqual(st["name"], ("filled", "api"))
        self.assertEqual(st["lines"], ("ghost", "100"))
        self.assertEqual(st["namespace"], ("empty", ""))
        self.assertEqual(r["needs"], ["namespace"])
        self.assertTrue(r["actions"][0]["disabled"])
        self.assertIn("{namespace}", r["preview"]["body"])

    def test_builtin_blank_is_filled_for_you(self):
        r = self.m.render("su", {"yesterday": "tests"})["row"]
        self.assertIn("Update for 2026-11-03", r["preview"]["body"])
        self.assertEqual(r["needs"], [])

    def test_copy_refused_until_filled(self):
        o = self.m.act("copy", "tl", {"name": "web"})
        self.assertIn("namespace", o["error"])
        self.assertEqual(self.logged(), [])

    def test_copy_logs_text_updates_usage_and_remembers_values(self):
        o = self.m.act("copy", "tl", {"name": "web", "namespace": "apps"})
        self.assertTrue(o["close"])
        self.assertEqual(self.logged(), [["wl-copy", "kubectl logs -f deploy/web -n apps --tail=100"]])
        u = self.m.load_usage()["tl"]
        self.assertEqual((u["n"], u["values"]["namespace"]), (28, "apps"))
        self.assertNotIn("date", u["values"])

    def test_secret_like_snippet_copies_with_sensitive_hint(self):
        self.write("snips/sk.json", json.dumps({"abbr": "sk", "title": "key", "kind": "reply", "text": "token ghp_" + "a" * 36, "tags": [], "pinned": False}))
        self.m.act("copy", "sk", {})
        self.assertEqual(self.logged()[-1][:2], ["wl-copy", "--sensitive"])

    def test_pane_types_without_enter_and_only_for_commands(self):
        pl = self.write("panes.json", json.dumps({"panes": [{"pane_id": "w1:p1", "focused": True}]}))
        os.environ["DOTS_HERDR_PANES"] = pl
        self.m.act("pane", "rd", {"name": "web", "namespace": "apps"})
        self.assertEqual(self.logged(), [["herdr", "pane", "send-text", "w1:p1", "kubectl rollout restart deploy/web -n apps"]])
        self.assertIn("error", self.m.act("pane", "su", {"yesterday": "x"}))

    def test_alt_versions_become_actions(self):
        r = self.m.render("ml", {"minutes": "10"})["row"]
        self.assertIn("Copy shorter version", [a["label"] for a in r["actions"]])
        self.m.act("copy-alt-shorter", "ml", {"minutes": "10"})
        self.assertEqual(self.logged()[-1], ["wl-copy", "Running 10 min late."])

    def test_empty_store(self):
        os.environ["DOTS_SNIPPETS_DIR"] = os.path.join(self.tmp, "empty")
        o = self.m.query("")
        self.assertEqual(o["rows"][0]["key"], "new")
        self.assertIn("No snippets", o["hint"])

    def test_nomatch_offers_closest_and_save_hint(self):
        o = self.m.query("restart the web deployment please")
        self.assertIn("Ctrl+N", o["hint"])
        self.assertTrue(o["rows"][0]["title"].startswith("Closest existing snippet"))

    def test_unreadable_store_names_the_file(self):
        self.write("snips/bad.json", "{not json")
        o = self.m.query("")
        self.assertIn("bad.json", o["error"])

    def test_sensitive_text_is_refused_then_forced(self):
        tok = "ghp_" + "a1B2c3D4e5" * 4
        o = self.m.add("tk", "block", "token", "use " + tok, False)
        self.assertTrue(o["sensitive"])
        self.assertFalse(os.path.exists(os.path.join(self.dir, "tk.json")))
        self.assertNotIn(tok, json.dumps(o))
        o = self.m.add("tk", "block", "token", "use " + tok, True)
        self.assertEqual(o["saved"], "tk")
        self.assertTrue(os.path.exists(os.path.join(self.dir, "tk.json")))

    def test_add_validates_abbr_and_kind(self):
        self.assertIn("error", self.m.add("../x", "block", "t", "x", False))
        self.assertIn("error", self.m.add("ok", "weird", "t", "x", False))
        self.assertIn("error", self.m.add("ok", "block", "t", "  ", False))

    def test_draft_from_clipboard_guesses_kind_and_flags_secrets(self):
        os.environ["DOTS_BUILTINS"] = json.dumps({"clipboard": "kubectl get pods -A"})
        self.assertEqual(self.m.draft()["draft"]["kind"], "command")
        os.environ["DOTS_BUILTINS"] = json.dumps({"clipboard": "password = hunter2hunter2"})
        d = self.m.draft()["draft"]
        self.assertTrue(d["sensitive"])
        self.assertEqual(d["text"], "")


CLIENTS = [
    {"address": "0x08", "class": "thunderbird", "title": "Inbox (3) secret subject", "workspace": {"id": 6, "name": "6"}, "focusHistoryID": 0, "mapped": True},
    {"address": "0x02", "class": "code", "title": "router.go (api-service)", "workspace": {"id": 1, "name": "1"}, "focusHistoryID": 1, "mapped": True},
    {"address": "0x01", "class": "foot", "title": "herdr: api-service", "workspace": {"id": 2, "name": "2"}, "focusHistoryID": 2, "mapped": True},
    {"address": "0x09", "class": "code", "title": "ingress.yaml", "workspace": {"id": 1, "name": "1"}, "focusHistoryID": 3, "mapped": True},
    {"address": "0x03", "class": "zen-beta", "title": "Ingress change: design doc", "workspace": {"id": 3, "name": "3"}, "focusHistoryID": 4, "mapped": True},
    {"address": "0x07", "class": "foot", "title": "ssh db-02", "workspace": {"id": 4, "name": "4"}, "focusHistoryID": 5, "mapped": True},
    {"address": "0x05", "class": "mpv", "title": "Focus mix", "workspace": {"id": 99, "name": "special:scratch"}, "focusHistoryID": 6, "mapped": True},
    {"address": "0x0a", "class": "foot", "title": "gone", "workspace": {"id": 1, "name": "1"}, "focusHistoryID": 7, "mapped": False},
]
PANES = {"panes": [
    {"pane_id": "w1:p1", "tab_id": "w1:t1", "agent": "claude", "agent_status": "idle", "terminal_title_stripped": "refactor-x", "tokens": {"ticket": "HD 4412"}},
    {"pane_id": "w1:p2", "tab_id": "w1:t2", "agent_status": "unknown", "cwd": "/x/api-service", "terminal_title_stripped": "tests: watch api"},
]}


class Windows(Env):
    ENV = ("DOTS_HYPR_CLIENTS", "DOTS_WINDOWS_CONF", "DOTS_AUDIO_ADDRS")

    def setUp(self):
        super().setUp()
        self.m = load("windows")
        os.environ["DOTS_HYPR_CLIENTS"] = self.write("clients.json", json.dumps(CLIENTS))
        os.environ["DOTS_HERDR_PANES"] = self.write("panes.json", json.dumps(PANES))
        os.environ["DOTS_WINDOWS_CONF"] = self.write("w.json", json.dumps({"profiles": {"Dev": [1, 2, 3], "Ops": [4, 5], "Admin": [6, 99]}}))
        os.environ["DOTS_AUDIO_ADDRS"] = "0x05"

    def keys(self, o):
        return [r["key"] for r in o["rows"]]

    def test_recent_groups_by_profile_excludes_current_and_hidden(self):
        o = self.m.query("", False, "")
        self.assertNotIn("0x08", self.keys(o))
        self.assertNotIn("0x0a", self.keys(o))
        self.assertEqual([r["group"] for r in o["rows"] if r.get("group")], ["DEV", "OPS", "ADMIN"])
        self.assertIn("Enter = back to router.go", o["hint"])

    def test_focus_mode_dims_other_profiles_and_says_so(self):
        o = self.m.query("", False, "Dev")
        self.assertEqual(o["banner"]["title"], "Focus mode: Dev profile")
        self.assertEqual({r["profile"]: r["dim"] for r in o["rows"]}, {"Dev": False, "Ops": True, "Admin": True})

    def test_privacy_masks_titles_to_app_names(self):
        o = self.m.query("", True, "")
        self.assertEqual(o["banner"]["title"], "Titles masked")
        titles = [r["title"] for r in o["rows"]]
        self.assertNotIn("router.go (api-service)", titles)
        self.assertIn("Code", titles)
        self.assertNotIn("api-service", json.dumps(o))

    def test_denied_app_is_masked_even_when_not_sharing(self):
        os.environ["DOTS_WINDOWS_CONF"] = self.write("w2.json", json.dumps({"profiles": {"Admin": [6]}, "deny": ["code"]}))
        o = self.m.query("", False, "")
        self.assertNotIn("router.go", json.dumps(o))
        self.assertNotIn("ingress.yaml", json.dumps(o))

    def test_fuzzy_title_with_highlight(self):
        o = self.m.query("ing", False, "")
        self.assertEqual(self.keys(o)[0], "0x09")  # ingress.yaml (prefix) beats the doc title
        self.assertEqual(o["rows"][0]["hl"], [0, 1, 2])

    def test_filters_profile_workspace_agent_audio(self):
        self.assertEqual(set(self.keys(self.m.query("p:ops", False, ""))), {"0x07"})
        self.assertEqual(set(self.keys(self.m.query("@3", False, ""))), {"0x03"})
        self.assertEqual(self.keys(self.m.query("!agent", False, "")), ["0x01"])
        self.assertEqual(self.keys(self.m.query("!audio", False, "")), ["0x05"])

    def test_pane_hit_expands_the_window_and_preselects(self):
        o = self.m.query("refac", False, "")
        self.assertEqual(self.keys(o), ["0x01", "0x01#0", "0x01#1"])
        self.assertTrue(o["rows"][1]["preselect"])
        self.assertEqual(o["rows"][1]["indent"], 1)
        self.assertIn("pane: agent: refactor-x", o["rows"][0]["sub"])

    def test_agent_state_comes_from_herdr(self):
        r = self.m.query("", False, "")["rows"]
        w = [x for x in r if x["key"] == "0x01"][0]
        self.assertEqual([c["t"] for c in w["chips"]], ["agent waiting", "2 panes"])
        self.assertEqual(w["preview"]["panes"][0]["st"], "waiting")

    def test_task_set_banner_when_two_windows_share_a_task(self):
        PANES2 = dict(PANES)
        os.environ["DOTS_HERDR_PANES"] = self.write("p2.json", json.dumps(PANES2))
        o = self.m.query("HD 4412", False, "")
        self.assertEqual(self.keys(o)[0], "0x01")  # one window only: no set banner
        self.assertNotIn("banner", o)

    def test_empty_result_hint(self):
        o = self.m.query("kubecfg", False, "")
        self.assertEqual(o["rows"], [])
        self.assertIn("Enter opens apps", o["hint"])

    def test_single_window(self):
        os.environ["DOTS_HYPR_CLIENTS"] = self.write("one.json", json.dumps(CLIENTS[1:2]))
        o = self.m.query("", False, "")
        self.assertEqual(len(o["rows"]), 1)
        self.assertEqual(o["banner"]["title"], "This is the only window")

    def test_hyprland_down_is_an_error(self):
        os.environ["DOTS_HYPR_CLIENTS"] = os.path.join(self.tmp, "none.json")
        self.assertIn("error", self.m.query("", False, ""))

    def test_focus_is_one_lua_dispatch_argv(self):
        o = self.m.act("focus", "0x02", [])
        self.assertTrue(o["close"])
        self.assertEqual(self.logged(), [["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0x02" })']])

    def test_stale_window_gives_banner_and_refresh_not_a_dispatch(self):
        o = self.m.act("focus", "0xdead", [])
        self.assertEqual(o["banner"]["title"], "Could not focus that window")
        self.assertTrue(o["refresh"])
        self.assertEqual(self.logged(), [])

    def test_bad_address_never_dispatches(self):
        for bad in ('0x1" }) hl.dsp.exit({ x = "', "not-an-address", ""):
            self.assertIn("error", self.m.act("focus", bad, []))
        self.assertEqual(self.logged(), [])

    def test_close_and_move_here(self):
        self.m.act("close", "0x03", [])
        self.m.act("move-here", "0x03", [])
        self.assertEqual(self.logged()[0][2], 'hl.dsp.window.close({ window = "address:0x03" })')
        self.assertEqual(self.logged()[1][2], 'hl.dsp.window.move({ workspace = "3", window = "address:0x03" })')

    def test_focus_pane_focuses_the_herdr_tab_then_the_window(self):
        self.m.act("focus-pane", "0x01 w1:t2", [])
        self.assertEqual(self.logged(), [["herdr", "tab", "focus", "w1:t2"], ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0x01" })']])

    def test_cli_masks(self):
        rc, o = self.run_cli("windows", "query", "--mask", "")
        self.assertEqual(rc, 0)
        self.assertEqual(o["banner"]["title"], "Titles masked")


class Rules(unittest.TestCase):
    MODES = ("files", "dict", "fonts", "emoji", "hosts", "kube", "snippets", "windows")

    def test_no_shell_strings_and_no_network(self):
        import re
        for m in self.MODES:
            src = open(helper_path(m)).read()
            self.assertNotRegex(src, r"shell\s*=\s*True", m)
            self.assertNotRegex(src, r"os\.system|os\.popen", m)
            self.assertNotRegex(src, r"\b(urllib|requests|http\.client|socket)\b", m)
            self.assertTrue(src.startswith("#!/usr/bin/env python3"), m)

    def test_public_repo_no_private_names(self):
        import re
        for m in self.MODES:
            src = open(helper_path(m)).read()
            self.assertNotRegex(src, r"(?i)pnow|proficient|kaarbaaz|websleak|snoorullah|ovh", m)
            self.assertNotRegex(src, r"(^|[^0-9.])(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+", m)


if __name__ == "__main__":
    unittest.main()
