pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../barpop"

// Task | Workspace | Profile | All, with the key that picks each.
Rectangle {
  id: root
  property var scopes: []
  signal picked(string id)
  implicitWidth: row.implicitWidth + 6
  height: 40
  radius: 20
  color: Theme.color.bg
  border.width: 1
  border.color: Theme.color.outlineVariant
  Row {
    id: row
    anchors.centerIn: parent
    spacing: 2
    Repeater {
      model: root.scopes
      Rectangle {
        id: s
        required property var modelData
        objectName: "scopePill"
        property string text: modelData.label
        height: 32; radius: 16
        width: lab.implicitWidth + key.implicitWidth + 2 * Theme.space.xl + 6
        color: modelData.on ? Theme.color.accent : "transparent"
        Row {
          anchors.centerIn: parent
          spacing: 6
          Cap { id: lab; text: s.modelData.label; dim: false; color: s.modelData.on ? Theme.color.accentFg : Theme.color.fg }
          Cap { id: key; text: s.modelData.key; dim: false; color: s.modelData.on ? Theme.color.accentFg : Theme.color.unknown }
        }
        MouseArea { anchors.fill: parent; onClicked: root.picked(s.modelData.id) }
      }
    }
  }
}
