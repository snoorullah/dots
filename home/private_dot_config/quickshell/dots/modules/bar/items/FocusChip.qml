import QtQuick
import "../../theme"
import "../../common"
import ".."

// A running focus block counting down like a stopwatch: "24:27", in the accent (progress, never a
// status). The only thing on the bar that ticks, and only while a block runs. Click: the Time tab.
Chip {
  id: root

  property string remaining: ""

  objectName: "focus"
  visible: remaining !== ""
  padX: Theme.space.m
  spacing: Theme.space.s

  Glyph {
    anchors.verticalCenter: parent.verticalCenter
    name: "timer"
    box: 14
    color: Theme.color.accent
  }
  DText {
    anchors.verticalCenter: parent.verticalCenter
    role: "bodyS"
    mono: true
    color: Theme.color.accent
    text: root.remaining
  }
}
