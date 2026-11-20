import Quickshell
import QtQuick

// Clipboard ("c:"): the encrypted history kept by dots-clip. Sensitive: never in Recents, never in All,
// and the decrypted image previews are purged when the launcher closes (reset). Paste puts the item
// back on the clipboard (wl-copy); typing it into the old window needs wtype and is not done here.
Provider {
  id: root

  providerId: "clip"
  name: "Clipboard"
  prefix: "c:"
  icon: "clipboard-text"
  inAll: false
  sensitive: true
  hint: "No clipboard history yet. Copy something and it shows up here."

  readonly property string bin: (Quickshell.env("DOTS_LAUNCHER_BIN") || (Quickshell.env("HOME") + "/.local/bin")) + "/dots-clip"
  helper: [root.bin, "list"]

  function refresh() { run(helper.concat([pending]), function (o) { root.rows = o.rows || []; root.hint = o.hint || root.hint; }); }

  function activate(rowIndex, actionIndex) {
    var r = rows[rowIndex];
    if (!r || !r.actions || r.actions.length === 0) return false;
    if (actionIndex === 0) {
      run([root.bin, "paste", r.key], function (o) { root.done(true, o.toast || "Copied"); });
      return true;
    }
    if (actionIndex === 1) {
      run([root.bin, r.pinned ? "unpin" : "pin", r.key], function (o) { root.done(false, o.toast || ""); root.refresh(); });
      return true;
    }
    if (actionIndex === 2) {
      run([root.bin, "delete", r.key], function (o) { root.done(false, o.toast || "Deleted"); root.refresh(); });
      return true;
    }
    return false;
  }

  function reset() {
    rows = [];
    error = "";
    busy = false;
    seq++;
    Quickshell.execDetached([root.bin, "purge-previews"]);
  }
}
