pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "js/Menus.js" as Menus

// The right-click menu (window or desktop). A component only: the host decides where to
// place it and what a {op:"wm"} act does. `kind` is "window" or "desktop".
Surface {
  id: root

  property string kind: "window"
  readonly property var spec: Menus.contextMenu(kind)
  signal activated(var act)

  implicitWidth: 240
  implicitHeight: col.height + 12
  width: implicitWidth
  height: implicitHeight
  corner: Theme.radius.card

  Column {
    id: col
    x: 6; y: 6
    width: parent.width - 12

    DText { x: 8; width: parent.width - 16; height: 24; role: "caption"; text: root.spec.title }

    Repeater {
      model: root.spec.rows
      Item {
        id: cr
        required property var modelData
        objectName: modelData.sep ? "ctx-sep" : "ctx-row"
        readonly property bool live: !cr.modelData.sep && !Menus.disabled(modelData.act)
        width: col.width
        height: modelData.sep ? 9 : 28
        opacity: modelData.sep || live ? 1 : 0.45
        Rectangle { visible: !!cr.modelData.sep; x: 8; y: 4; width: parent.width - 16; height: 1; color: Qt.alpha(Theme.color.fg, 0.12) }
        Rectangle { visible: !cr.modelData.sep; anchors.fill: parent; radius: 8; color: Qt.alpha(Theme.color.fg, area.containsMouse && cr.live ? 0.08 : 0) }
        Row {
          visible: !cr.modelData.sep
          anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
          spacing: 10
          SIcon { key: cr.modelData.icon || ""; boardSize: 15; anchors.verticalCenter: parent.verticalCenter
                 color: cr.modelData.danger ? Theme.color.failed : Theme.color.fg }
          SText { width: parent.width - 15 - 10 - hint.implicitWidth - 10; anchors.verticalCenter: parent.verticalCenter
                  text: cr.modelData.label || ""; elide: Text.ElideRight; color: cr.modelData.danger ? Theme.color.failed : Theme.color.fg }
          SText { id: hint; anchors.verticalCenter: parent.verticalCenter; text: cr.modelData.hint || ""; dim: true; mono: true }
        }
        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          enabled: !cr.modelData.sep
          cursorShape: cr.live ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (cr.live) root.activated(cr.modelData.act)
        }
        Tip { x: parent.width - width; y: -height; text: (cr.modelData.act && cr.modelData.act.why) || ""; shown: area.containsMouse && !cr.live && !cr.modelData.sep }
      }
    }
  }
}
