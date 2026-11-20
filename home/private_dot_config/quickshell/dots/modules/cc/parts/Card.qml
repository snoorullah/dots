import QtQuick
import qs.modules.theme

// A board card: panel surface, card radius, content padded 16 to 24.
Rectangle {
  id: c
  property int pad: 20
  default property alias content: body.data
  color: Theme.color.surface
  radius: Theme.radius.card
  implicitHeight: body.implicitHeight + pad * 2
  Item {
    id: body
    anchors.fill: parent
    anchors.margins: c.pad
    implicitHeight: childrenRect.height
  }
}
