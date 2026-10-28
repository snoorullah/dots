pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The three numbers the overview pill needs, from attention.json (written by the tracking
// side, read-only here). Missing file -> nothing to show. Present but older than 180 s, or
// not version 1 -> stale, which the pill renders as a hollow "?".
Singleton {
  id: root

  readonly property string dir: Quickshell.env("DOTS_OVERVIEW_STATE_DIR")
    || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/dots-overview")

  property int waiting: 0
  property int failed: 0
  property bool present: false
  property bool badVersion: false
  property real ts: 0
  property real now: Date.now() / 1000
  readonly property bool stale: present && (badVersion || (now - ts) > 180)

  function apply(raw) {
    try {
      var o = JSON.parse(raw);
      root.badVersion = o.v !== 1;
      root.ts = Number(o.ts) || 0;
      root.waiting = (o.counts && o.counts.waiting) | 0;
      root.failed = (o.counts && o.counts.failed) | 0;
      root.present = true;
    } catch (e) {
      root.badVersion = true;
      root.present = true;
    }
    root.now = Date.now() / 1000;
  }

  FileView {
    path: root.dir + "/attention.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: {
      root.present = false;
      root.waiting = 0;
      root.failed = 0;
    }
  }

  // ageing is the only thing that changes without a file event
  Timer {
    interval: 30000
    running: root.present
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }
}
