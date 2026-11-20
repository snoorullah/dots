pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Board button: 30 px (28 small), radius row, outline chip; `primary` fills with accent.
// `stub` marks an action whose real effect would write or send somewhere: it renders,
// stays disabled and says why on hover.
Item {
  id: b
  property string text: ""
  property string icon: ""
  property string keyHint: ""
  property bool primary: false
  property bool small: false
  property bool quiet: false       // no fill, no border (tab-like)
  property bool stub: false
  property bool blocked: false     // nothing to act on right now (no link, no pane)
  property string tip: stub ? "read-only for now" : (blocked ? "nothing to open here" : "")
  readonly property bool live: enabled && !stub && !blocked
  readonly property alias hovered: ma.containsMouse
  signal clicked()

  implicitHeight: small ? 28 : 30
  implicitWidth: row.implicitWidth + (small ? 20 : 20)
  opacity: live ? 1 : 0.45
  activeFocusOnTab: true

  Rectangle {
    anchors.fill: parent
    radius: b.small ? Theme.radius.chip + 2 : Theme.radius.row
    color: b.primary ? Theme.color.accent : (b.quiet ? "transparent" : Theme.color.surfaceContainer)
    border.width: (b.primary || b.quiet) ? 0 : 1
    border.color: Theme.color.outlineVariant
  }
  Rectangle {
    anchors.fill: parent
    radius: b.small ? Theme.radius.chip + 2 : Theme.radius.row
    color: Qt.alpha(Theme.color.fg, ma.pressed ? Theme.alpha.pressed : Theme.alpha.hover)
    visible: b.live && (ma.containsMouse || ma.pressed)
  }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: Theme.space.m
    Icon {
      visible: b.icon !== ""
      name: b.icon
      size: 16
      color: b.primary ? Theme.color.accentFg : Theme.color.fg
      anchors.verticalCenter: parent.verticalCenter
    }
    DText {
      text: b.text
      role: "bodyS"
      font.weight: b.primary ? Font.DemiBold : Font.Normal
      color: b.primary ? Theme.color.accentFg : Theme.color.fg
      anchors.verticalCenter: parent.verticalCenter
    }
    DText {
      visible: b.keyHint !== ""
      text: b.keyHint
      role: "caption"
      font.capitalization: Font.MixedCase
      font.letterSpacing: 0
      color: b.primary ? Theme.color.accentFg : Theme.color.fgDim
      opacity: 0.75
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: b.live ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (b.live) b.clicked()
  }
  Keys.onReturnPressed: if (b.live) b.clicked()
  Keys.onSpacePressed: if (b.live) b.clicked()

  // hover tooltip, after a short delay; a plain Rectangle so no Controls dependency
  Timer { id: tipDelay; interval: 350; running: ma.containsMouse && b.tip !== ""; onTriggered: tipBox.show = true }
  Connections { target: ma; function onContainsMouseChanged() { if (!ma.containsMouse) tipBox.show = false } }
  Rectangle {
    id: tipBox
    objectName: "tip"
    property bool show: false
    visible: show && b.tip !== ""
    z: 10
    x: 0
    y: -height - 4
    width: tipText.implicitWidth + 16
    height: 26
    radius: Theme.radius.chip
    color: Theme.color.surfaceContainerHigh
    border.width: 1
    border.color: Theme.color.outline
    DText { id: tipText; anchors.centerIn: parent; text: b.tip; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.fg }
  }
}
