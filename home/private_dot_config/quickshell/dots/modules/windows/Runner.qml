import Quickshell.Io
import QtQuick
import "js/Dispatch.js" as D

// Runs one argv at a time (hyprctl or dots-layout) and reports what it printed. No shell: the
// command is an argv array js/Dispatch.js built. tag "layout:*" replies are one JSON line, any
// other tag is a Hyprland dispatch ("ok") unless it starts with "eval:".
QtObject {
  id: root

  property var queue: []
  property string tag: ""
  signal finished(string tag, bool ok, var data)

  function run(argv, tag) {
    if (!argv) { root.finished(tag, false, null); return; }
    root.queue = root.queue.concat([{ argv: argv, tag: tag }]);
    root.pump();
  }
  function pump() {
    if (proc.running || root.queue.length === 0) return;
    var j = root.queue[0];
    root.queue = root.queue.slice(1);
    root.tag = j.tag;
    proc.command = j.argv;
    proc.running = true;
  }

  property Process proc: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        var t = root.tag;
        if (t.indexOf("layout:") === 0) root.finished(t, D.okJson(text), D.reply(text));
        else if (t.indexOf("eval:") === 0) root.finished(t, D.okEval(text), null);
        else root.finished(t, D.ok(text), null);
        root.pump();
      }
    }
  }
}
