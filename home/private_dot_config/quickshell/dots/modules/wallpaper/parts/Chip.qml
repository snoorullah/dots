import QtQuick
import "../../theme"
import "../../barpop"

// A bordered button: a glyph, a label, optional accent when `on`.
Rectangle {
  id: root
  property string icon: ""
  property string text: ""
  property bool on: false
  property bool quiet: false
  signal clicked()
  implicitWidth: row.implicitWidth + 2 * Theme.space.xl
  height: 36
  radius: Theme.radius.row
  color: quiet ? "transparent" : Theme.color.bg
  border.width: 1
  border.color: on ? Theme.color.accent : Theme.color.outlineVariant
  Row {
    id: row
    anchors.centerIn: parent
    spacing: Theme.space.m
    Gly { visible: root.icon !== ""; anchors.verticalCenter: parent.verticalCenter; name: root.icon; box: 16; color: root.on ? Theme.color.accent : Theme.color.fg }
    Cap { anchors.verticalCenter: parent.verticalCenter; text: root.text; dim: false; color: root.on ? Theme.color.accent : Theme.color.fg }
  }
  MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
