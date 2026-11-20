import Quickshell
import QtQuick

// Emoji and symbols mode (`e:`): a local table (unicodedata + keywords), copy only (never types), a tray for
// building a short run of glyphs. Contract: docs/shell/specs/launcher-contract.md.
// Mode spec: docs/shell/specs/launcher-modes.md. Presentation only: rows come from `dots-launch-emoji`.
Provider {
  id: root

  providerId: "emoji"
  name: "Emoji"
  prefix: "e:"
  icon: "smiley"
  inAll: false
  allLimit: 1
  allWeight: 0.5
  sensitive: false

  readonly property var usedIcons: ({ glyph: "smiley" })

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-emoji"
  property string lastText: ""
  property var tray: []              // glyphs collected with "Add to tray"; copied as one string

  function query(text) {
    root.lastText = text;
    root.pending = text;
    q.restart();
  }

  function trayText() { return root.tray.join(""); }
  function clearTray() { root.tray = []; }
  function copyTray() {
    if (root.tray.length === 0) return false;
    root.run([root.tool, "act", "copy", root.trayText()], function(o) {
      root.tray = [];
      root.done(!!o.close, o.toast || "");
    });
    return true;
  }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "tray") {            // local: no helper call, the launcher stays open
      root.tray = root.tray.concat([String(act.arg)]);
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
