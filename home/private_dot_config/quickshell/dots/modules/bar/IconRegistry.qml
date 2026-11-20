import QtQuick
import "../common"

// NEVER INSTANTIATED. The bar picks most glyphs by name at run time (kind -> icon in
// js/BarModel.js), and tools/gen-phosphor-qml.py only sees literals inside Icon blocks.
// Listing them here keeps every name the bar can show in the generated registry.
Item {
  Icon { name: "sparkle" }
  Icon { name: "star" }
  Icon { name: "warning" }
  Icon { name: "git-pull-request" }
  Icon { name: "envelope" }
  Icon { name: "ticket" }
  Icon { name: "circle" }
  Icon { name: "check-circle" }
  Icon { name: "timer" }
  Icon { name: "terminal-window" }
  Icon { name: "globe" }
  Icon { name: "chat-circle" }
  Icon { name: "notebook" }
  Icon { name: "stack" }
  Icon { name: "mosque" }
  Icon { name: "arrow-u-down-left" }
  Icon { name: "bell" }
  Icon { name: "bell-slash" }
}
