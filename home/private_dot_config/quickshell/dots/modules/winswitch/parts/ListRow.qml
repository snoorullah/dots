pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The list layout's row: 44 tall, glyph, title with the hit highlighted, ticket, profile, workspace.
Rectangle {
  id: root
  property var c: ({})
  signal picked()
  readonly property bool sel: !!c.selected
  height: 44
  radius: Theme.radius.row
  opacity: c.dim ? 0.5 : (c.faded ? 0.4 : 1)
  color: sel ? Qt.alpha(Theme.color.accent, Theme.alpha.rest + 0.06) : "transparent"
  border.width: 1
  border.color: sel ? Theme.color.accent : "transparent"
  Row {
    anchors.fill: parent
    anchors.leftMargin: Theme.space.xl
    anchors.rightMargin: Theme.space.xl
    spacing: Theme.space.xl
    Gly { anchors.verticalCenter: parent.verticalCenter; name: root.c.icon || "squares-four"; box: 20; color: root.sel ? Theme.color.accent : Theme.color.fgDim }
    Item {
      objectName: "winTitle"
      property string text: root.c.title || ""
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 20 - 3 * Theme.space.xl - tags.width - wsBox.width
      height: 18
      clip: true
      Row {
        DText { text: root.c.pre || ""; role: "bodyS" }
        DText { visible: !!root.c.hit; text: root.c.hit || ""; role: "bodyS"; color: Theme.color.accent }
        DText { text: root.c.post || ""; role: "bodyS" }
      }
    }
    Row {
      id: tags
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.m
      Tag { visible: !!root.c.badge; text: root.c.badge || ""; tone: "light"; icon: "tabs" }
      Tag { visible: !!root.c.ticket; text: root.c.ticket || ""; tone: "accent"; icon: "ticket" }
      Tag { text: root.c.profile || ""; tone: "dim" }
    }
    Rectangle {
      id: wsBox
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(20, wsText.implicitWidth + 8); height: 18; radius: 6
      color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant
      Cap { id: wsText; anchors.centerIn: parent; text: root.c.ws || "" }
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.picked() }
}
