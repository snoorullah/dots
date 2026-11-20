pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../barpop"

// "Move to" icon buttons, one per profile. The current profile and every profile during
// salah are dimmed and inert.
Row {
  id: root
  property var targets: []
  property string label: "Move to"
  signal pick(string name)
  spacing: 3
  Cap { objectName: "moveLabel"; anchors.verticalCenter: parent.verticalCenter; text: root.label; rightPadding: Theme.space.s; wrapMode: Text.NoWrap }
  Repeater {
    model: root.targets
    Rectangle {
      id: t
      required property var modelData
      objectName: "moveTarget"
      width: 32; height: 32
      radius: 8
      color: ma.containsMouse && !t.modelData.disabled ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : "transparent"
      border.width: 1
      border.color: t.modelData.disabled ? Theme.color.outlineVariant : Theme.color.outline
      opacity: t.modelData.cur ? 0.35 : (t.modelData.disabled ? 0.5 : 1)
      Gly { anchors.centerIn: parent; name: t.modelData.icon; box: 16; color: t.modelData.disabled ? Theme.color.fgDim : Theme.color.accent }
      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: t.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!t.modelData.disabled) root.pick(t.modelData.name)
      }
    }
  }
}
