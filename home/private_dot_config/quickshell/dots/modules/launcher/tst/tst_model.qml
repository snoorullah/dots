import QtQuick
import QtTest
import "../js/Model.js" as M

TestCase {
  name: "LauncherModel"

  readonly property var provs: [
    { providerId: "all", prefix: "" }, { providerId: "clip", prefix: "c:" }, { providerId: "cmd", prefix: ">" },
    { providerId: "math", prefix: "=" }, { providerId: "dict", prefix: "d:" }
  ]

  function test_prefix() {
    compare(M.matchPrefix("c:foo", provs).pid, "clip");
    compare(M.matchPrefix("c:foo", provs).rest, "foo");
    compare(M.matchPrefix(">k8s", provs).rest, "k8s");
    compare(M.matchPrefix("=1+1", provs).pid, "math");
    compare(M.matchPrefix("c", provs), null);
    compare(M.matchPrefix("cat", provs), null);
    compare(M.matchPrefix("", provs), null);
  }

  function test_cycle() {
    var ids = ["all", "clip", "cmd"];
    compare(M.cycle(ids, "all", 1), "clip");
    compare(M.cycle(ids, "cmd", 1), "all");
    compare(M.cycle(ids, "all", -1), "cmd");
    compare(M.cycle([], "all", 1), "all");
  }

  function test_rank_limit_weight_recent() {
    var now = 1000000, g = [
      { pid: "apps", weight: 1.0, limit: 2, rows: [{ key: "a1", score: 0.9 }, { key: "a2", score: 0.8 }, { key: "a3", score: 0.99 }] },
      { pid: "cmd", weight: 1.2, limit: 3, rows: [{ key: "c1", score: 0.7 }] },
      { pid: "math", weight: 1.0, limit: 1, rows: [{ key: "m" }] }
    ];
    var r = M.rankAll(g, {}, now);
    compare(r.length, 4);                       // a3 cut by the limit of 2
    compare(r[0].key, "a1");                    // 0.9
    compare(r[1].key, "c1");                    // 0.7 * 1.2 = .84 beats a2 .8
  }

  function test_rank_order_details() {
    var now = 1000000, g = [
      { pid: "apps", weight: 1.0, limit: 2, rows: [{ key: "a1", score: 0.9 }, { key: "a2", score: 0.5 }] },
      { pid: "cmd", weight: 1.2, limit: 3, rows: [{ key: "c1", score: 0.7 }] },
      { pid: "math", weight: 1.0, limit: 1, rows: [{ key: "m" }] }
    ];
    var r = M.rankAll(g, {}, now);
    compare(r.map(function (x) { return x.key; }).join(","), "a1,c1,a2,m");   // .9 .84 .5 .5 (stable)
    var rec = {}; rec["math\u0000m"] = now - 3600;
    r = M.rankAll(g, rec, now);
    compare(r.map(function (x) { return x.key; }).join(","), "a1,c1,m,a2");   // m .5 + .2 = .7 passes a2 .5, not c1 .84
  }

  function test_rank_recent_boost() {
    var now = 1000000, rec = {};
    rec["p\u0000b"] = now - 86400; rec["p\u0000c"] = now - 8 * 86400;
    var r = M.rankAll([{ pid: "p", weight: 1, limit: 5, rows: [{ key: "a", score: 0.6 }, { key: "b", score: 0.5 }, { key: "c", score: 0.55 }] }], rec, now);
    compare(r.map(function (x) { return x.key; }).join(","), "b,a,c");        // b .7; c's boost is stale
    compare(r[0]._p, "p"); compare(r[0]._i, 1); compare(r[0]._k, "b");
  }

  function test_rank_stable() {
    var r = M.rankAll([{ pid: "p", weight: 1, limit: 5, rows: [{ key: "x" }, { key: "y" }, { key: "z" }] }], {}, 0);
    compare(r.map(function (x) { return x.key; }).join(""), "xyz");
  }

  function test_recent_rows() {
    var rr = M.recentRows([{ p: "cmd", key: "k", title: "Pods", sub: "k8s", icon: "terminal-window", q: "pods" }]);
    compare(rr.length, 1); compare(rr[0]._p, "cmd"); compare(rr[0]._k, "k"); compare(rr[0]._q, "pods");
    compare(rr[0].actions[0].label, "Run again");
    var many = []; for (var i = 0; i < 20; i++) many.push({ p: "p", key: "k" + i, title: "t" });
    compare(M.recentRows(many).length, 8);
  }

  function test_reselect() {
    var rows = [{ key: "a" }, { key: "b" }, { key: "c" }];
    compare(M.reselect(rows, "c", 0), 2);
    compare(M.reselect(rows, "zz", 5), 2);
    compare(M.reselect(rows, "", 1), 1);
    compare(M.reselect([], "a", 3), 0);
  }

  function test_move_and_secondary() {
    compare(M.move(0, 3, -1), 0); compare(M.move(2, 3, 1), 2); compare(M.move(1, 3, 1), 2); compare(M.move(0, 0, 1), 0);
    compare(M.nextSecondary(0, 3, 1), 1); compare(M.nextSecondary(1, 3, 1), 2); compare(M.nextSecondary(2, 3, 1), 1);
    compare(M.nextSecondary(1, 3, -1), 2); compare(M.nextSecondary(0, 1, 1), 0); compare(M.nextSecondary(0, 3, -1), 2);
  }

  function test_escape() {
    compare(M.escapeStep({ confirm: true, query: "x" }), "confirm");
    compare(M.escapeStep({ confirm: false, query: "x" }), "clear");
    compare(M.escapeStep({ confirm: false, query: "" }), "close");
  }

  function test_route() {
    var st = { confirm: false, queryEmpty: false, modeIsAll: true, nActions: 3 };
    compare(M.route({ key: 0x01000001 }, st).t, "modeNext");
    compare(M.route({ key: 0x01000001, shift: true }, st).t, "modePrev");
    compare(M.route({ key: 0x01000002 }, st).t, "modePrev");
    compare(M.route({ key: 0x4e, ctrl: true }, st).d, 1);
    compare(M.route({ key: 0x50, ctrl: true }, st).d, -1);
    compare(M.route({ key: 0x01000015 }, st).d, 1);
    compare(M.route({ key: 0x01000013 }, st).d, -1);
    compare(M.route({ key: 0x01000004 }, st).a, 0);
    compare(M.route({ key: 0x01000005, ctrl: true }, st).t, "runSecondary");
    compare(M.route({ key: 0x33, ctrl: true }, st).a, 2);
    compare(M.route({ key: 0x4a, ctrl: true }, st).d, 1);
    compare(M.route({ key: 0x4b, ctrl: true }, st).d, -1);
    compare(M.route({ key: 0x01000000 }, st).t, "escape");
    compare(M.route({ key: 0x4e }, st), null);                  // plain n is typing
    compare(M.route({ key: 0x01000003 }, st), null);            // backspace with text: the field handles it
    compare(M.route({ key: 0x01000003 }, { confirm: false, queryEmpty: true, modeIsAll: false }).t, "backMode");
    compare(M.route({ key: 0x01000003 }, { confirm: false, queryEmpty: true, modeIsAll: true }), null);
  }

  function test_route_confirm() {
    var st = { confirm: true, queryEmpty: false, modeIsAll: true };
    compare(M.route({ key: 0x01000004 }, st).t, "confirm");
    compare(M.route({ key: 0x01000005, ctrl: true }, st).t, "confirm");
    compare(M.route({ key: 0x31, ctrl: true }, st), null);
    compare(M.route({ key: 0x01000000 }, st).t, "escape");
  }

  function test_status() {
    compare(M.statusLine("Copied", true, true, "h"), "Copied");
    compare(M.statusLine("", true, true, "h"), "Searching.");
    compare(M.statusLine("", false, true, "No history"), "No history");
    compare(M.statusLine("", false, false, "No history"), "Type a prefix, or press Tab to change mode.");
  }

  function test_fuzzy() {
    compare(M.fuzzy("fire", "Firefox"), 0.9);
    compare(M.fuzzy("fox", "Firefox"), 0.75);
    compare(M.fuzzy("firefox", "firefox"), 1);
    compare(M.fuzzy("ffx", "Firefox") > 0.3, true);
    compare(M.fuzzy("zzz", "Firefox"), 0);
    compare(M.fuzzy("", "x"), 0.5);
  }

  function test_helpers() {
    compare(M.maxOf(1, 3, 2), 3);
    compare(M.centred(1000, 400), 300);
    compare(M.centred(100, 400), 0);
    compare(M.nowSec() > 1700000000, true);
  }
}
