import QtQuick
import "../../theme"
import "../../common"
import ".."

// What I am working on, clipped at 170, and the detour chip when I have left it
// (STUB: no detour source yet, so the chip shows only when `detour` is set).
Row {
  id: root

  property string task: ""
  property string detour: ""
  property int maxText: 170          // BarView shrinks it on a narrow screen

  height: parent ? parent.height : Theme.space.xxxl
  spacing: Theme.space.m

  DText {
    objectName: "taskText"
    anchors.verticalCenter: parent.verticalCenter
    visible: root.task !== "" && root.maxText >= 48
    role: "bodyS"
    elide: Text.ElideRight
    width: Math.min(implicitWidth, root.maxText)
    text: root.task
  }

  Rectangle {
    objectName: "detour"
    anchors.verticalCenter: parent.verticalCenter
    visible: root.detour !== ""
    height: Theme.space.xxxl + Theme.space.s
    width: detourRow.implicitWidth + 2 * (Theme.space.l + 2)
    radius: Theme.radius.pill
    color: Qt.alpha(Theme.color.waiting, Theme.alpha.wash)

    Row {
      id: detourRow
      x: Theme.space.l + 2
      height: parent.height
      spacing: Theme.space.s + 2

      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        name: "arrow-u-down-left"
        box: 14
        color: Theme.color.waiting
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        role: "bodyS"
        text: "Detour"
        color: Theme.color.waiting
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        role: "bodyS"
        mono: true
        text: root.detour
        color: Theme.color.waiting
      }
    }
  }
}
