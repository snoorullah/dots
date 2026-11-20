import Quickshell
import QtQuick
import "modules/theme"
import "modules/common"
import "modules/launcher"
import "modules/launcher/parts"
import "modules/launcher/providers"

// Test scene for tests/launcher-ui.sh: quickshell -p <root> on Qt's offscreen platform. It renders the REAL
// Card from the REAL LauncherState with the real All, Apps, Commands, Math and Clipboard providers (fed by
// fixture files and the real Python helpers) and stub Dictionary, Files, Fonts, Work providers. It walks a
// list of steps, logs `PROBE <tag> {json}` (box and text of every objectName'd item) and saves a PNG per step.
ShellRoot {
  id: sc

  readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
  property int closes: 0
  property string farewellText: ""

  FloatingWindow {
    id: win
    implicitWidth: 1160
    implicitHeight: 700
    color: Theme.color.bg

    Item {
      id: stage
      anchors.fill: parent
      Rectangle { anchors.fill: parent; color: Theme.color.bg }

      Item {
        visible: false
        All { id: all; sources: [apps, cmds, math, clip, dict, files, fonts, work] }
        Apps { id: apps }
        Commands { id: cmds }
        Math { id: math }
        Clipboard { id: clip }
        Stub {
          id: dict
          providerId: "dict"; name: "Dictionary"; prefix: "d:"; icon: "book-open-text"; inAll: false
          fixture: [
            { key: "idempotent", title: "idempotent", sub: "adjective", icon: "book-open-text",
              preview: { head: "idempotent", body: "Having the same result however many times it is applied.\n\nUsed in: an idempotent apply changes nothing the second time." },
              actions: [{ label: "Copy word", primary: true }, { label: "Check my text" }] },
            { key: "grammar", title: "Grammar: paste text to check", sub: "Local, nothing leaves the PC", icon: "pen-nib", match: "idempotent",
              preview: { head: "Check grammar", body: "Their going to restart the the node tonight.\n→ They're going to restart the node tonight.\n\n2 fixes. Enter copies the result." },
              actions: [{ label: "Copy word", primary: true }, { label: "Check my text" }] }
          ]
        }
        Stub {
          id: files
          providerId: "files"; name: "Files"; prefix: "f:"; icon: "folder"; inAll: true; confirmFirst: true
          fixture: [
            { key: "restore.md", title: "runbooks/restore.md", sub: "~/work/docs, edited 2h ago", icon: "file-code", match: "restore", score: 0.6,
              preview: { head: "restore.md", body: "## Restore\n1. Stop writes.\n2. Run restore with the latest snapshot.\n3. Verify row counts." },
              actions: [{ label: "Open", primary: true }, { label: "Copy path" }, { label: "Send to agent" }] },
            { key: "drill.png", title: "restore-drill-2026.png", sub: "~/Pictures, last week", icon: "image", match: "restore", score: 0.4,
              preview: { head: "restore-drill-2026.png", body: "Image preview appears here." },
              actions: [{ label: "Open", primary: true }, { label: "Copy path" }, { label: "Send to agent" }] },
            { key: "plan", title: "Restore drill plan", sub: "~/powerhouse/notes", icon: "note", match: "restore", score: 0.3,
              preview: { head: "Restore drill plan", body: "Date to be agreed with Sam R." },
              actions: [{ label: "Open", primary: true }, { label: "Copy path" }, { label: "Send to agent" }] }
          ]
        }
        Stub {
          id: fonts
          providerId: "fonts"; name: "Fonts + icons"; prefix: "t:"; icon: "text-aa"; inAll: false
          fixture: [
            { key: "jb", title: "JetBrains Mono", sub: "Font, installed", icon: "text-aa", match: "mono",
              preview: { head: "JetBrains Mono 0O Il1", font: "JetBrains Mono", body: "The quick brown fox jumps over the lazy dog.\nHD 4412 12m 0:45" },
              actions: [{ label: "Copy name", primary: true }, { label: "Copy CSS" }, { label: "Install" }] },
            { key: "bg", title: "Bricolage Grotesque", sub: "Font, installed", icon: "text-aa", match: "mono",
              preview: { head: "Bricolage 03:18", font: "Bricolage Grotesque", body: "The quick brown fox jumps over the lazy dog." },
              actions: [{ label: "Copy name", primary: true }, { label: "Copy CSS" }, { label: "Install" }] },
            { key: "icon", title: "Icon: terminal-window", sub: "Phosphor Regular", icon: "terminal-window", match: "mono",
              preview: { head: "terminal-window", body: "Copies the name or the SVG. Search covers all Phosphor icons." },
              actions: [{ label: "Copy name", primary: true }, { label: "Copy CSS" }, { label: "Install" }] }
          ]
        }
        Stub {
          id: work
          providerId: "work"; name: "Work"; prefix: ""; icon: "note"; inAll: true; allLimit: 2
          fixture: [
            { key: "t1", title: "Add vCPUs to db-02", sub: "Task, today", icon: "note", match: "db-02", score: 0.8,
              preview: { head: "Add vCPUs to db-02", body: "Task from HD 4412.\nNext step: check the current vCPU count." },
              actions: [{ label: "Open", primary: true }, { label: "Copy" }] },
            { key: "n1", title: "db-02 in Infra", sub: "Node, cluster 1, healthy", icon: "globe", match: "db-02", score: 0.6,
              preview: { head: "db-02", body: "Opens the Infra board on this node." },
              actions: [{ label: "Open", primary: true }, { label: "Copy" }] }
          ]
        }
      }

      LauncherState {
        id: st
        providers: [all, clip, dict, files, fonts, cmds, math, work, apps]
        onCloseRequested: { sc.closes++; st.open = false; }    // what Launcher.qml does through Ui.close()
        onFarewell: text => { sc.farewellText = text; }
      }

      Card {
        id: card
        x: 40
        y: 40
        st: st
      }
    }
  }

  // ---- probes --------------------------------------------------------------------------------
  function walk(item, fn) {
    if (!item) return;
    fn(item);
    var kids = item.children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], fn);
  }
  // the Math provider type shadows the JS Math object in this scope
  function px(v) { return parseInt(v.toFixed(0)); }
  function measure() {
    var m = { names: {}, card: { w: card.width, h: card.height }, closes: sc.closes, mode: st.modeId, query: st.query,
              sel: st.sel, sec: st.sec, nrows: st.rows.length, toast: st.toast, status: st.status, confirm: st.confirm !== null,
              blocked: st.blocked, open: st.open, farewell: sc.farewellText, busy: st.busy };
    walk(card, function (it) {
      if (!it.objectName) return;
      var p = it.mapToItem(card, 0, 0);
      var r = { x: sc.px(p.x), y: sc.px(p.y), w: sc.px(it.width), h: sc.px(it.height), visible: it.visible && it.opacity > 0 };
      if (it.text !== undefined) r.text = String(it.text);
      if (it.titleText !== undefined) { r.title = it.titleText; r.sub = it.subText; }
      if (it.selected !== undefined) r.selected = it.selected;
      if (it.tabId !== undefined) { r.tab = it.tabId; r.active = it.active; }
      if (it.label !== undefined) { r.label = it.label; r.primary = it.primary; r.picked = it.picked; }
      if (!m.names[it.objectName]) m.names[it.objectName] = [];
      m.names[it.objectName].push(r);
    });
    return m;
  }

  // ---- steps ---------------------------------------------------------------------------------
  readonly property int ctrl: Qt.ControlModifier
  function key(k, mods) { st.handleKey({ key: k, modifiers: mods || 0 }); }
  function type(t) { st.setText(t); }

  function reopen() { st.open = false; st.open = true; sc.farewellText = ""; }

  // wait = ms before the probe; late (optional) runs at half of it, for what must follow an async answer
  readonly property var steps: [
    { tag: "all-recents", wait: 900, run: function () { st.open = true; } },
    { tag: "all-query", wait: 1500, run: function () { type("db-02"); } },
    { tag: "all-math", wait: 1200, run: function () { type("1024 * 8"); } },
    { tag: "all-nomatch", wait: 900, run: function () { type("zzzqq"); } },
    { tag: "clip", wait: 1500, run: function () { type(""); type("c:"); } },
    { tag: "clip-filter", wait: 1000, run: function () { type("kubectl"); } },
    { tag: "clip-image", wait: 1400, run: function () { type(""); }, late: function () { st.select(2); } },
    { tag: "clip-nomatch", wait: 900, run: function () { type("qqqq"); } },
    { tag: "dict-word", wait: 600, run: function () { st.setMode("dict"); type("idempotent"); } },
    { tag: "dict-grammar", wait: 400, run: function () { st.select(1); } },
    { tag: "files", wait: 600, run: function () { st.setMode("files"); type("restore"); } },
    { tag: "fonts", wait: 600, run: function () { st.setMode("fonts"); type("mono"); } },
    { tag: "fonts-icon", wait: 400, run: function () { st.select(2); } },
    { tag: "cmd", wait: 1500, run: function () { st.setMode("all"); type(">"); type("k8s"); } },
    { tag: "cmd-secondary", wait: 400, run: function () { sc.key(Qt.Key_J, sc.ctrl); } },
    { tag: "cmd-new", wait: 1200, run: function () { type("my cmd :: echo hi"); }, late: function () { st.select(st.rows.length - 1); } },
    { tag: "math", wait: 1200, run: function () { st.setMode("all"); type("=1024 * 8"); } },
    { tag: "math-units", wait: 1200, run: function () { type("3 GiB in MiB"); } },
    { tag: "tab-next", wait: 300, run: function () { st.setMode("all"); type(""); sc.key(Qt.Key_Tab); } },
    { tag: "tab-back", wait: 300, run: function () { sc.key(Qt.Key_Backtab); sc.key(Qt.Key_Backtab); } },
    { tag: "backspace-chip", wait: 300, run: function () { st.setMode("math"); type(""); sc.key(Qt.Key_Backspace); } },
    { tag: "confirm", wait: 500, run: function () { st.setMode("files"); type("restore"); st.activate(2); } },
    { tag: "confirm-esc", wait: 300, run: function () { sc.key(Qt.Key_Escape); } },
    { tag: "confirm-enter", wait: 500, run: function () { st.activate(2); sc.key(Qt.Key_Return); } },
    { tag: "esc-clear", wait: 500, run: function () { sc.reopen(); st.setMode("files"); type("rest"); sc.key(Qt.Key_Escape); } },
    { tag: "esc-close", wait: 300, run: function () { sc.key(Qt.Key_Escape); } },
    { tag: "act-app", wait: 1500, run: function () { sc.reopen(); type("dbcon"); } },
    { tag: "act-app-open", wait: 600, run: function () { st.activate(0); } },
    { tag: "act-math", wait: 1200, run: function () { sc.reopen(); type("2+2"); } },
    { tag: "act-math-copy", wait: 600, run: function () { sc.key(Qt.Key_Return); } },
    { tag: "act-cmd", wait: 1200, run: function () { sc.reopen(); st.setMode("cmd"); type("pods"); } },
    { tag: "act-cmd-run", wait: 1500, run: function () { sc.key(Qt.Key_Return); } },
    { tag: "act-clip", wait: 1200, run: function () { sc.reopen(); st.setMode("clip"); type("kubectl"); } },
    { tag: "act-clip-pin", wait: 1500, run: function () { sc.key(Qt.Key_2, sc.ctrl); } },
    { tag: "act-clip-paste", wait: 1500, run: function () { sc.key(Qt.Key_Return); } },
    { tag: "act-clip-delete", wait: 1500, run: function () { sc.reopen(); st.setMode("clip"); type("kubectl"); }, late: function () { sc.key(Qt.Key_3, sc.ctrl); } },
    { tag: "recents-after", wait: 1200, run: function () { sc.reopen(); } },
    { tag: "recents-run", wait: 1800, run: function () { sc.key(Qt.Key_Return); } },
    { tag: "locked", wait: 400, run: function () { sc.reopen(); st.blocked = "locked"; } },
    { tag: "salah", wait: 400, run: function () { st.blocked = "salah"; } },
    { tag: "error", wait: 600, run: function () { st.blocked = ""; st.setMode("dict"); dict.error = "The word list is not installed."; } }
  ]
  property int idx: 0

  function next() {
    if (idx >= steps.length) { Qt.quit(); return; }
    var s = steps[idx];
    s.run();
    if (s.late) { lateT.interval = s.wait / 2; lateT.restart(); }
    settle.interval = s.wait;
    settle.restart();
  }

  Timer { id: lateT; onTriggered: sc.steps[sc.idx].late() }

  Timer {
    id: settle
    onTriggered: {
      var s = sc.steps[sc.idx];
      console.log("PROBE " + s.tag + " " + JSON.stringify(sc.measure()));
      stage.grabToImage(function (res) {
        res.saveToFile(sc.outDir + "/launcher-" + s.tag + ".png");
        console.log("SHOT " + s.tag);
        sc.idx++;
        sc.next();
      });
    }
  }

  Component.onCompleted: Qt.callLater(next)
}
