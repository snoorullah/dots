import QtQuick
import "../theme"
import "../common"

// A moments button. kind: primary (accent) | outline | quiet (raised) | amber (chip) | link.
// A button whose real action would write somewhere remote is created with enabled: false and
// a tip: its face renders dimmed and the tip says why on hover.
Item {
  id: root

  property string text: ""
  property string icon: ""
  property string kind: "primary"
  property int iconSize: Theme.font.size.title
  property int corner: 8
  property int padX: 10
  property int gap: 6
  property string tip: "read-only for now"
  property bool usable: true          // false = read-only: dimmed, no click, tip on hover
  signal clicked()

  readonly property color fgc: kind === "primary" ? Theme.color.accentFg
    : kind === "amber" ? Theme.color.waiting
    : kind === "link" ? Theme.color.accent : Theme.color.fg

  implicitHeight: 28
  implicitWidth: row.implicitWidth + 2 * padX
  height: implicitHeight
  width: implicitWidth

  Rectangle {
    id: face
    anchors.fill: parent
    radius: root.corner
    opacity: root.usable ? 1 : 0.5
    color: root.kind === "primary" ? Theme.color.accent
         : root.kind === "amber" ? Qt.alpha(Theme.color.waiting, Theme.alpha.wash)
         : root.kind === "quiet" ? Theme.color.surfaceContainer : "transparent"
    border.width: (root.kind === "outline" || root.kind === "quiet") ? 1 : 0
    border.color: root.kind === "quiet" ? Theme.color.outlineVariant : Theme.color.outline

    Rectangle {
      anchors.fill: parent
      radius: face.radius
      color: Theme.color.fg
      opacity: (mouse.containsMouse && root.usable) ? Theme.alpha.hover : 0
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: root.gap
      Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon !== ""
        name: root.icon
        size: root.iconSize
        color: root.fgc
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        role: "bodyS"
        text: root.text
        color: root.fgc
        font.weight: (root.kind === "outline" || root.kind === "quiet" || root.kind === "link") ? Font.Normal : Font.DemiBold
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.usable) root.clicked()
  }

  Rectangle {
    objectName: "tip"
    visible: !root.usable && mouse.containsMouse && root.tip !== ""
    z: 10
    x: 0
    y: -height - 4
    width: tipText.implicitWidth + 16
    height: tipText.implicitHeight + 8
    radius: Theme.radius.chip
    color: Theme.color.surfaceContainerHigh
    border.width: 1
    border.color: Theme.color.outline
    DText {
      id: tipText
      anchors.centerIn: parent
      role: "bodyS"
      text: root.tip
    }
  }
}
