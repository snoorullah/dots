pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../../services"
import "../bar/js/Profiles.js" as Profiles
import "js/Presets.js" as P
import "js/Restore.js" as R
import "js/Scratch.js" as S
import "js/Dispatch.js" as D

// The windows module's one card, centred: the tiling assistant, the scratchpad note or the
// restore prompt, by Ui.open ("tiling" | "scratchpad" | "restore"). Reads Hyprland (window
// counts, the focused workspace) and dots-layout (the saved layout, notes, presets); changes
// the layout by dispatching Lua expressions through hyprctl. Nothing leaves the machine.
// Ask first: at login it checks for a saved layout once and opens "restore" only if one is waiting.
PanelWindow {
  id: win

  readonly property string kind: Ui.open
  readonly property bool wanted: kind === "tiling" || kind === "scratchpad" || kind === "restore"
  property bool pinned: false
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/dots-layout"

  // ---- live data -------------------------------------------------------------------------
  readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string profile: activeWs > 0 ? Profiles.profileOf(activeWs) : "Other"
  readonly property int tiledCount: Hyprland.toplevels.values.filter(function (t) {
    var o = t.lastIpcObject || ({});
    return (o.workspace ? o.workspace.id : (t.workspace ? t.workspace.id : -1)) === win.activeWs && !o.floating;
  }).length

  property string tilePick: ""
  property string remembered: ""
  property string tab: "note"
  property string noteText: ""
  property var layoutStatus: null       // dots-layout status().layout
  property var rOn: ({})
  property var rResult: null
  property string err: ""
  property string note: ""              // one quiet line under the card

  readonly property var tilingM: P.build({ n: tiledCount, selected: tilePick, remembered: remembered })
  readonly property var scratchM: S.build({ tab: tab, text: noteText, pinned: pinned, profile: profile })
  readonly property var restoreM: R.build(layoutStatus, rOn)

  // ---- window ----------------------------------------------------------------------------
  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: Math.max(Theme.bar.height + 8, ((screen ? screen.height : 900) - card.height) / 2)
  margins.left: Math.max(0, ((screen ? screen.width : 1600) - card.width) / 2)
  implicitWidth: card.width
  implicitHeight: card.height
  visible: wanted || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  DismissGrab { windows: [win]; armed: win.wanted && !win.pinned; onDismissed: win.close() }

  Runner {
    id: run
    onFinished: (tag, ok, data) => {
      if (tag === "layout:status" || tag === "layout:boot") {
        win.layoutStatus = data && data.layout ? data.layout : null;
        if (tag === "layout:boot" && ok && data && data.pending && data.layout && Ui.open === "") Ui.toggle("restore");
      } else if (tag === "layout:note") {
        win.noteText = data && data.ok ? data.text : "";
      } else if (tag === "layout:pref") {
        win.remembered = data && data.ok ? data.value : "";
      } else if (tag === "layout:restore") {
        win.rResult = ok ? { launched: data.launched, failed: data.failed } : (data && data.launched !== undefined ? { launched: data.launched, failed: data.failed } : null);
        if (!win.rResult) win.err = "Nothing was restored.";
        else resultTimer.restart();
      } else if (tag === "layout:save") {
        win.note = ok ? "Saved to notes." : "Nothing to save.";
      } else if (tag.indexOf("eval:") === 0 || tag.indexOf("msg:") === 0) {
        if (!ok) win.err = "Hyprland refused the layout.";
      }
    }
  }
  Timer { id: resultTimer; interval: 10000; onTriggered: win.close() }
  Timer { id: noteTimer; interval: 600; onTriggered: run.run(D.noteSet(win.tool, win.profile, win.noteText), "layout:noteset") }
  // once per login: ask only if a layout from an earlier boot is waiting
  Timer { interval: 8000; running: true; repeat: false; onTriggered: run.run(D.status(win.tool), "layout:boot") }

  function close() { noteTimer.stop(); if (win.kind === "scratchpad") run.run(D.noteSet(win.tool, win.profile, win.noteText), "layout:noteset"); Ui.close(); }

  onKindChanged: {
    win.err = ""; win.note = ""; win.rResult = null; win.rOn = ({}); win.tilePick = "";
    if (kind === "tiling") run.run(D.prefGet(tool, profile), "layout:pref");
    else if (kind === "scratchpad") run.run(D.noteGet(tool, profile), "layout:note");
    else if (kind === "restore" && layoutStatus === null) run.run(D.status(tool), "layout:status");
    if (wanted) { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); keys.forceActiveFocus(); }
  }

  // ---- actions ---------------------------------------------------------------------------
  // the scratchpad's windows: show or hide this profile's special workspace (IPC target calls it)
  function scratchWorkspace() { run.run(D.scratchToggle(win.profile), "scratch:" + win.profile); }
  function applyPreset(id) {
    var st = P.steps(id, win.activeWs);
    if (!st) { win.err = "No workspace to tile."; return; }
    win.err = "";
    st.forEach(function (a, i) { run.run(a, (i === 0 ? "eval:" : "msg:") + id); });
    run.run(D.prefSet(win.tool, win.profile, id), "layout:prefset");
    Ui.close();
  }
  function restoreNow() {
    var a = D.restore(win.tool, win.restoreM.parts);
    if (a) run.run(a, "layout:restore");
  }
  function startClean() { run.run(D.dismiss(win.tool), "layout:dismiss"); Ui.close(); }
  function undoRestore() { run.run(D.undo(win.tool), "layout:undo"); win.rResult = null; Ui.close(); }
  function scratchAct(id) {
    if (id === "pin") win.pinned = !win.pinned;
    else if (id === "save") { run.run(D.noteSet(win.tool, win.profile, win.noteText), "layout:noteset"); run.run(D.noteSave(win.tool, win.profile), "layout:save"); }
  }

  // ---- keyboard --------------------------------------------------------------------------
  function onKey(e) {
    if (e.key === Qt.Key_Escape) {
      if (win.kind === "restore" && !win.rResult) win.startClean(); else win.close();
      e.accepted = true; return;
    }
    if (win.kind === "scratchpad") return;               // typing goes to the note
    var key = null;
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) key = "enter";
    else if (e.key === Qt.Key_Left) key = "left";
    else if (e.key === Qt.Key_Right) key = "right";
    else if (e.key === Qt.Key_Up) key = "up";
    else if (e.key === Qt.Key_Down) key = "down";
    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_6) key = String(e.key - Qt.Key_0);
    else if (e.key === Qt.Key_Z && win.kind === "restore" && win.rResult) { win.undoRestore(); e.accepted = true; return; }
    if (key === null) return;
    e.accepted = true;
    if (win.kind === "tiling") {
      var r = P.nav(win.tilingM, key);
      if (r.act) win.applyPreset(r.act.id); else if (r.selected) win.tilePick = r.selected;
    } else if (win.kind === "restore" && !win.rResult) {
      var q = R.nav(win.restoreM, key);
      if (q.act && q.act.type === "restore") win.restoreNow();
      else if (q.toggle) { var o = {}; for (var k in win.rOn) o[k] = win.rOn[k]; o[q.toggle] = !win.restoreM.rows.filter(function (x) { return x.id === q.toggle; })[0].on; win.rOn = o; }
    }
  }
  Item { id: keys; focus: true; Keys.onPressed: e => win.onKey(e) }

  // ---- card ------------------------------------------------------------------------------
  Surface {
    id: card
    corner: Theme.radius.card
    width: body.width + 2 * Theme.space.xxl
    height: body.height + 2 * Theme.space.xxl + (line.visible ? line.height + Theme.space.xl : 0)
    opacity: win.wanted ? 1 : 0
    transform: Scale {
      origin.x: card.width / 2
      origin.y: card.height / 2
      xScale: win.wanted ? 1 : 0.92
      yScale: win.wanted ? 1 : 0.92
      Behavior on xScale { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }

    Item {
      id: body
      x: Theme.space.xxl
      y: Theme.space.xxl
      width: win.kind === "restore" ? restorePrompt.width : (win.kind === "scratchpad" ? scratch.width : tiling.width)
      height: win.kind === "restore" ? restorePrompt.height : (win.kind === "scratchpad" ? scratch.height : tiling.height)

      TilingAssistant {
        id: tiling
        visible: win.kind === "tiling"
        m: win.tilingM
        onPicked: id => win.tilePick = id
        onApply: id => win.applyPreset(id)
      }
      ScratchPanel {
        id: scratch
        visible: win.kind === "scratchpad"
        m: win.scratchM
        onTabPicked: id => win.tab = id
        onEdited: t => { win.noteText = t; noteTimer.restart(); }
        onActed: id => win.scratchAct(id)
      }
      RestorePrompt {
        id: restorePrompt
        visible: win.kind === "restore"
        m: win.restoreM
        result: win.rResult
        onToggled: id => { var o = {}; for (var k in win.rOn) o[k] = win.rOn[k]; o[id] = !win.restoreM.rows.filter(function (x) { return x.id === id; })[0].on; win.rOn = o; }
        onRestore: win.restoreNow()
        onClean: win.startClean()
        onUndo: win.undoRestore()
      }
    }
    Cap {
      id: line
      visible: win.err !== "" || win.note !== ""
      x: Theme.space.xxl
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Theme.space.xl
      text: win.err !== "" ? win.err : win.note
      color: win.err !== "" ? Theme.color.failed : Theme.color.fgDim
      dim: false
    }
  }
}
