pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Night light through hyprsunset, when it is installed. Absent -> the toggle is hidden.
Singleton {
  id: root

  property bool available: false
  property bool on: false
  property int kelvin: 4000

  function toggle() {
    if (!available) return;
    if (on) Quickshell.execDetached(["pkill", "-x", "hyprsunset"]);
    else Quickshell.execDetached(["hyprsunset", "-t", String(kelvin)]);
    on = !on;
  }

  Process {
    id: probeBin
    command: ["sh", "-c", "command -v hyprsunset >/dev/null && echo yes"]
    stdout: StdioCollector { onStreamFinished: root.available = text.trim() === "yes" }
  }
  Process {
    id: probeRun
    command: ["pgrep", "-x", "hyprsunset"]
    onExited: code => root.on = (code === 0)
  }

  Component.onCompleted: {
    probeBin.running = true;
    probeRun.running = true;
  }
}
