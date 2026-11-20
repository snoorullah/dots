pragma Singleton
import QtQuick

// Icon KEY (what js/Session.js returns, an away key or a session button id) to Phosphor
// name. Names live here as literals so tools/gen-phosphor-qml.py finds them.
QtObject {
  readonly property var icons: ({
    salah: "mosque", washroom: "toilet", walk: "person-simple-walk", meal: "fork-knife", meeting: "users",
    lock: "lock", logout: "sign-out", suspend: "moon", reboot: "arrow-clockwise", poweroff: "power",
    backup: "hard-drives", close: "x", fallback: "clock"
  })

  // The dots Icons font draws a glyph at about 0.64 of its pixel size, while the boards give
  // SVG pixel sizes (same constant as modules/system/SysIcons.qml).
  readonly property real scale: 1.5
  function px(boardSize) { return Math.round(boardSize * scale) }

  function name(key) { return icons[key] !== undefined ? icons[key] : icons.fallback }
}
