pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import ".."

// Things waiting on me: one symbol and one age each, oldest first, three at most and then
// "+n". Amber is waiting, red is a problem; the shape (the icon) says which thing it is.
// Arrivals fade in over motion.fade; nothing moves otherwise.
Row {
  id: root

  property var shown: []           // [{ id, icon, tone, name, age, popout }]
  property int more: 0
  signal activated(string popout, real x)

  height: parent ? parent.height : Theme.space.xxxl
  spacing: Theme.space.s

  function tone(t) { return t === "failed" ? Theme.color.failed : Theme.color.waiting; }

  Repeater {
    model: root.shown

    Chip {
      id: w
      required property var modelData

      objectName: "wait"
      padX: Theme.space.s
      anchors.verticalCenter: parent.verticalCenter
      opacity: 0
      Component.onCompleted: opacity = 1
      Behavior on opacity { NumberAnimation { duration: Theme.motion.fade } }

      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        name: w.modelData.icon
        box: 16
        color: root.tone(w.modelData.tone)
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        mono: true
        role: "bodyS"
        font.weight: Theme.font.weight.label
        text: w.modelData.age
        color: root.tone(w.modelData.tone)
      }
      onClicked: b => root.activated(w.modelData.popout, w.mapToItem(null, w.width / 2, 0).x)
    }
  }

  DText {
    objectName: "waitMore"
    anchors.verticalCenter: parent.verticalCenter
    visible: root.more > 0
    mono: true
    role: "bodyS"
    dim: true
    text: "+" + root.more
  }
}
