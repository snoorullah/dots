import QtQuick
import "../theme"

// Hairline between groups inside a pill: 1 px, 16 high. Rows centre it with their height.
Item {
  width: 1
  height: parent ? parent.height : Theme.space.xxl

  Rectangle {
    width: 1
    height: Theme.space.xxl
    anchors.verticalCenter: parent.verticalCenter
    color: Qt.alpha(Theme.color.fg, Theme.alpha.divider)
  }
}
