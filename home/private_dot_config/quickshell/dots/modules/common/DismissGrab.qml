import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// A focus grab that means "close on an outside click", minus one case: a screenshot
// (slurp/grim, the Print binds) takes the keyboard and clears the grab too. Then it
// stays open until the capture is done and re-arms. Every popout and overview surface
// uses this, so any of them can be captured.
Scope {
  id: g

  property alias windows: grab.windows
  property bool armed: false
  property bool capturing: false
  signal dismissed()

  HyprlandFocusGrab {
    id: grab
    active: g.armed && !g.capturing
    onCleared: if (g.armed) probe.running = true
  }

  Process {
    id: probe
    command: ["sh", "-c", "sleep 0.2; pgrep -x slurp >/dev/null || pgrep -x grim >/dev/null"]
    onExited: code => {
      if (code === 0) { g.capturing = true; poll.start(); }
      else g.dismissed();
    }
  }

  Timer {
    id: poll
    interval: 300
    repeat: true
    onTriggered: if (!still.running) still.running = true
  }

  Process {
    id: still
    command: ["sh", "-c", "pgrep -x slurp >/dev/null || pgrep -x grim >/dev/null"]
    onExited: code => {
      if (code !== 0) { poll.stop(); g.capturing = false; }
    }
  }
}
