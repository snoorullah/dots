import QtQuick
import "../theme"

// A thin level bar. The fill is the neutral foreground, not an accent: a level is not news.
Item {
  property real value: 0
  property bool muted: false

  implicitHeight: 4

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
  }
  Rectangle {
    width: parent.width * Math.max(0, Math.min(1, parent.value))
    height: parent.height
    radius: height / 2
    color: parent.muted ? Theme.color.fgFaint : Theme.color.fg
  }
}
