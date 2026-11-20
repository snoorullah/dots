import QtQuick
import qs.modules.theme
import qs.modules.common

// Card heading: icon + 16 px title, as the board's h2.
Row {
  id: h
  property string text: ""
  property string icon: ""
  spacing: 8
  Icon { visible: h.icon !== ""; name: h.icon; size: 18; color: Theme.color.fg; anchors.verticalCenter: parent.verticalCenter }
  DText { text: h.text; role: "title"; anchors.verticalCenter: parent.verticalCenter }
}
