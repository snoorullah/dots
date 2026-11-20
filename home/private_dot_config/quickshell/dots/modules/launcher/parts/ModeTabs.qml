pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Board row 2 (40 px): one chip per mode with its prefix. The active chip is raised, the rest are dim.
Item {
  id: root

  required property var st
  implicitHeight: 40

  Row {
    x: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Repeater {
      model: root.st.tabs
      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property bool on: root.st.modeId === modelData.providerId
        objectName: "tab"
        property string tabId: modelData.providerId
        property bool active: on
        height: 28
        width: lab.implicitWidth + 20
        radius: 8
        color: on ? Theme.color.surfaceContainerHigh : "transparent"

        Row {
          id: lab
          anchors.centerIn: parent
          spacing: 6
          Gly { name: chip.modelData.icon; box: 14; color: chip.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          DText { text: chip.modelData.name; role: "bodyS"; font.pixelSize: Theme.font.size.caption; color: chip.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          DText { visible: chip.modelData.prefix !== ""; text: chip.modelData.prefix; role: "bodyS"; font.pixelSize: Theme.font.size.caption; dim: true; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; onClicked: root.st.setMode(chip.modelData.providerId) }
      }
    }
  }
}
