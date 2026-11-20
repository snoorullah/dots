import QtQuick
import "../../theme"
import "../../common"
import ".."

// What I am working on (the human ticket, see BarModel.taskText), clipped at 170, and the detour
// chip when I have left it. `detour` is the whole sentence from moments ("Detour 4m · back to
// HD 4412"): the chip adds the icon and the key hint, never a second "Detour".
Row {
  id: root

  property string task: ""
  property string detour: ""
  property string hint: "Super+Alt+B"   // the key that returns (dots.ret back)
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

  // the chip's measured width, so BarView can take it off the room the task text may use
  readonly property real detourWidth: detourChip.visible ? detourChip.width + root.spacing : 0

  Rectangle {
    id: detourChip
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
        objectName: "detourText"
        anchors.verticalCenter: parent.verticalCenter
        role: "bodyS"
        text: root.detour
        color: Theme.color.waiting
      }
      DText {
        objectName: "detourHint"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hint !== ""
        font.pixelSize: Theme.font.size.caption
        text: root.hint
        color: Theme.color.waiting
        opacity: 0.8
      }
    }
  }
}
