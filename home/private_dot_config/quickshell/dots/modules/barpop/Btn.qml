import QtQuick
import "../theme"
import "../common"

// A small text button (primary | ghost | amber | red | quiet | link). `stub` renders it disabled with the "read-only for now" tooltip:
// its real action would send or write something remotely, which nothing here ever does.
Item {
  id: root

  property string label: ""
  property string kind: "ghost"      // primary | ghost | amber | red | quiet
  property bool stub: false
  property bool enabled2: !stub
  property string tip: "read-only for now"
  property int pad: Theme.space.xl
  signal clicked()

  implicitWidth: txt.implicitWidth + 2 * pad
  implicitHeight: 32
  opacity: enabled2 ? 1 : 0.45

  readonly property color base: kind === "primary" ? Theme.color.accent
    : kind === "amber" ? Theme.color.waiting
    : kind === "red" ? Theme.color.failed
    : (kind === "quiet" || kind === "link") ? "transparent"
    : Theme.color.surfaceContainer

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.chip + 2
    color: root.base
    border.width: root.kind === "ghost" || root.kind === "quiet" ? 1 : 0
    border.color: Theme.color.outlineVariant
  }
  DText {
    id: txt
    anchors.centerIn: parent
    text: root.label
    role: "bodyS"
    font.weight: root.kind === "ghost" || root.kind === "quiet" || root.kind === "link" ? Font.Normal : Font.DemiBold
    color: root.kind === "link" ? Theme.color.accent : (root.kind === "ghost" || root.kind === "quiet" ? Theme.color.fg : Theme.color.accentFg)
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    enabled: true
    cursorShape: root.enabled2 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.enabled2) root.clicked()
  }
  Rectangle {
    objectName: "stubTip"
    visible: root.stub && ma.containsMouse
    z: 50
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.top
    anchors.bottomMargin: Theme.space.s
    width: tipText.implicitWidth + 2 * Theme.space.m
    height: 24
    radius: Theme.radius.chip
    color: Theme.color.surfaceContainerHigh
    border.width: 1
    border.color: Theme.color.outlineVariant
    Cap { id: tipText; anchors.centerIn: parent; text: root.tip; dim: false }
  }
}
