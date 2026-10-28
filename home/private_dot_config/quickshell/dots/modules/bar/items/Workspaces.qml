import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// Workspaces that exist. The focused one gets the neutral hover lift, not a colour:
// where I am is not news.
Chip {
  hoverable: false
  shown: Hypr.workspaces.length > 0

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Repeater {
      model: Hypr.workspaces

      Item {
        id: ws
        required property var modelData
        readonly property bool current: Hypr.activeId === modelData.id

        width: Math.max(20, label.implicitWidth + Theme.space.l)
        height: 20

        Rectangle {
          anchors.fill: parent
          radius: Theme.radius.chip
          color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
          visible: ws.current
        }
        DText {
          id: label
          anchors.centerIn: parent
          text: ws.modelData.name
          mono: true
          role: "bodyS"
          color: ws.current ? Theme.color.fg : Theme.color.fgDim
        }
        MouseArea {
          anchors.fill: parent
          onClicked: Hypr.focus(ws.modelData.id)
        }
      }
    }
  }
}
