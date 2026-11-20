import QtQuick
import "../theme"

// The small text button of the boards (28 px, 8 px radius). `primary` is the accent
// fill; `quiet` has no border (the settings link at the end of a menu). A disabled
// button stays visible, dims, and says why on hover.
Item {
  id: root

  property string text: ""
  property bool primary: false
  property bool quiet: false
  property bool danger: false
  property bool live: true
  property string why: ""
  property int pad: Theme.space.xl - 2
  signal clicked()

  implicitWidth: label.implicitWidth + 2 * pad
  implicitHeight: 28
  opacity: live ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.chip + 2
    color: root.primary ? Theme.color.accent
         : area.containsMouse && root.live ? Theme.color.surfaceContainerHigh : Theme.color.surfaceContainer
    border.width: root.primary || root.quiet ? 0 : 1
    border.color: Theme.color.outlineVariant
    visible: !root.quiet || area.containsMouse
  }
  SText {
    id: label
    anchors.centerIn: parent
    text: root.text
    font.weight: root.primary ? 600 : 400
    color: root.primary ? Theme.color.accentFg : root.danger ? Theme.color.failed : root.quiet ? Theme.color.fgDim : Theme.color.fg
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.live ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.live) root.clicked()
  }
  Tip {
    y: -height - 4
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.why
    shown: area.containsMouse && !root.live
  }
}
