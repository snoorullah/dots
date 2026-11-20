pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../barpop"

// The popover's profile strip: one icon per profile, the active one filled. Hover for 150 ms
// shows the preview (the window owns the timer); a click picks it.
Row {
  id: root
  property var profiles: []
  signal picked(string name)
  signal hovered(string name)
  spacing: Theme.space.s
  Repeater {
    model: root.profiles
    Rectangle {
      id: b
      required property var modelData
      objectName: "stripBtn"
      width: 36; height: 32
      radius: Theme.radius.row
      opacity: b.modelData.dim ? 0.4 : 1
      color: b.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent")
      border.width: 1
      border.color: b.modelData.on ? Theme.color.accent : "transparent"
      Gly { anchors.centerIn: parent; name: b.modelData.icon; box: 18; color: b.modelData.on ? Theme.color.fg : Theme.color.fgDim }
      Rectangle {
        visible: b.modelData.needs > 0
        width: 8; height: 8; radius: 4
        x: parent.width - 11; y: 3
        color: Theme.color.waiting
        border.width: 1; border.color: Theme.color.surface
      }
      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(b.modelData.name)
        onContainsMouseChanged: root.hovered(containsMouse ? b.modelData.name : "")
      }
    }
  }
}
