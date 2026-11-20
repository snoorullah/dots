pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../common"
import "js/Menus.js" as Menus

// The session card: lock, log out, suspend, reboot, shut down, back up then shut down.
// `buttons` comes from Menus.sessionButtons; a blocker (a long job running) greys the
// destructive ones and says why underneath.
Item {
  id: root

  property var buttons: []
  property string blocker: ""
  signal activated(var act)
  signal closed()

  implicitHeight: head.height + grid.height + (blockNote.visible ? blockNote.height + Theme.space.xl - 2 : 0) + 2 * (Theme.space.xl - 2)

  Row {
    id: head
    width: parent.width
    height: 28
    DText { width: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; text: "Session"; role: "caption" }
    Item {
      width: 28; height: 28
      SIcon { anchors.centerIn: parent; key: "x"; boardSize: 16; color: Theme.color.fgDim }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closed() }
    }
  }

  GridLayout {
    id: grid
    anchors { top: head.bottom; topMargin: Theme.space.xl - 2 }
    width: parent.width
    columns: 2
    columnSpacing: 6
    rowSpacing: 6
    uniformCellWidths: true
    Repeater {
      model: root.buttons
      Item {
        id: sb
        required property var modelData
        objectName: "sess-" + modelData.id
        readonly property bool live: !Menus.disabled(modelData.act)
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.max(58, texts.implicitHeight + 16)
        opacity: live ? 1 : 0.45
        Rectangle {
          anchors.fill: parent
          radius: 12
          color: Qt.alpha(Theme.color.fg, sbArea.containsMouse && sb.live ? 0.09 : 0.05)
          border.width: 1
          border.color: Qt.alpha(Theme.color.fg, 0.12)
        }
        Row {
          anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
          spacing: 10
          SIcon { key: sb.modelData.icon; boardSize: 20; anchors.verticalCenter: parent.verticalCenter
                 color: sb.modelData.danger ? Theme.color.failed : Theme.color.fg }
          Column {
            id: texts
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 20 - 10
            SText { width: parent.width; text: sb.modelData.title; font.weight: 700; wrapMode: Text.WordWrap
                    color: sb.modelData.danger ? Theme.color.failed : Theme.color.fg }
            SText { width: parent.width; text: sb.modelData.sub; dim: true; wrapMode: Text.WordWrap }
          }
        }
        MouseArea {
          id: sbArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: sb.live ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (sb.live) root.activated(sb.modelData.act)
        }
        Tip { anchors.horizontalCenter: parent.horizontalCenter; y: -height; text: sb.modelData.act.why || ""; shown: sbArea.containsMouse && !sb.live }
      }
    }
  }

  SText {
    id: blockNote
    anchors { top: grid.bottom; topMargin: Theme.space.xl - 2 }
    width: parent.width
    visible: root.blocker !== ""
    text: "Blocked while " + root.blocker + "."
    dim: true
    wrapMode: Text.WordWrap
  }
}
