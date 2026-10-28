import QtQuick
import "../theme"

// 1 px hairline, outline at alpha.divider, the full slab height minus 8.
Rectangle {
  width: 1
  height: Theme.bar.height - Theme.space.l
  color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
}
