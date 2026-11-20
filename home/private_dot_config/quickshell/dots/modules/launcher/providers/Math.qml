import Quickshell
import QtQuick

// Math ("="): arithmetic, units and dates through js/launcher_math.py (own evaluator, `qalc` as a fallback
// when installed). In All it answers only when the text parses, so words never produce a row.
Provider {
  id: root

  providerId: "math"
  name: "Math"
  prefix: "="
  icon: "calculator"
  inAll: true
  allLimit: 1
  allWeight: 1.1
  hint: "Type a sum, a conversion (3 GiB in MiB) or a date (today + 2w)."

  readonly property string py: Qt.resolvedUrl("../js/").toString().replace("file://", "")
  helper: ["python3", root.py + "launcher_math.py", "query"]

  function activate(rowIndex, actionIndex) {
    var r = rows[rowIndex];
    if (!r || actionIndex !== 0) return false;
    Quickshell.execDetached(["wl-copy", r.title]);
    done(true, "Copied " + r.title);
    return true;
  }
}
