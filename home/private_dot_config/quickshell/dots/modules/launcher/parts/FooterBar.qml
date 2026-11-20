import QtQuick
import "../../theme"
import "../../common"

// Board row 4 (32 px): status on the left, the key hints on the right.
Item {
  id: root

  required property var st
  property string keys: "Nav N/E move · Enter use · Tab mode · Esc close"
  implicitHeight: 32

  DText { objectName: "status"; x: 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width - hints.width - 40; elide: Text.ElideRight; text: root.st.status; role: "bodyS"; font.pixelSize: Theme.font.size.caption; dim: true }
  DText { id: hints; objectName: "hints"; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: root.keys; role: "bodyS"; font.pixelSize: Theme.font.size.caption; dim: true }
}
