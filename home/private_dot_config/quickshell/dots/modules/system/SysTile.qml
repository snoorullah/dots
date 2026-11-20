import QtQuick
import "../theme"

// One quick tile: the body toggles, the 32 px arrow (or a right click) opens the menu.
Item {
  id: root

  property string icon: ""
  property string name: ""
  property string sub: ""
  property bool on: false
  property bool avail: true
  property bool selected: false
  signal toggled()
  signal opened()

  implicitHeight: 48

  readonly property color fg: on ? Theme.color.accentFg : Theme.color.fg

  Rectangle {
    anchors.fill: parent
    anchors.margins: -4
    radius: Theme.radius.card
    color: "transparent"
    border.width: 2
    border.color: Theme.color.fg
    visible: root.selected
  }
  Rectangle {
    id: body
    anchors.fill: parent
    radius: 12
    color: root.on ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.08)
    clip: true
    opacity: root.avail ? 1 : 0.5

    MouseArea {
      id: main
      anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: caret.left }
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: mouse => { if (mouse.button === Qt.RightButton) root.opened(); else root.toggled(); }
    }
    Row {
      anchors { left: parent.left; leftMargin: Theme.space.xl - 2; verticalCenter: parent.verticalCenter }
      spacing: Theme.space.m
      width: caret.x - Theme.space.xl
      SIcon { key: root.icon; boardSize: 17; color: root.fg; anchors.verticalCenter: parent.verticalCenter }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 17 - Theme.space.m
        SText { width: parent.width; text: root.name; font.weight: 500; color: root.fg; elide: Text.ElideRight; lineHeight: 15 }
        SText { width: parent.width; text: root.sub; color: root.fg; opacity: 0.8; elide: Text.ElideRight; lineHeight: 15; visible: root.sub !== "" }
      }
    }
    Rectangle {
      id: caret
      anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
      width: 32
      color: "transparent"
      Rectangle {
        width: 1; height: parent.height
        color: root.on ? Qt.alpha(Theme.color.accentFg, 0.25) : Theme.color.outlineVariant
      }
      SIcon { anchors.centerIn: parent; key: "caret"; boardSize: 14; color: root.fg }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
      }
    }
  }
}
