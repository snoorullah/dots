pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import "../barpop"
import "../barpop/js/Salah.js" as Salah
import "../../services"
import "js/Menu.js" as M

// The logo menu's behaviour with no window: health, mode, salah, the recovery actions and the
// keyboard. Recovery actions are local argv through py/recover.py, started detached so a step
// that stops the shell does not stop the steps after it. Nothing leaves the machine. The window
// (LogoMenu) shows `m`; the test smoke loads this alone.
Item {
  id: win

  readonly property string name: "logomenu"
  readonly property string pyDir: Quickshell.shellDir + "/modules/logomenu/py"
  readonly property bool wanted: Ui.open === name

  // set by whoever detects it; the shell has no health detector yet
  property var health: ({ state: "ok", fix: "", up: "" })
  property string hint: ""
  property bool typing: false             // the window says whether its filter field has focus
  signal focusKeys()
  signal focusFilter(string text)
  signal clearFilter()
  readonly property real startedAt: Date.now()
  property real nowMs: Date.now()
  property string mode: "Heavy work"
  property var st: ({ sel: "", query: "", logout: 0, ai: false, focusNote: false, focusSeen: false, toast: "" })

  SalahSource { id: salahSrc }
  readonly property var salah: {
    var s = salahSrc.model;
    if (!s.ok || s.cur < 0) return { on: false, ends: "", next: s.ok && s.next >= 0 ? salahSrc.parsed.rows[s.next].name + " " + Salah.hm(salahSrc.parsed.rows[s.next].adhan) : "" };
    var row = salahSrc.parsed.rows[s.cur];
    var nx = salahSrc.parsed.rows[(s.cur + 1) % salahSrc.parsed.rows.length];
    return { on: true, ends: Salah.hm(Salah.windowEnd(row)), next: nx.name + " " + Salah.hm(nx.adhan) };
  }

  readonly property var m: M.build({
    health: { state: health.state, fix: health.fix, up: M.uptimeText(nowMs - startedAt).replace(/^up /, "") },
    mode: mode, salah: salah, st: st, hint: hint
  })

  function patch(o) {
    var n = {};
    for (var k in win.st) n[k] = win.st[k];
    for (var j in o) n[j] = o[j];
    win.st = n;
  }

  onWantedChanged: {
    if (wanted) {
      win.nowMs = Date.now();
      win.st = ({ sel: "", query: "", logout: 0, ai: false, focusNote: false, focusSeen: win.st.focusSeen, toast: "" });
      disp.run(["python3", pyDir + "/recover.py", "mode"], "mode");
      win.focusKeys();
    } else {
      countdown.stop();
    }
  }

  function close() { countdown.stop(); Ui.close(); }

  // ---- actions ---------------------------------------------------------------------------
  Dispatcher {
    id: disp
    onFinished: (tag, code, out) => {
      if (tag !== "mode") return;
      try { var o = JSON.parse(out); if (o.ok) win.mode = o.mode; } catch (e) { }
    }
  }

  function recover(name) {
    var argv = M.recoverArgv(win.pyDir + "/recover.py", name);
    if (!argv) return;
    Quickshell.execDetached(["python3", argv[1], argv[2]]);
  }

  function go(act) {
    if (act.type === "ui") {
      win.close();
      if (act.fn === "cc" || act.fn === "settings") Ui.toggleCc();
      else if (act.fn === "sidebar") Ui.toggleSidebar();
    } else if (act.type === "ipc") {
      win.close();
      var argv = M.ipcArgv(Quickshell.shellDir, act.target, act.fn);
      if (argv) disp.run(argv, "ipc");
    } else if (act.type === "recover") {
      win.recover(act.name);
      if (act.name !== "log") win.close();
    }
  }

  function side(s) {
    if (!s) return;
    if (s.type === "act") go(s.act);
    else if (s.type === "close") win.close();
    else if (s.type === "countdown") countdown.restart();
    else if (s.type === "countdown-stop") countdown.stop();
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: {
      var n = M.tickLogout(win.st.logout);
      if (n > 0) { win.patch({ logout: n }); return; }
      countdown.stop();
      win.patch({ logout: 0 });
      win.recover("logout");
    }
  }

  function cancelLogout() { countdown.stop(); win.patch({ logout: 0, toast: "Logout cancelled" }); }

  function pickMode(name) {
    if (win.salah.on) { win.patch({ toast: "Salah wins. Modes unlock at " + win.salah.ends + "." }); return; }
    var argv = M.modeArgv(win.pyDir + "/recover.py", name);
    if (!argv) return;
    win.mode = name;
    disp.run(argv, "mode");
    win.patch({ focusNote: name === "Focus" && !win.st.focusSeen, focusSeen: win.st.focusSeen || name === "Focus" });
  }

  // ---- keyboard --------------------------------------------------------------------------
  readonly property var keyNames: ({ 16777235: "up", 16777237: "down", 16777220: "enter", 16777221: "enter", 16777232: "home", 16777233: "end" })

  function onKey(e) {
    var typing = win.typing;
    if (e.key === Qt.Key_Escape) {
      var r0 = M.nav(win.m, win.st, "esc", false);
      if (win.st.query !== "") { win.clearFilter(); win.focusKeys(); }
      win.patch(r0.st); win.side(r0.side);
      e.accepted = true; return;
    }
    var key = win.keyNames[e.key] || null;
    var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
    if (key === null && !typing) {
      var t = String(e.text || "");
      if (t === "j" || t === "k") key = t;
      else if (t.length === 1 && /[a-zA-Z0-9 ]/.test(t)) key = t.toLowerCase();
    }
    if (key === null) return;
    e.accepted = true;
    var r = M.nav(win.m, win.st, key, shift);
    win.patch(r.st);
    if (r.st.query !== undefined && r.st.query !== "") win.focusFilter(r.st.query);
    win.side(r.side);
  }
}
