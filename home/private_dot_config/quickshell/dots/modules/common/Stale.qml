import QtQuick
import "../theme"

// A source that is stale or unavailable renders a hollow circled "?" at fgFaint.
// Same shape as the overview's StaleMark (outline circle, 1 px, "?" at 62 % of the size).
// Outline only so it claims no attention. Never a spinner: waiting is not news.
Item {
  id: root
  property bool on: false
  property int size: Theme.font.size.title

  implicitWidth: on ? size : 0
  implicitHeight: size
  visible: on

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 1
    border.color: Theme.color.fgFaint
  }
  Text {
    anchors.centerIn: parent
    text: "?"
    color: Theme.color.fgFaint
    font.family: Theme.font.mono
    font.pixelSize: Math.round(root.size * 0.62)
    renderType: Text.NativeRendering
  }
}
