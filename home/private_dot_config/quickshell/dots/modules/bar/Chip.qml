import QtQuick
import "../theme"

// One clickable spot inside a pill: content in a Row, a neutral hover wash, a press wash.
// Never recolours for status; the content carries the colour and the shape.
Item {
  id: chip

  default property alias content: row.data
  property int padX: Theme.space.m
  property int chipHeight: Theme.space.xxxl + Theme.space.xxl   // the full 40 pill, so a Row centres it
  property int washHeight: Theme.space.xxxl + Theme.space.s   // 28: the hover wash inside it
  property bool hoverable: true
  property bool clickable: true
  property int spacing: Theme.space.s + 2
  readonly property bool hovered: mouse.containsMouse

  signal clicked(var button)

  implicitWidth: row.implicitWidth + 2 * padX
  implicitHeight: chipHeight
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: (chip.height - chip.washHeight) / 2
    anchors.bottomMargin: anchors.topMargin
    radius: Theme.radius.pill
    color: Qt.alpha(Theme.color.fg, mouse.pressed ? Theme.alpha.pressed : Theme.alpha.hover)
    visible: chip.hoverable && chip.clickable && (chip.hovered || mouse.pressed)
  }

  Row {
    id: row
    x: chip.padX
    height: parent.height
    spacing: chip.spacing
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: chip.clickable
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: m => chip.clicked(m.button)
  }
}
