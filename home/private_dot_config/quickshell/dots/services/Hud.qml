pragma Singleton
import Quickshell
import QtQuick

// What the OSD is showing right now. Anything that changes volume or brightness calls
// show(); the OSD window just binds to this.
Singleton {
  id: root

  property string kind: "volume"     // volume | brightness
  property real value: 0             // 0..1
  property bool muted: false
  property bool shown: false

  function show(k, v, muted) {
    root.kind = k;
    root.value = Math.max(0, Math.min(1, v));
    root.muted = !!muted;
    root.shown = true;
    hide.restart();
  }

  Timer {
    id: hide
    interval: 1200
    onTriggered: root.shown = false
  }
}
