pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ~/.config/dots-work/work.conf (hand-written, never in the repo). The shell reads only
// the keys it needs and never a secret: ERP_KEY_FILE is a path, and this does not open it.
Singleton {
  id: root

  property var values: ({})
  readonly property bool loaded: Object.keys(values).length > 0

  function get(key, fallback) {
    var v = values[key];
    return (v === undefined || v === "") ? fallback : v;
  }

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/dots-work/work.conf"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var out = {};
      var lines = text().split("\n");
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([A-Z][A-Z0-9_]*)=(.*?)\s*(?:#.*)?$/);
        if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
      }
      root.values = out;
    }
    onLoadFailed: root.values = ({})
  }
}
