import Quickshell
import QtQuick

// Dictionary mode (`d:`): offline WordNet definitions, grammar check through the local `llm` CLI.
// Contract: docs/shell/specs/launcher-contract.md. Mode spec: docs/shell/specs/launcher-modes.md.
// Presentation only: rows come from `dots-launch-dict`. Nothing leaves the machine.
Provider {
  id: root

  providerId: "dict"
  name: "Dictionary"
  prefix: "d:"
  icon: "book-open-text"
  inAll: false
  allLimit: 1
  allWeight: 0.6
  sensitive: true   // pasted text is private: never in Recents

  readonly property var usedIcons: ({ word: "book-open-text", grammar: "pen-nib" })

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-dict"
  property string lastText: ""

  function query(text) {
    root.lastText = text;
    root.pending = text;
    q.restart();
  }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "grammar") {
      // the result replaces the list with one row holding the corrected text; Enter then copies it
      root.run([root.tool, "grammar", String(act.arg || root.lastText)], function(o) {
        root.rows = o.rows || [];
      });
      return true;
    }
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
