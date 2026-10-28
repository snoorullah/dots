pragma Singleton
import Quickshell
import QtQuick

// Keep the screen awake. Off is nominal; on is a state I hold open, so the chip washes
// amber. Each bar window carries an IdleInhibitor bound to `on`.
Singleton {
  id: root

  property bool on: false

  function toggle() { root.on = !root.on; }
}
