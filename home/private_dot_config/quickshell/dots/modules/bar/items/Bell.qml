import QtQuick
import "../../theme"
import ".."

// Notifications and the system panel behind one bell. A dot says something is new (no
// count). Do-not-disturb swaps in the slashed bell. Click opens the centre.
Chip {
  id: root

  property bool dot: false
  property bool quiet: false
  signal activated(string popout, real x)

  objectName: "bell"
  padX: Theme.space.m

  Glyph {
    anchors.verticalCenter: parent.verticalCenter
    name: root.quiet ? "bell-slash" : "bell"
    active: root.quiet
    box: 16
    color: Qt.alpha(Theme.color.fg, 0.85)
  }

  // the ring is the pill ground, so the dot reads as cut out of the bell
  Rectangle {
    objectName: "bellDot"
    visible: root.dot
    x: root.padX + 16 - 3
    y: (root.height - root.washHeight) / 2 + Theme.space.s - 1
    width: 6
    height: 6
    radius: 3
    color: Theme.color.accent
    border.width: 1.5
    border.color: Theme.color.bg
  }

  onClicked: b => root.activated("center", root.mapToItem(null, root.width / 2, 0).x)
}
