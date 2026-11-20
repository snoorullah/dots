import Quickshell
import QtQuick

// SSH hosts mode (`h:`): Host entries of ~/.ssh/config; connect opens a new herdr pane.
// Contract: docs/shell/specs/launcher-contract.md. Mode spec: docs/shell/specs/launcher-modes.md.
// Presentation only: `dots-launch-hosts` parses the config and builds the argv. Hosts are never probed.
Provider {
  id: root

  providerId: "hosts"
  name: "SSH hosts"
  prefix: "h:"
  icon: "terminal-window"
  inAll: true
  allLimit: 2
  allWeight: 0.9
  sensitive: false

  readonly property var usedIcons: ({ host: "terminal-window" })

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-hosts"
  property string lastText: ""
  property string pendingForget: ""

  function query(text) {
    root.lastText = text;
    root.pending = text;
    root.pendingForget = "";
    q.restart();
  }

  function cancelConfirm() { root.pendingForget = ""; }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "forget" && root.pendingForget !== row.key) {
      root.pendingForget = row.key;
      root.confirmRequested({ title: "Forget host key?", detail: "Removes " + row.title + " from known_hosts. Asked once, then done.", danger: true, label: "Forget key" });
      return true;
    }
    root.pendingForget = "";
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
