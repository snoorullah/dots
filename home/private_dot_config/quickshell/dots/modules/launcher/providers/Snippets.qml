import Quickshell
import QtQuick

// Snippets mode (`s:`): text snippets with {blanks}. Copy never pastes; Send to pane types at a herdr
// prompt without Enter. Contract: docs/shell/specs/launcher-contract.md.
// Mode spec: docs/shell/specs/launcher-modes.md. Presentation only: `dots-launch-snippets` owns the
// store (~/.config/dots-launcher/snippets), the blanks, the sensitive-text refusal and the argv.
Provider {
  id: root

  providerId: "snippets"
  name: "Snippets"
  prefix: "s:"
  icon: "note"
  inAll: true
  allLimit: 3
  allWeight: 1.0
  sensitive: true   // snippet text can be private: never in Recents, dropped on close

  readonly property var usedIcons: ({ cmd: "terminal-window", reply: "chat-circle", path: "link", block: "note", add: "plus" })

  property var fills: ({})           // {rowKey: {blank: value}}: what the person typed this session
  property bool adding: false        // the add/edit view is open
  property var draft: ({})           // {abbr, kind, title, text, sensitive}
  property bool sensitiveHold: false // refused once; the next save is "save anyway"
  property string sensitiveReason: ""

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-snippets"
  property string lastText: ""

  function query(text) {
    root.lastText = text;
    root.pending = text;
    q.restart();
  }

  function fillArgs(key) {
    var f = root.fills[key] || {};
    var out = [];
    for (var k in f) if (f[k] !== "") out.push(k + "=" + f[k]);
    return out;
  }

  // The core's blank editor calls this on every edit; the helper returns the row re-rendered.
  function fill(rowIndex, name, value) {
    var row = root.rows[rowIndex];
    if (!row) return;
    var f = JSON.parse(JSON.stringify(root.fills));
    f[row.key] = f[row.key] || {};
    f[row.key][name] = value;
    root.fills = f;
    root.run([root.tool, "render", row.key].concat(root.fillArgs(row.key)), function(o) {
      var next = root.rows.slice();
      if (o.row) { o.row.group = row.group; next[rowIndex] = o.row; root.rows = next; }
    });
  }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "draft") { root.beginAdd(); return true; }
    root.run([root.tool, "act", act.verb, String(act.arg)].concat(root.fillArgs(row.key)), function(o) {
      root.done(!!o.close, o.toast || "");
    });
    return true;
  }

  // Ctrl+N: a draft from the clipboard. Secrets never reach the draft.
  function beginAdd() {
    root.run([root.tool, "draft"], function(o) {
      root.draft = o.draft || {};
      root.sensitiveReason = o.draft && o.draft.sensitive ? "This text " + o.draft.sensitive + "." : "";
      root.sensitiveHold = !!root.sensitiveReason;
      root.adding = true;
    });
  }

  // Enter in the add view. A refused text needs a second Enter (force).
  function saveDraft(force) {
    var d = root.draft;
    var a = [root.tool, "add", String(d.abbr || ""), String(d.kind || "block"), String(d.title || ""), String(d.text || "")];
    if (force) a.push("--force");
    root.run(a, function(o) {
      if (o.sensitive) { root.sensitiveHold = true; root.sensitiveReason = o.reason || ""; return; }
      root.adding = false;
      root.sensitiveHold = false;
      root.sensitiveReason = "";
      root.draft = ({});
      root.done(false, o.toast || "");
      root.query(root.lastText);
    });
  }

  function cancelAdd() { root.adding = false; root.sensitiveHold = false; root.sensitiveReason = ""; root.draft = ({}); }

  function reset() {
    root.rows = [];
    root.error = "";
    root.busy = false;
    root.seq++;
    root.fills = ({});
    root.cancelAdd();
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
