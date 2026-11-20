import Quickshell.Io
import QtQuick
import "js/Dispatch.js" as D

// Runs hyprctl one argv at a time and reports whether Hyprland answered "ok". No shell: the
// command is the argv array js/Dispatch.js built. Nothing is retried here; the caller shows the
// error row and the person decides.
QtObject {
  id: root

  property var queue: []
  property string tag: ""
  signal finished(string tag, bool ok)
  signal replied(string tag, var data)      // the parsed JSON line of a dots-layout call, else null

  function run(argv, tag) {
    if (!argv) { root.finished(tag, false); return; }
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
        var layout = root.tag.indexOf("layout:") === 0;
        root.replied(root.tag, layout ? D.reply(text) : null);
        root.finished(root.tag, layout ? D.okJson(text) : D.ok(text));
        root.pump();
      }
    }
  }
}
