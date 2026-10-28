pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Wi-Fi radio state, read when the quick panel opens and after a toggle. No polling.
Singleton {
  id: root

  property bool wifi: false
  property bool available: false

  function refresh() {
    if (!probe.running) probe.running = true;
  }
  function setWifi(on) {
    Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
    root.wifi = on;
  }

  Process {
    id: probe
    command: ["nmcli", "radio", "wifi"]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = text.trim();
        root.available = (s === "enabled" || s === "disabled");
        root.wifi = (s === "enabled");
      }
    }
  }
}
