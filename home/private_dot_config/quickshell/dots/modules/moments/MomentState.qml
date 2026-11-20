pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "js/Moments.js" as M
import "../bar/js/Profiles.js" as Profiles

// What the return chip and the capture note know about the world: now.json, written by
// dots-overview (the same file the overview reads). Read-only, watched, no polling of the
// file; one 15 s timer only re-evaluates the detour clock while a detour runs.
// Focus is read from Hyprland (focused window class and workspace), local only: leaving the task's
// terminal for another profile for 2 minutes is a detour (rules in js/Moments.js).
// DOTS_OVERVIEW_STATE_DIR, DOTS_OVERVIEW_NOW and DOTS_MOMENTS_FOCUS ({"cls","ws","agoSec","homeWs"}, as if
// focus had been there for agoSec, the terminal on workspace homeWs) exist for the fixture tests.
Singleton {
  id: root

  readonly property string dir: Quickshell.env("DOTS_OVERVIEW_STATE_DIR")
    || (Quickshell.env("HOME") + "/.local/state/dots-overview")

  property var doc: null
  property int tick: 0

  function clock() {
    var o = Number(Quickshell.env("DOTS_OVERVIEW_NOW"));
    return o > 0 ? o : Math.floor(Date.now() / 1000);
  }
  // re-read whenever tick moves (file change, or the 15 s timer while a detour runs)
  readonly property real nowSec: root.tick >= 0 ? root.clock() : 0
  readonly property var task: doc ? doc.task : null
  // where focus is and since when: {home, homeWs, offSince, key}
  property var focusState: M.freshFocus()
  readonly property string taskKey: task ? String(task.uuid || task.ref || "") : ""
  readonly property var detour: M.detour(root.doc, root.nowSec, root.focusState)
  readonly property string backTo: M.backLabel(task)
  readonly property bool hasTask: !!task
  readonly property string backKey: M.BACK_KEY

  // one sample of focus, folded into focusState
  function readFocus() {
    var inj = Quickshell.env("DOTS_MOMENTS_FOCUS");
    if (inj) {
      try {
        var o = JSON.parse(inj);
        return { cls: o.cls, ws: o.ws, profile: Profiles.profileOf(o.ws), ago: Number(o.agoSec) || 0, homeWs: Number(o.homeWs) || 0 };
      } catch (e) { return null; }
    }
    var t = Hyprland.activeToplevel;
    var w = Hyprland.focusedWorkspace;
    var id = w ? w.id : 0;
    return { cls: t && t.lastIpcObject ? t.lastIpcObject["class"] : "", ws: id, profile: Profiles.profileOf(id), ago: 0, homeWs: 0 };
  }
  function sample() {
    var f = root.readFocus();
    var at = root.clock() - (f ? f.ago : 0);
    var st = M.focusStep(root.focusState, f, at, root.taskKey);
    if (f && f.homeWs > 0) st.homeWs = f.homeWs;     // fixture seed: a terminal was on that workspace
    root.focusState = st;
    root.tick++;
  }
  onTaskKeyChanged: root.sample()
  Component.onCompleted: root.sample()

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.sample(); }
    function onFocusedWorkspaceChanged() { root.sample(); }
  }

  // back to the task: the workspace its terminal was on, then its pane. Argv only, local.
  function back() {
    if (!root.detour.active) return false;
    var list = M.backArgvs(root.task, root.focusState.homeWs);
    for (var i = 0; i < list.length; i++) {
      var argv = list[i];
      Quickshell.execDetached(argv);
    }
    return list.length > 0;
  }

  FileView {
    id: file
    path: root.dir + "/now.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.doc = JSON.parse(text()); } catch (e) { root.doc = null; }
      root.tick++;
    }
    onLoadFailed: { root.doc = null; root.tick++; }
  }

  // while focus is off the task the 2 minute mark and the detour minutes need a clock
  Timer {
    interval: 15000
    running: root.detour.active || root.focusState.offSince > 0
    repeat: true
    onTriggered: root.tick++
  }
}
