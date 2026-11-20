import QtQuick
import "../../theme"
import "../../common"

// One window's state. needs = the waiting circle from StatusMark (amber, always a shape),
// working = an agent at work, an accent ring with a core; active = the focused window, accent
// filled; running = a quiet filled dot. paused agents draw no dot (the row says so in words).
// Nothing moves.
Item {
  id: root
  property string kind: "running"
  objectName: "stateDot"
  implicitWidth: 12
  implicitHeight: 12
  StatusMark { visible: root.kind === "needs"; anchors.centerIn: parent; level: "waiting"; size: 12 }
  Rectangle {
    visible: root.kind === "working"
    anchors.centerIn: parent
    width: 12; height: 12; radius: 6
    color: "transparent"
    border.width: 2
    border.color: Theme.color.accent
    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.color.accent }
  }
  Rectangle {
    visible: root.kind !== "needs" && root.kind !== "working" && root.kind !== "paused"
    anchors.centerIn: parent
    width: 9; height: 9; radius: 5
    color: root.kind === "active" ? Theme.color.accent : Theme.color.fgFaint
    border.width: 1
    border.color: root.kind === "active" ? Theme.color.accent : Theme.color.outline
  }
}
