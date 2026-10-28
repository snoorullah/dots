import QtQuick
import "../theme"
import "../common"

// An icon and a level you can drag or click. `moved` fires with 0..1 while dragging.
Item {
  id: root

  property string icon: ""
  property real value: 0
  property bool available: true

  signal moved(real fraction)

  implicitHeight: 28
  visible: available

  Icon {
    id: glyph
    anchors.verticalCenter: parent.verticalCenter
    text: root.icon
    size: Theme.font.size.title
  }
  Item {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    x: glyph.implicitWidth + Theme.space.xl
    width: parent.width - x - 38
    height: 18

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 4
      radius: 2
      color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * Math.max(0, Math.min(1, root.value))
      height: 4
      radius: 2
      color: Theme.color.fg
    }
    MouseArea {
      anchors.fill: parent
      onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / width)))
      onPositionChanged: mouse => { if (pressed) root.moved(Math.max(0, Math.min(1, mouse.x / width))); }
    }
  }
  DText {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    mono: true
    text: Math.round(root.value * 100) + "%"
    role: "bodyS"
  }
}
