import Quickshell
import QtQuick

// Files mode (`f:`): fd over $HOME, text and image preview, open, copy path.
// Contract: docs/shell/specs/launcher-contract.md. Mode spec: docs/shell/specs/launcher-modes.md.
// Presentation only: every row comes from the helper `dots-launch-files` (argv, JSON on stdout).
Provider {
  id: root

  providerId: "files"
  name: "Files"
  prefix: "f:"
  icon: "folder"
  inAll: true
  allLimit: 4
  allWeight: 0.8
  sensitive: false

  // Phosphor names the helper puts in row.icon. Listed so the registry generator keeps them.
  readonly property var usedIcons: ({ folder: "folder", code: "file-code", image: "image", note: "note" })

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-files"
  property string lastText: ""
  property string toast: ""

  function query(text) {
    root.lastText = text;
    root.pending = text;
    q.restart();
  }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    root.run([root.tool, "act", act.verb, String(act.arg)], function(o) {
      root.done(!!o.close, o.toast || "");
    });
    return true;
  }

  Timer {
    id: q
    interval: root.debounce
    onTriggered: root.run([root.tool, "query", root.pending], function(o) {
      root.rows = o.rows || [];
      root.hint = o.hint || "";
    })
  }
}
