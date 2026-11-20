import QtQuick
import "../../theme"
import "../../common"
import ".."

// A running focus block: "Focus 24m" left, in the accent (selection/progress, never a status).
// Minutes only, so nothing on the bar ticks. Hidden when no block runs. Click: the Time tab.
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
    text: "Focus " + root.remaining
  }
}
