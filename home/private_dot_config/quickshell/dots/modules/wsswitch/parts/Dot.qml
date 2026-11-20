import QtQuick
import "../../theme"
import "../../common"

// One window's state. needs = the waiting circle from StatusMark (amber, always a shape),
// active = the focused window, accent filled; running = a quiet filled dot. No pulse.
Item {
  id: root
  property string kind: "running"
  objectName: "stateDot"
  implicitWidth: 12
  implicitHeight: 12
  StatusMark { visible: root.kind === "needs"; anchors.centerIn: parent; level: "waiting"; size: 12 }
  Rectangle {
    visible: root.kind !== "needs"
    anchors.centerIn: parent
    width: 9; height: 9; radius: 5
    color: root.kind === "active" ? Theme.color.accent : Theme.color.fgFaint
    border.width: 1
    border.color: root.kind === "active" ? Theme.color.accent : Theme.color.outline
  }
}
