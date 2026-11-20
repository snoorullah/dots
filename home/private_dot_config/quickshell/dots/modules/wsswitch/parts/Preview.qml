pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The hover preview: a profile's workspaces as app chips. Appears after 150 ms on a strip
// icon; a click pins the full tree open.
Item {
  id: root
  property var p: null
  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl - 2
    Row {
      width: parent.width
      DText { objectName: "pvName"; id: nm; text: root.p ? root.p.name : ""; role: "headline" }
      Item { width: parent.width - nm.implicitWidth - tot.implicitWidth; height: 1 }
      Cap { id: tot; anchors.verticalCenter: nm.verticalCenter; text: root.p ? root.p.total + " windows" : "" }
    }
    Column {
      width: parent.width
      spacing: Theme.space.m
      Repeater {
        model: root.p ? root.p.ws : []
        Row {
          id: wr
          required property var modelData
          required property int index
          objectName: "pvRow"
          spacing: Theme.space.m
          height: 32
          Cap { width: 80; anchors.verticalCenter: parent.verticalCenter; text: wr.modelData.label; color: wr.index === 0 ? Theme.color.fg : Theme.color.fgDim; elide: Text.ElideRight }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.s
            Repeater {
              model: wr.modelData.wins.slice(0, 5)
              Chip { required property var modelData; box: 28; icon: modelData.icon; tone: modelData.app === "browser" || modelData.app === "editor" ? Theme.color.accent : Theme.color.fgDim }
            }
            Cap { visible: wr.modelData.wins.length > 5; anchors.verticalCenter: parent.verticalCenter; text: "+" + (wr.modelData.wins.length - 5) }
            Cap { visible: wr.modelData.wins.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "empty" }
          }
        }
      }
    }
    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
    Cap { width: parent.width; wrapMode: Text.WordWrap; text: "Preview after 150 ms. Click pins it open." }
  }
}
