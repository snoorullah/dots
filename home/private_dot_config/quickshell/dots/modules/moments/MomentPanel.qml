import QtQuick
import "../theme"
import "../common"

// One moments card: the board's section frame (ground fill, hairline, radius 14, padding 20,
// a title row, 12 between children). Children stack in a column below the title.
Rectangle {
  id: root

  property string title: ""
  property string icon: ""
  property int gap: Theme.space.xl
  default property alias content: body.data
  property alias footer: foot.data     // pinned to the bottom edge (board: margin-top auto)

  implicitWidth: 480
  implicitHeight: col.implicitHeight + (foot.implicitHeight > 0 ? foot.implicitHeight + gap : 0) + 40
  color: Theme.color.bg
  radius: Theme.radius.card
  border.width: 1
  border.color: Theme.color.outlineVariant

  Column {
    id: col
    x: 20
    y: 20
    width: parent.width - 40
    spacing: root.gap

    Row {
      spacing: Theme.space.m
      height: Theme.font.line.title
      Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: Theme.font.size.title
        visible: root.icon !== ""
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        role: "title"
        text: root.title
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: root.gap
    }
  }

  Column {
    id: foot
    x: 20
    width: parent.width - 40
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 20
    spacing: root.gap
  }
}
