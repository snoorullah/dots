import QtQuick
import "../theme"

// A 30 px pill that is also a slider: brightness, volume or mic level. Drag or click
// sets it, right click opens the matching menu. No value is shown when it is unavailable.
Item {
  id: root

  property string icon: ""
  property real value: 0          // 0..100
  property bool avail: true
  signal moved(real fraction)
  signal opened()

  implicitHeight: 30
  opacity: avail ? 1 : 0.45

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.alpha(Theme.color.fg, 0.10)
    clip: true
    Rectangle {
      anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
      width: parent.width * Math.max(0, Math.min(100, root.value)) / 100
      color: Qt.alpha(Theme.color.fg, 0.28)
    }
  }
  Row {
    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    spacing: Theme.space.m
    SIcon { key: root.icon; boardSize: 16; anchors.verticalCenter: parent.verticalCenter }
    SText { text: root.avail ? String(Math.round(root.value)) : "?"; anchors.verticalCenter: parent.verticalCenter; mono: true }
  }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    enabled: root.avail
    onPressed: mouse => { if (mouse.button === Qt.LeftButton) root.moved(Math.max(0, Math.min(1, mouse.x / width))); }
    onPositionChanged: mouse => { if (pressed && (pressedButtons & Qt.LeftButton)) root.moved(Math.max(0, Math.min(1, mouse.x / width))); }
    onClicked: mouse => { if (mouse.button === Qt.RightButton) root.opened(); }
  }
}
