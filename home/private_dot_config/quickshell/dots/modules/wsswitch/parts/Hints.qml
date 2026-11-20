pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../barpop"

// The footer line of keys: [{k, l}] as keycap + label.
Flow {
  id: root
  property var items: []
  spacing: Theme.space.xl
  Repeater {
    model: root.items
    Row {
      id: hint
      required property var modelData
      objectName: "hint"
      spacing: Theme.space.s + 2
      Keycap { anchors.verticalCenter: parent.verticalCenter; text: hint.modelData.k }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: hint.modelData.l }
    }
  }
}
