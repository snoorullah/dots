import QtQuick
import "../../theme"

// One action under the preview. Index 0 is the primary (accent fill, Enter); the others are secondary
// (raised, outlined); the one Ctrl+J/K picked has an accent outline.
Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  property bool picked: false
  property bool disabled: false
  signal clicked()

  height: 28
  width: txt.implicitWidth + 20
  radius: 8
  opacity: disabled ? 0.4 : 1
  color: primary ? Theme.color.accent : Theme.color.surfaceContainer
  border.width: primary ? 0 : 1
  border.color: picked ? Theme.color.accent : Qt.alpha(Theme.color.outline, Theme.alpha.divider)

  Text {
    id: txt
    anchors.centerIn: parent
    text: root.label
    color: root.primary ? Theme.color.accentFg : Theme.color.fg
    font.family: Theme.font.mono
    font.pixelSize: Theme.font.size.caption
    font.weight: root.primary ? Theme.font.weight.label : Theme.font.weight.body
    renderType: Text.NativeRendering
  }
  MouseArea { anchors.fill: parent; enabled: !root.disabled; onClicked: root.clicked() }
}
