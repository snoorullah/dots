import QtQuick
import "../theme"

// A small hover label, drawn inside the card. Used on disabled controls to say why.
Rectangle {
  id: tip
  property string text: ""
  property bool shown: false

  visible: shown && text !== ""
  z: 50
  width: label.implicitWidth + 2 * Theme.space.l
  height: label.implicitHeight + Theme.space.m
  radius: Theme.radius.chip
  color: Theme.color.surfaceContainerHigh
  border.width: 1
  border.color: Theme.color.outlineVariant

  SText {
    id: label
    anchors.centerIn: parent
    text: tip.text
  }
}
