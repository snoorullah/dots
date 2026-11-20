import QtQuick
import "../../theme"
import "../../barpop"

// "Moved X to Y." with Undo. Shown for a few seconds after a move.
Rectangle {
  id: root
  property string text: ""
  signal undo()
    visible: text !== ""
  height: visible ? 48 : 0
  radius: Theme.radius.card
  color: Theme.color.surfaceContainer
  border.width: 1
  border.color: Theme.color.outline
  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.xxl
    anchors.rightMargin: Theme.space.m
    spacing: Theme.space.xl
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - undoBtn.width - Theme.space.xl
      text: root.text
      color: Theme.color.fg
      font.family: Theme.font.mono
      font.pixelSize: Theme.font.size.bodyS
      elide: Text.ElideRight
    }
    Btn { id: undoBtn; anchors.verticalCenter: parent.verticalCenter; label: "Undo  z"; kind: "ghost"; onClicked: root.undo() }
  }
}
