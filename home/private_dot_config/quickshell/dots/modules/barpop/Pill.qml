import QtQuick
import "../theme"

// A rounded label. tone: red | amber | dim | accent | none. Colour never stands alone: the
// caller pairs it with text (an age, a count), so this is a tint behind the words.
Item {
  id: root

  property string text: ""
  property string tone: "none"
  property bool bordered: false

  readonly property color tint: tone === "red" ? Theme.color.failed
    : tone === "amber" ? Theme.color.waiting
    : tone === "accent" ? Theme.color.accent
    : Theme.color.fgDim

  implicitWidth: label.implicitWidth + 2 * Theme.space.m
  implicitHeight: 20

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: root.tone === "dim" || root.tone === "none" ? Theme.color.surfaceContainer : Qt.alpha(root.tint, 0.16)
    border.width: root.bordered ? 1 : 0
    border.color: root.tint
  }
  Cap {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.tone === "none" ? Theme.color.fgDim : (root.tone === "dim" ? Theme.color.fgDim : root.tint)
    dim: false
  }
}
