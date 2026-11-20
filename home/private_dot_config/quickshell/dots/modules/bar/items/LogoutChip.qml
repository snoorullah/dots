import QtQuick
import "../../theme"
import "../../common"

// "Logout 03:12": the end of today's session. STUB: no source yet, so it shows only when
// `time` is set. Not clickable.
Rectangle {
  id: root

  property string time: ""

  objectName: "logout"
  visible: time !== ""
  height: Theme.space.xxxl + Theme.space.s
  width: row.implicitWidth + 2 * (Theme.space.l + 2)
  radius: Theme.radius.pill
  color: Theme.color.surfaceContainer

  Row {
    id: row
    x: Theme.space.l + 2
    height: parent.height
    spacing: Theme.space.s + 2

    DText {
      anchors.verticalCenter: parent.verticalCenter
      role: "bodyS"
      dim: true
      text: "Logout"
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      role: "bodyS"
      mono: true
      text: root.time
    }
  }
}
