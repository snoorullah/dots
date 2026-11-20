import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// One menu row: glyph, label, the key combo that does the same, and the letter key boxed.
Rectangle {
  id: root
  property var r: ({ label: "", icon: "gear", key: "", combo: "", hot: false, selected: false })
  signal clicked()

  height: 32
  radius: 8
  color: r.hot ? Qt.alpha(Theme.color.accent, Theme.alpha.pressed) : (r.selected ? Qt.alpha(Theme.color.accent, Theme.alpha.on - 0.06) : "transparent")

  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.m
    anchors.rightMargin: Theme.space.m
    spacing: 10
    Gly { anchors.verticalCenter: parent.verticalCenter; name: root.r.icon; box: 18; color: (root.r.hot || root.r.selected) ? Theme.color.accent : Theme.color.fgDim }
    DText { objectName: "rowLabel"; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 18 - combo.implicitWidth - keyBox.width - 3 * 10; elide: Text.ElideRight; text: root.r.label; role: "bodyS" }
    Cap { id: combo; anchors.verticalCenter: parent.verticalCenter; text: root.r.combo; dim: !root.r.hot; color: root.r.hot ? Theme.color.accent : Theme.color.fgDim }
    Rectangle {
      id: keyBox
      anchors.verticalCenter: parent.verticalCenter
      width: 20; height: 20; radius: 5
      color: "transparent"; border.width: root.r.key !== "" ? 1 : 0; border.color: Theme.color.outlineVariant
      Cap { anchors.centerIn: parent; text: root.r.key; dim: false; font.underline: true }
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
