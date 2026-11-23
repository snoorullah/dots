import QtQuick
import qs.modules.theme
import qs.modules.common

// Filter chip: 26 px pill. On = inverted (fg fill, bg text), never green.
Item {
  id: c
  property string text: ""
  property string icon: ""
  property bool on: false
  property bool focused: false
  signal clicked()

  implicitHeight: 26
  implicitWidth: row.implicitWidth + 20

  Rectangle {
    anchors.fill: parent
    radius: 16
    color: c.on ? Theme.color.fg : "transparent"
    border.width: 1
    border.color: c.on ? Theme.color.fg : Theme.color.outline
  }
  Rectangle {
    anchors.fill: parent
    radius: 16
    color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
    visible: ma.containsMouse && !c.on
  }
  FocusRing { focused: c.focused; radius: 18 }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    Icon { visible: c.icon !== ""; name: c.icon; size: 14; color: c.on ? Theme.color.bg : Theme.color.fg; anchors.verticalCenter: parent.verticalCenter }
    DText { text: c.text; role: "bodyS"; color: c.on ? Theme.color.bg : Theme.color.fg; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.clicked() }
}
