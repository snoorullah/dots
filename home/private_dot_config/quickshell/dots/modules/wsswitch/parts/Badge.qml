import QtQuick
import "../../theme"

// The "needs you" count: an amber pill with the number. The count is the shape; amber is
// the same colour the rest of the shell uses for waiting.
Rectangle {
  id: root
  property int count: 0
  property int h: 22
  objectName: "needsBadge"
  visible: count > 0
  implicitWidth: Math.max(h, label.implicitWidth + 12)
  implicitHeight: h
  radius: h / 2
  color: Theme.color.waiting
  Text {
    id: label
    anchors.centerIn: parent
    text: root.count
    color: Theme.color.bg
    font.family: Theme.font.mono
    font.pixelSize: Theme.font.size.caption
    font.weight: Theme.font.weight.label
  }
}
