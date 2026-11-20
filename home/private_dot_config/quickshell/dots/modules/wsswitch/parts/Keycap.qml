import QtQuick
import "../../theme"
import "../../barpop"

// A key name in a box: the hint footer and the selected row's actions.
Rectangle {
  id: root
  property string text: ""
  implicitWidth: label.implicitWidth + 10
  implicitHeight: 18
  radius: 4
  color: Theme.color.bg
  border.width: 1
  border.color: Theme.color.outlineVariant
  Cap { id: label; anchors.centerIn: parent; text: root.text; dim: false }
}
