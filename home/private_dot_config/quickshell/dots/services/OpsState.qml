pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The dots-ops summary, from the same command the waybar module runs (`dots-ops waybar`
// only reads state files; it never acts). ok -> the chip has zero width. warn -> amber
// (something waits on an answer). fail -> red (a job failed and nobody is waiting).
Singleton {
  id: root

  property string level: "ok"      // ok | warn | fail
  property string text: ""
  property string tooltip: ""
  property bool stale: false

  readonly property string shownLevel: Lamp.on ? "fail" : level

  function parse(raw) {
    try {
      var o = JSON.parse(raw);
      root.level = (o["class"] === "fail" || o["class"] === "warn") ? o["class"] : "ok";
      root.text = String(o.text || "").replace(/[​\s]+/g, " ").trim();
      root.tooltip = String(o.tooltip || "");
      root.stale = false;
    } catch (e) {
      root.stale = true;
    }
  }

  Process {
    id: proc
    command: [Quickshell.env("HOME") + "/.local/bin/dots-ops", "waybar"]
    stdout: StdioCollector { onStreamFinished: root.parse(text) }
    onExited: code => { if (code !== 0) root.stale = true; }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
  }
}
