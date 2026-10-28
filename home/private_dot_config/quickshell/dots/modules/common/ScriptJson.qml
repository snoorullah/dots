import Quickshell.Io
import QtQuick

// Runs a read-only helper on an interval and parses the {text, class, tooltip} line the
// waybar modules already print, so the same scripts feed either bar.
Item {
  id: root

  property var command: []
  property int interval: 30000
  property string text: ""
  property string cls: ""
  property string tooltip: ""
  property bool failed: false

  function parse(raw) {
    try {
      var o = JSON.parse(raw);
      // waybar needs a zero-width space to keep an empty label alive; strip it and trim
      root.text = String(o.text || "").replace(/[​\s]+/g, " ").trim();
      root.cls = String(o["class"] || "");
      root.tooltip = String(o.tooltip || "");
      root.failed = false;
    } catch (e) {
      root.failed = true;
    }
  }

  Process {
    id: proc
    command: root.command
    stdout: StdioCollector { onStreamFinished: root.parse(text) }
    onExited: code => { if (code !== 0) root.failed = true; }
  }

  Timer {
    interval: root.interval
    running: root.command.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
  }
}
