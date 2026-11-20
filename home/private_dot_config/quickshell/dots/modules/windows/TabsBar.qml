pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../wsswitch/parts"

// The tab strip of the focused window's Hyprland group: one tab per member, the active one lit
// with a close mark, the group size on the right. `m` comes from js/Groups.js build().
Rectangle {
  id: root

  property var m: ({ show: false, tabs: [], n: 0, text: "" })
  signal picked(string addr)
  signal closed(string addr)

  implicitWidth: 640
  implicitHeight: 40
  width: implicitWidth
  height: implicitHeight
  radius: Theme.radius.row
  color: Qt.alpha(Theme.color.surface, Theme.alpha.panel)
  border.width: 1
  border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)

  Row {
    id: strip
    x: Theme.space.m
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s
    Repeater {
      model: root.m.tabs
      Rectangle {
        id: tab
        required property var modelData
        objectName: "tab"
        height: 30
        width: Math.min(tabRow.implicitWidth + 2 * Theme.space.l, 200)
        radius: Theme.radius.chip + 2
        color: tab.modelData.active ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent")
        border.width: tab.modelData.active ? 1 : 0
        border.color: Theme.color.accent
        Row {
          id: tabRow
          anchors.verticalCenter: parent.verticalCenter
          x: Theme.space.l
          spacing: Theme.space.m
          Chip { anchors.verticalCenter: parent.verticalCenter; box: 20; glyph: 12; icon: tab.modelData.icon; tone: tab.modelData.active ? Theme.color.accent : Theme.color.fgDim }
          DText { objectName: "tabTitle"; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, 130); text: tab.modelData.title; role: "bodyS"; elide: Text.ElideRight; textFormat: Text.PlainText; dim: !tab.modelData.active }
          Item {
            objectName: "tabClose"
            visible: tab.modelData.active
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? 16 : 0
            height: 16
            Gly { anchors.centerIn: parent; name: "x"; box: 12; color: Theme.color.fgDim }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closed(tab.modelData.addr) }
          }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; z: -1; onClicked: root.picked(tab.modelData.addr) }
      }
    }
  }
  Cap { objectName: "groupCount"; anchors.right: parent.right; anchors.rightMargin: Theme.space.xl; anchors.verticalCenter: parent.verticalCenter; text: root.m.text }
}
