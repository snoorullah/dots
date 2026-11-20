pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Stat card: icon + label, a big number (display role, 40 px), one line of context.
Card {
  id: s
  property string label: ""
  property string icon: ""
  property string value: ""
  property string note: ""
  property bool dim: false
  Column {
    id: col
    width: parent.width
    Row {
      spacing: 6
      Icon { visible: s.icon !== ""; name: s.icon; size: 16; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
      DText { text: s.label; role: "bodyS"; dim: true; anchors.verticalCenter: parent.verticalCenter }
    }
    DText { objectName: "statValue"; text: s.value; role: "display"; opacity: s.dim ? 0.5 : 1 }
    DText { width: parent.width; text: s.note; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
  }
}
