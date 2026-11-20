import QtQuick
import qs.modules.theme
import qs.modules.common

// A small text toggle (Group by, sub-tabs, Where time went): raised surface when on.
Item {
  id: s
  property string text: ""
  property string icon: ""
  property bool on: false
  property int pad: 10
  property int h: 26
  property color onColor: Theme.color.surfaceContainer
  signal clicked()
  implicitHeight: h
  implicitWidth: row.implicitWidth + pad * 2
  Rectangle { anchors.fill: parent; radius: Theme.radius.chip + 2; color: s.on ? s.onColor : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent") }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: 8
    Icon { visible: s.icon !== ""; name: s.icon; size: 18; color: s.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
    DText { text: s.text; role: "bodyS"; color: s.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: s.clicked() }
}
