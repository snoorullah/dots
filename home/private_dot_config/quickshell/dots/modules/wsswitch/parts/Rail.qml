pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The profile list beside the tree (narrow, icon + key) or beside the map (wide, name + sub).
Column {
  id: root
  property var profiles: []
  property bool wide: false
  signal picked(string name)
  spacing: wide ? 4 : Theme.space.m
  topPadding: wide ? 10 : 12

  Repeater {
    model: root.profiles
    Rectangle {
      id: b
      required property var modelData
      objectName: "railBtn"
      x: root.wide ? 10 : (root.width - width) / 2
      width: root.wide ? root.width - 20 : 56
      height: root.wide ? 54 : 52
      radius: 12
      opacity: b.modelData.dim ? 0.4 : 1
      color: b.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : Theme.color.bg)
      border.width: 1
      border.color: b.modelData.on ? Theme.color.accent : Theme.color.outlineVariant

      // narrow: icon over key
      Column {
        visible: !root.wide
        anchors.centerIn: parent
        spacing: 1
        Gly { anchors.horizontalCenter: parent.horizontalCenter; name: b.modelData.icon; box: 22; color: b.modelData.on ? Theme.color.fg : Theme.color.fgDim }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: b.modelData.key }
      }
      // wide: icon tile, name + sub, badge, key
      Row {
        visible: root.wide
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 32; height: 32; radius: 9
          color: b.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Qt.alpha(Theme.color.fg, Theme.alpha.rest + 0.02)
          Gly { anchors.centerIn: parent; name: b.modelData.icon; box: 18; color: b.modelData.on ? Theme.color.accent : Theme.color.fgDim }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 32 - 10 - keyCap.width - (nb.visible ? nb.width + 10 : 0) - 10
          DText { objectName: "railName"; width: parent.width; text: b.modelData.name; role: "bodyS"; font.weight: Font.DemiBold; elide: Text.ElideRight }
          Cap { objectName: "railSub"; width: parent.width; text: b.modelData.sub; elide: Text.ElideRight }
        }
        Badge { id: nb; anchors.verticalCenter: parent.verticalCenter; count: b.modelData.needs; h: 20 }
        Cap { id: keyCap; anchors.verticalCenter: parent.verticalCenter; text: b.modelData.key }
      }
      Badge {
        visible: !root.wide && b.modelData.needs > 0
        count: b.modelData.needs
        h: 18
        x: parent.width - width + 4
        y: -4
      }
      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(b.modelData.name)
      }
    }
  }
}
