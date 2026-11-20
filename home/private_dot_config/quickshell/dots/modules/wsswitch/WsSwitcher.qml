pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../../services"
import "js/Model.js" as M
import "js/Dispatch.js" as D

// The profile and workspace switcher, shown when Ui.open === "workspaces". Reads Hyprland's
// workspaces and windows (Quickshell.Hyprland), focuses a workspace or window and moves a
// window by dispatching Lua expressions through hyprctl. Nothing leaves the machine.
//   views: A popover (default) -> Tab -> A full -> B grid -> C map -> popover
PanelWindow {
  id: win

  readonly property string name: "workspaces"
  property bool locked: false            // no lock-state source yet; a surface can set it
  readonly property bool wanted: Ui.open === name
  readonly property bool shown: wanted && !locked

  property var st: ({ focus: "", sel: "", hover: "", query: "", wsIdx: 0, variant: "a", mode: "pop", err: "", toast: "", moved: "" })
  property var lastMove: null            // { addr, from, to, title }

  function patch(o) {
    var n = {};
    for (var k in win.st) n[k] = win.st[k];
    for (var j in o) n[j] = o[j];
    win.st = n;
  }

  // ---- live data -------------------------------------------------------------------------
  readonly property var wsList: Hyprland.workspaces.values.map(function (w) {
    return { id: w.id, name: w.name, urgent: w.urgent === true };
  })
  readonly property var winList: Hyprland.toplevels.values.map(function (t) {
    var o = t.lastIpcObject || ({});
    var a = String(t.address);
    return {
      addr: a.indexOf("0x") === 0 ? a : "0x" + a,
      cls: o["class"] || "", title: t.title || o.title || "",
      wsId: o.workspace ? o.workspace.id : (t.workspace ? t.workspace.id : -1),
      floating: !!o.floating
    };
  })
  readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string activeAddr: {
    var t = Hyprland.activeToplevel;
    if (!t) return "";
    var a = String(t.address);
    return a.indexOf("0x") === 0 ? a : "0x" + a;
  }

  SalahSource { id: salahSrc }
  readonly property bool salah: salahSrc.model.ok && salahSrc.model.cur >= 0

  readonly property var m: M.build({
    workspaces: wsList, windows: winList, activeWs: activeWs, activeAddr: activeAddr,
    st: {
      focus: st.focus, sel: st.sel, hover: st.hover, query: st.query, wsIdx: st.wsIdx,
      variant: st.variant, mode: st.mode, salah: salah, locked: locked,
      err: st.err, toast: st.toast, moved: st.moved
    }
  })

  // ---- window ----------------------------------------------------------------------------
  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: panel.pop ? Theme.bar.height + 2 + 4 : Math.max(Theme.bar.height + 8, ((screen ? screen.height : 900) - panel.height) / 2)
  margins.left: panel.pop ? Math.max(Theme.space.l, Math.min((screen ? screen.width : 1600) - panel.width - Theme.space.l, Ui.anchorX - panel.width / 2))
                          : Math.max(0, ((screen ? screen.width : 1600) - panel.width) / 2)
  implicitWidth: panel.width
  implicitHeight: panel.height + (panel.pop ? 4 : 0)
  visible: shown || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  DismissGrab { windows: [win]; armed: win.shown; onDismissed: Ui.close() }

  onWantedChanged: {
    if (wanted) {
      win.st = ({ focus: "", sel: "", hover: "", query: "", wsIdx: 0, variant: "a", mode: "pop", err: "", toast: "", moved: "" });
      Hyprland.refreshWorkspaces();
      Hyprland.refreshToplevels();
      keys.forceActiveFocus();
    }
  }
  Timer { interval: 2000; repeat: true; running: win.shown; onTriggered: Hyprland.refreshToplevels() }

  // ---- actions ---------------------------------------------------------------------------
  Dispatcher {
    id: disp
    onFinished: (tag, ok) => {
      if (ok) return;
      if (tag.indexOf("move:") === 0) win.patch({ err: tag.slice(5), toast: "" });
    }
  }
  Timer { id: toastTimer; interval: 6000; onTriggered: win.patch({ toast: "", moved: "" }) }

  function profileNamed(n) { return M.findProfile(win.m.profiles, n); }

  function focusWs(id) { disp.run(D.focusWs(id), "focus"); Ui.close(); }
  function focusWin(addr) { disp.run(D.focusWin(addr), "focus"); Ui.close(); }

  function moveWin(addr, profile, follow) {
    var p = profileNamed(profile);
    if (!p) return;
    var a = addr || win.activeAddr;
    var w = M.findWin(win.m.profiles, a);
    win.lastMove = { addr: addr, from: w ? w.wsId : -1, to: p.primary, title: w ? w.title : "Window", profile: p.name };
    disp.run(D.moveWin(addr, p.primary, follow), "move:" + a);
    if (follow) { Ui.close(); return; }
    win.patch({ err: "", toast: "Moved " + win.lastMove.title + " to " + p.name + ".", moved: a, sel: a });
    toastTimer.restart();
  }
  function undo() {
    var l = win.lastMove;
    if (!l || l.from < 1) return;
    disp.run(D.moveWin(l.addr, l.from, false), "undo");
    win.patch({ toast: "", moved: "" });
    win.lastMove = null;
  }
  function retry(addr) {
    var l = win.lastMove;
    if (!l) return;
    win.patch({ err: "" });
    disp.run(D.moveWin(l.addr, l.to, false), "move:" + addr);
  }
  function run(act) {
    if (act.type === "focusWs") win.focusWs(act.id);
    else if (act.type === "focusWin") win.focusWin(act.addr);
    else if (act.type === "moveWin") win.moveWin(act.addr, act.profile, act.follow);
  }

  function pickProfile(name) {
    if (name === win.st.focus && name !== win.m.active && win.st.sel === "") {
      var p = profileNamed(name);
      if (p) { win.focusWs(p.primary); return; }
    }
    win.patch({ focus: name, sel: "", wsIdx: 0, hover: "" });
  }
  function pickWin(addr) {
    if (win.st.sel === addr) win.focusWin(addr);
    else win.patch({ sel: addr, err: "" });
  }

  function cycleView() {
    var v = win.st.variant, md = win.st.mode;
    if (v === "a" && md === "pop") win.patch({ mode: "full" });
    else if (v === "a") win.patch({ variant: "b" });
    else if (v === "b") win.patch({ variant: "c" });
    else win.patch({ variant: "a", mode: "pop", query: "" });
  }

  // ---- keyboard --------------------------------------------------------------------------
  readonly property var digitKeys: ({ 49: "1", 50: "2", 51: "3", 52: "4", 53: "5", 54: "6", 55: "7" })
  readonly property var shiftDigitKeys: ({ 33: "s1", 64: "s2", 35: "s3", 36: "s4", 37: "s5", 94: "s6", 38: "s7" })

  function onKey(e) {
    var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
    var typing = panel.filter.activeFocus;
    var key = null;
    if (e.key === Qt.Key_Escape) {
      if (win.st.query !== "") { win.patch({ query: "", sel: "" }); panel.filter.text = ""; keys.forceActiveFocus(); }
      else Ui.close();
      e.accepted = true; return;
    }
    if (e.key === Qt.Key_Tab) { win.cycleView(); e.accepted = true; return; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) key = shift ? "shift-enter" : "enter";
    else if (e.key === Qt.Key_Left) key = "left";
    else if (e.key === Qt.Key_Right) key = "right";
    else if (e.key === Qt.Key_Up) key = "up";
    else if (e.key === Qt.Key_Down) key = "down";
    if (key === null && !typing) {
      if (e.key === Qt.Key_H) key = "left";
      else if (e.key === Qt.Key_L) key = "right";
      else if (e.key === Qt.Key_K) key = "up";
      else if (e.key === Qt.Key_J) key = "down";
      else if (e.key === Qt.Key_Slash) { win.patch({ mode: "full" }); panel.filter.forceActiveFocus(); e.accepted = true; return; }
      else if (e.key === Qt.Key_Z) { win.undo(); e.accepted = true; return; }
      else if (shift && win.shiftDigitKeys[e.key]) key = win.shiftDigitKeys[e.key];
      else if (!shift && win.digitKeys[e.key]) key = win.digitKeys[e.key];
    }
    if (key === null) return;
    e.accepted = true;
    var r = M.nav(win.m, key);
    if (r.act) { win.run(r.act); return; }
    var p = {};
    for (var k in r) p[k] = r[k];
    win.patch(p);
  }
  Item {
    id: keys
    focus: true
    Keys.onPressed: e => win.onKey(e)
  }

  // ---- hover preview ---------------------------------------------------------------------
  property string pendingHover: ""
  Timer { id: hoverTimer; interval: 150; onTriggered: win.patch({ hover: win.pendingHover }) }
  function hoverProfile(name) {
    win.pendingHover = name;
    if (name === "") { hoverTimer.stop(); win.patch({ hover: "" }); }
    else hoverTimer.restart();
  }

  // ---- card ------------------------------------------------------------------------------
  Item {
    id: card
    y: panel.pop ? 4 : 0
    width: panel.width
    height: panel.height
    opacity: win.shown ? 1 : 0
    transform: Scale {
      origin.x: panel.pop ? panel.notchX : panel.width / 2
      origin.y: panel.pop ? 0 : panel.height / 2
      xScale: win.shown ? 1 : 0.92
      yScale: win.shown ? 1 : 0.92
      Behavior on xScale { Anim { duration: win.shown ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: win.shown ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: win.shown ? Theme.motion.base : Theme.motion.fast } }

    WsPanel {
      id: panel
      m: win.m
      strip: true
      notchX: Ui.anchorX - win.margins.left
      onProfilePicked: name => win.pickProfile(name)
      onHoverProfile: name => win.hoverProfile(name)
      onWsFocus: id => win.focusWs(id)
      onWsTab: i => win.patch({ wsIdx: i, sel: "" })
      onWinPicked: addr => win.pickWin(addr)
      onMoveTo: (addr, profile) => win.moveWin(addr, profile, false)
      onRetry: addr => win.retry(addr)
      onUndo: win.undo()
      onEdited: q => win.patch({ query: q, mode: (win.st.variant === "a" && q !== "") ? "full" : win.st.mode })
      onKeyed: e => win.onKey(e)
    }
  }
}
