pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Bluetooth power, straight from the default adapter. No adapter, no toggle.
Singleton {
  id: root

  // BluetoothAdapter is real but not exported to qmllint
  // qmllint disable unresolved-type
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool available: adapter !== null
  readonly property bool powered: adapter ? adapter.enabled : false

  function setPowered(on) {
    if (adapter) adapter.enabled = on;
  }
}
