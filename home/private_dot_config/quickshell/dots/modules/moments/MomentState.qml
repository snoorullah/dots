pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/Moments.js" as M

// What the return chip and the capture note know about the world: now.json, written by
// dots-overview (the same file the overview reads). Read-only, watched, no polling of the
// file; one 15 s timer only re-evaluates the detour clock while a detour runs.
// DOTS_OVERVIEW_STATE_DIR and DOTS_OVERVIEW_NOW exist for the fixture tests.
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
  readonly property var detour: M.detour(root.doc, root.nowSec)
  readonly property string backTo: M.backLabel(task)
  readonly property bool hasTask: !!task

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

  Timer {
    interval: 15000
    running: root.detour.active
    repeat: true
    onTriggered: root.tick++
  }
}
