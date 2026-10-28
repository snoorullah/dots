pragma Singleton
import Quickshell
import QtQuick

// Lamp test (Super+Shift+T, `qs ipc call dots.bar lamp`): force every conditional
// surface visible, amber and red included, for 1.2 s, then let go. It is how you see
// that the alarm still works on a day nothing has gone wrong.
Singleton {
  id: root

  property bool on: false

  function fire(ms) {
    root.on = true;
    off.interval = ms > 0 ? ms : 1200;
    off.restart();
  }

  Timer {
    id: off
    onTriggered: root.on = false
  }
}
