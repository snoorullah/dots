pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Backlight via brightnessctl. Read on start and after every change; never polled.
Singleton {
  id: root

  property real value: 0          // 0..1
  property bool available: false

  function refresh() {
    if (!probe.running) probe.running = true;
  }
  function set(fraction) {
    var pct = Math.round(Math.max(0.01, Math.min(1, fraction)) * 100);
    Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", pct + "%"]);
    root.value = pct / 100;
  }

  Process {
    id: probe
    command: ["brightnessctl", "-c", "backlight", "-m"]
    stdout: StdioCollector {
      onStreamFinished: {
        // device,class,current,percent%,max
        var f = text.trim().split(",");
        if (f.length >= 5) {
          root.value = parseInt(f[3]) / 100;
          root.available = true;
        } else {
          root.available = false;
        }
      }
    }
  }

  Component.onCompleted: refresh()
}
