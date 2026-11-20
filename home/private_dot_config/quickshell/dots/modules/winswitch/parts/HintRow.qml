import QtQuick
import "../../theme"
import "../../barpop"

// Key hints at the right of the header: a key in a box, then what it does.
Row {
  id: root
  property var items: []
  spacing: 14
  Repeater {
    model: root.items
    Row {
      id: h
      required property var modelData
      objectName: "hint"
      spacing: 6
      Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: k.implicitWidth + 12; height: 20; radius: 6
        color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant
        Cap { id: k; anchors.centerIn: parent; text: h.modelData.k; dim: false }
      }
      Cap { anchors.verticalCenter: parent ? parent.verticalCenter : undefined; text: h.modelData.t }
    }
  }
}
