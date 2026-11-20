import Quickshell.Io
import QtQuick

// Runs one argv at a time and reports its exit code and stdout. No shell: the command is the
// array js/Acts.js built. Nothing is retried here; the caller decides what a failure means.
QtObject {
  id: root

  property var queue: []
  property string tag: ""
  property string out: ""
  property bool gotOut: false
  property bool gotExit: false
  property int code: -1
  signal finished(string tag, int code, string out)

  function run(argv, tag) {
    if (!argv) { root.finished(tag, -1, ""); return; }
    root.queue = root.queue.concat([{ argv: argv, tag: tag }]);
    root.pump();
  }
  function pump() {
    if (proc.running || root.queue.length === 0) return;
    var j = root.queue[0];
    root.queue = root.queue.slice(1);
    root.tag = j.tag;
    root.gotOut = false;
    root.gotExit = false;
    proc.command = j.argv;
    proc.running = true;
  }
  function settle() {
    if (!root.gotOut || !root.gotExit) return;
    root.finished(root.tag, root.code, root.out);
    root.pump();
  }

  property Process proc: Process {
    stdout: StdioCollector {
      onStreamFinished: { root.out = text; root.gotOut = true; root.settle(); }
    }
    onExited: c => { root.code = c; root.gotExit = true; root.settle(); }
  }
}
