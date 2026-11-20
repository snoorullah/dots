import Quickshell.Io
import QtQuick

// Base type for every launcher mode. The core (modules/launcher/Launcher.qml) never knows a
// concrete provider: it reads these properties, calls query()/activate(), and renders rows.
// Contract: docs/shell/specs/launcher-contract.md
Item {
  id: root

  // ---- identity (set by the subclass) -----------------------------------------------
  property string providerId: ""     // stable key, "clip"; `id` is reserved by QML
  property string name: ""           // chip label, "Clipboard"
  property string prefix: ""         // "c:" ; "" = All-only provider
  property string icon: ""           // Phosphor name
  property bool inAll: true          // contributes rows to All
  property int allLimit: 3           // max rows it gives All
  property real allWeight: 1.0       // All ranking multiplier
  property bool sensitive: false     // rows never logged, never kept in recents

  // ---- state (the core reads, the provider writes) -----------------------------------
  // row: { key, title, sub, icon, score?, preview:{head, body, font?, image?},
  //        actions:[{label, primary}] }   key is unique and stable within the provider
  property var rows: []              // replace the whole array; rowsChanged re-ranks All
  property bool busy: false
  property string error: ""          // "" = ok; non-empty replaces the list with one error line
  property string hint: ""           // empty-state line, "No clipboard history yet"

  // ---- helper (optional): Python program, argv only, JSON on stdout ------------------
  property var helper: []            // e.g. [Paths.bin + "/dots-launch-clip", "query"]
  property int debounce: 80

  // ---- API ----------------------------------------------------------------------------
  signal done(bool closeLauncher, string toast)   // after activate(); toast "" = none
  signal modeRequested(string providerId)         // jump to another mode (e.g. k -> namespaces)
  signal confirmRequested(var spec)  // {title, detail, danger, label}: core shows the confirm card

  // Called on every keystroke, text has the prefix already removed. Default runs `helper`.
  function query(text) {
    if (helper.length === 0) return;
    pending = text;
    deb.restart();
  }
  // Enter = actionIndex 0. Return true if handled. Default does nothing.
  function activate(rowIndex, actionIndex) { return false; }
  // Called when the launcher opens/closes; drop secrets and cached text on close.
  function reset() { rows = []; error = ""; busy = false; seq++; }

  // Run any argv; resolves through onResult(parsedJson). Not a shell: no string commands.
  function run(argv, onResult) {
    var n = ++seq;
    busy = true;
    var p = proc.createObject(root, { command: argv, ticket: n, cb: onResult });
    p.running = true;
  }

  // ---- internals ----------------------------------------------------------------------
  property string pending: ""
  property int seq: 0

  Timer {
    id: deb
    interval: root.debounce
    onTriggered: root.run(root.helper.concat([root.pending]), function(o) {
      root.rows = o.rows || [];
      root.hint = o.hint || root.hint;
    })
  }

  Component {
    id: proc
    Process {
      id: me
      property int ticket: 0
      property var cb: null
      stdout: StdioCollector {
        onStreamFinished: {
          var o = root.parseOut(text);
          if (me.ticket === root.seq) {      // drop answers to older queries
            root.busy = false;
            root.error = o.error || "";
            if (!o.error && me.cb) me.cb(o);
          }
          me.destroy();
        }
      }
      onExited: code => { if (code !== 0 && me.ticket === root.seq) { root.busy = false; root.error = root.error || "helper failed"; } }
    }
  }

  function parseOut(raw) {
    try { return JSON.parse(raw); } catch (e) { return { error: "bad helper output" }; }
  }
}
