import Quickshell
import QtQuick

// Windows mode (`w:`): Hyprland toplevels with herdr panes underneath. Focus, move here, close.
// Contract: docs/shell/specs/launcher-contract.md. Mode spec: docs/shell/specs/launcher-modes.md.
// Presentation only: rows, banner and the focus dispatch come from `dots-launch-windows`.
Provider {
  id: root

  providerId: "windows"
  name: "Windows"
  prefix: "w:"
  icon: "stack"
  inAll: true
  allLimit: 3
  allWeight: 1.1
  sensitive: true   // window titles are private: never in Recents, dropped on close

  readonly property var usedIcons: ({ terminal: "terminal-window", code: "code", browser: "globe", chat: "chat-circle",
                                      mail: "envelope-simple", player: "speaker-high", notes: "note", other: "stack" })

  // set by the integration: screen share on (titles masked), focus mode profile ("" = off)
  property bool masked: false
  property string focusProfile: ""
  property var banner: null          // {tone, title, detail, verb?, arg?} drawn above the list
  property var flash: null           // banner from a failed action, kept across the refresh it triggers
  property string pendingClose: ""   // row key waiting for the second activate (confirm card)

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-windows"
  property string lastText: ""

  function argvQuery(text) {
    var a = [root.tool, "query"];
    if (root.masked) a.push("--mask");
    if (root.focusProfile) { a.push("--focus"); a.push(root.focusProfile); }
    a.push(text);
    return a;
  }

  function query(text) {
    root.lastText = text;
    root.pending = text;
    root.pendingClose = "";
    q.restart();
  }

  function cancelConfirm() { root.pendingClose = ""; }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "close" && root.pendingClose !== row.key) {
      root.pendingClose = row.key;
      root.confirmRequested({ title: "Close " + row.title + "?", detail: "Unsaved work in that window is lost.", danger: true, label: "Close window" });
      return true;
    }
    root.pendingClose = "";
    root.run([root.tool, "act", act.verb, String(act.arg)], function(o) {
      if (o.banner) { root.banner = o.banner; root.flash = o.banner; }
      if (o.refresh) root.query(root.lastText);
      if (!o.banner) root.done(!!o.close, o.toast || "");
    });
    return true;
  }

  function reset() {
    root.banner = null;
    root.flash = null;
    root.pendingClose = "";
    root.rows = [];
    root.error = "";
    root.busy = false;
    root.seq++;
  }

  Timer {
    id: q
    interval: root.debounce
    onTriggered: root.run(root.argvQuery(root.pending), function(o) {
      root.rows = o.rows || [];
      root.hint = o.hint || "";
      root.banner = o.banner || root.flash;
      root.flash = null;
    })
  }
}
