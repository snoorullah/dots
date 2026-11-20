pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../services"
import "js/Switch.js" as S
import "js/Flow.js" as F
import "js/Acts.js" as A

// The window switcher's behaviour with no window of its own: the Alt+Tab state machine, the live window
// list, the lock probe, closes held for Undo, pins, the local-model rank and the keyboard. The
// window (WinSwitcher) shows `m` and forwards keys; the test smoke loads this alone.
//   next() / prev()   the Tab binds        release()   the Alt release        unlocked()   hypridle
Item {
  id: win

  readonly property string name: "winswitch"
  readonly property string pyDir: Quickshell.shellDir + "/modules/winswitch/py"

  property bool typing: false             // the window says whether its filter field has focus
  signal focusKeys()
  signal focusFilter(string text)
  signal clearFilter()

  property var flow: F.start()
  property var st: S.initial()
  property var mru: []
  property var pins: ({})
  property string ticket: ""
  property bool probeDone: false
  property bool lockedNow: false
  property bool flipPending: false
  property real redactUntil: 0
  property bool redactNow: false
  property var closing: null              // { addr, title } held for UNDO_MS, then closed
  property var pending: []                // addresses hidden while their close is held

  readonly property bool shown: flow.phase === "shown" && probeDone && !lockedNow

  // ---- live data -------------------------------------------------------------------------
  readonly property var winList: Hyprland.toplevels.values.map(function (t) {
    var o = t.lastIpcObject || ({});
    var a = String(t.address);
    var ws = o.workspace || ({});
    var special = String(ws.name || "").indexOf("special") === 0;
    return {
      addr: a.indexOf("0x") === 0 ? a : "0x" + a,
      cls: o["class"] || "", title: t.title || o.title || "",
      wsId: special ? -99 : (ws.id !== undefined ? ws.id : -1), special: special,
      hidden: o.hidden === true, focusHist: o.focusHistoryID
    };
  })
  readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string activeAddr: {
    var t = Hyprland.activeToplevel;
    if (!t) return "";
    var a = String(t.address);
    return a.indexOf("0x") === 0 ? a : "0x" + a;
  }
  onActiveAddrChanged: mru = S.touch(mru, activeAddr)

  readonly property var m: S.build({
    windows: winList, activeWs: activeWs, activeAddr: activeAddr, mru: mru, pins: pins,
    locked: lockedNow, redacted: redactNow,
    st: {
      sel: st.sel, scope: st.scope, query: st.query, group: st.group, layout: st.layout, confirm: st.confirm,
      msg: st.msg, closed: st.closed.concat(pending), undo: st.undo, ai: st.ai
    }
  })

  function patch(o) {
    var n = {};
    for (var k in win.st) n[k] = win.st[k];
    for (var j in o) n[j] = o[j];
    win.st = n;
  }

  // ---- actions ---------------------------------------------------------------------------
  Dispatcher {
    id: disp
    onFinished: (tag, code, out) => win.handle(tag, code, out)
  }

  function handle(tag, code, out) {
    if (tag === "lock") {                        // pidof exits 0 while hyprlock runs
      probeDone = true;
      lockedNow = code === 0;
      if (lockedNow) { flow = F.start(); flipPending = false; Ui.open = Ui.open === name ? "" : Ui.open; return; }
      if (flipPending) { flipPending = false; doFlip(); }
      else if (flow.phase === "shown") enter();
    } else if (tag === "pins") {
      try { var o = JSON.parse(out); if (o.ok) pins = o.pins; } catch (e) { }
    } else if (tag === "ticket") {
      try { var t = JSON.parse(out); if (t.ok) ticket = t.ticket; } catch (e2) { }
    } else if (tag === "rank") {
      try {
        var r = JSON.parse(out);
        if (r.ok && st.ai) patch({ ai: { phase: r.via === "model" ? "done" : "fallback", ids: r.ids } });
      } catch (e3) { }
    }
  }

  function probeLock() { disp.run(["pidof", "hyprlock"], "lock"); }

  // inputs from the binds (IPC) -----------------------------------------------------------------
  function next() { press(1); }
  function prev() { press(-1); }
  function press(dir) {
    var r = F.press(flow, Date.now(), dir);
    flow = r.f;
    if (r.act.type === "pending") {
      probeDone = false; lockedNow = false; flipPending = false;
      probeLock();
      tickTimer.restart();
    } else if (r.act.type === "move") {
      var k = S.nav(m, st, dir > 0 ? "tab" : "shift-tab", ticket);
      patch(k.st);
    }
  }
  function release() {
    var r = F.release(flow, Date.now());
    flow = r.f;
    tickTimer.stop();
    if (r.act.type === "flip") {
      if (!probeDone) flipPending = true; else if (!lockedNow) doFlip();
    } else if (r.act.type === "commit") commit();
  }
  function unlocked() {                          // hypridle unlock_cmd
    redactUntil = Date.now() + S.REDACT_MS;
    lockedNow = false;
  }
  function cancel() {
    var r = F.cancel(flow);
    flow = r.f;
    tickTimer.stop();
    leave();
  }

  function doFlip() {
    var a = S.previous(winList, mru, activeAddr);
    if (a) disp.run(A.focusWin(a), "focus");
  }
  function commit() {
    var a = S.selectedAddr(m);
    leave();
    if (a) disp.run(A.focusWin(a), "focus");
  }
  function enter() {
    redactNow = Date.now() < redactUntil;
    st = S.initial();
    st.sel = flow.dir > 0 ? 1 : Math.max(0, m.count - 1);
    Hyprland.refreshToplevels();
    disp.run(["python3", pyDir + "/pins.py", "list"], "pins");
    disp.run(["python3", pyDir + "/pins.py", "current"], "ticket");
    Ui.open = name;
    win.focusKeys();
    if (redactNow) redactTimer.restart();
  }
  function leave() {
    if (Ui.open === name) Ui.open = "";
    redactNow = false;
  }

  Timer {
    id: tickTimer
    interval: F.FLIP_MS
    onTriggered: {
      var r = F.tick(win.flow, Date.now());
      win.flow = r.f;
      if (r.act.type === "show" && win.probeDone && !win.lockedNow) win.enter();
    }
  }
  Timer { id: redactTimer; interval: S.REDACT_MS; onTriggered: win.redactNow = false }
  // the lock can arrive while the strip is up; look again once a second, only while shown
  Timer { interval: 1000; repeat: true; running: win.shown; onTriggered: win.probeLock() }

  // a close is held so Undo can take it back; it is dispatched when the hold ends
  Timer {
    id: closeTimer
    interval: S.UNDO_MS
    onTriggered: win.flushClose()
  }
  function flushClose() {
    closeTimer.stop();
    var c = win.closing;
    if (!c) return;
    disp.run(A.closeWin(c.addr), "close");
    win.closing = null;
    win.pending = win.pending.filter(function (a) { return a !== c.addr; });
    if (win.st.undo && win.st.undo.addr === c.addr) win.patch({ undo: null });
  }
  function undoClose() {
    var c = win.closing;
    if (!c) return;
    closeTimer.stop();
    win.closing = null;
    win.pending = win.pending.filter(function (a) { return a !== c.addr; });
    win.patch({ undo: null, closed: win.st.closed.filter(function (a) { return a !== c.addr; }), msg: "" });
  }

  function scopeKey(id) {
    return S.nav(win.m, win.st, { task: "`", workspace: "1", profile: "2", all: "3" }[id], win.ticket).st;
  }

  function side(s) {
    if (!s) return;
    if (s.type === "closeLater") {
      win.flushClose();
      win.closing = { addr: s.addr };
      win.pending = win.pending.concat([s.addr]);
      win.patch({ closed: [] });
      closeTimer.restart();
    } else if (s.type === "scratch") disp.run(A.scratchpad(s.addr), "scratch");
    else if (s.type === "pin") { disp.run(A.pinsArgv(pyDir + "/pins.py", "set", s.addr, s.ticket), "pinset"); var n = {}; for (var k in pins) n[k] = pins[k]; n[s.addr] = s.ticket; pins = n; }
    else if (s.type === "unpin") { disp.run(A.pinsArgv(pyDir + "/pins.py", "unset", s.addr), "pinset"); var u = {}; for (var j in pins) if (j !== s.addr) u[j] = pins[j]; pins = u; }
  }

  // ---- keyboard --------------------------------------------------------------------------
  readonly property var keyNames: ({ 16777217: "tab", 16777218: "shift-tab", 16777234: "left", 16777236: "right", 16777235: "up", 16777237: "down", 16777220: "enter", 16777221: "enter" })

  function onKey(e) {
    var typing = win.typing;
    if (e.key === Qt.Key_Escape) {
      if (win.st.query !== "") { win.patch({ query: "", ai: null, sel: 1 }); win.clearFilter(); win.focusKeys(); }
      else win.cancel();
      e.accepted = true; return;
    }
    var key = win.keyNames[e.key] || null;
    if (key === "tab" && (e.modifiers & Qt.ShiftModifier)) key = "shift-tab";
    if (key === "enter") { win.release(); e.accepted = true; return; }
    if (key === null && !typing) {
      var t = String(e.text || "").toLowerCase();
      if (t === "/" ) { win.focusFilter(""); e.accepted = true; return; }
      if (t === "w" || t === "m" || t === "p" || t === "u" || t === "`" || t === "1" || t === "2" || t === "3") key = t;
      else if (t.length === 1 && /[a-z0-9]/.test(t)) { win.focusFilter(t); win.edited(t); e.accepted = true; return; }
    }
    if (key === null) return;
    e.accepted = true;
    var r = S.nav(win.m, win.st, key, win.ticket);
    win.patch(r.st);
    win.side(r.side);
  }
  function edited(q) {
    win.patch({ query: q, sel: 0, ai: S.questionFor(q) ? ({ phase: "thinking", ids: [] }) : null });
    rankTimer.restart();
  }
  Timer {
    id: rankTimer
    interval: 450
    onTriggered: {
      if (!S.questionFor(win.st.query) || win.lockedNow || win.redactNow) return;
      disp.run(A.rankArgv(win.pyDir + "/rank.py", win.st.query, win.m.cards.map(function (c) { return { addr: c.addr, title: c.full, app: c.app }; })), "rank");
    }
  }
}
