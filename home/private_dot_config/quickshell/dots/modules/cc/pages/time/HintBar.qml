pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// The keys that work here: [key, label] pairs, key in mono on a raised chip.
Row {
  id: h
  property var hints: []
  spacing: 14
  objectName: "timeHints"
  clip: true
  Repeater {
    model: h.hints
    Row {
      id: hh
      required property var modelData
      spacing: 6
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: kt.implicitWidth + 10
        height: 20
        radius: Theme.radius.chip
        color: Theme.color.surfaceContainer
        border.width: 1
        border.color: Theme.color.outlineVariant
        DText { id: kt; anchors.centerIn: parent; text: hh.modelData[0]; role: "caption"; mono: true; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.fg }
      }
      DText { anchors.verticalCenter: parent.verticalCenter; text: hh.modelData[1]; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
    }
  }
}
