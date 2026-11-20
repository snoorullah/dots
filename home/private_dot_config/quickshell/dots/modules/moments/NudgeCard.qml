import Quickshell
import QtQuick
import "../theme"
import "../common"
import "js/Moments.js" as M

// The board's waiting toast face: title, amber age, what it is waiting on, Jump there and
// Dismiss. Jump there runs `dots-jump <ref>` (local); with no ref it is disabled. It fades
// in over motion.fade when `shown` turns true (arrivals fade, they do not slide).
Rectangle {
  id: card

  property string title: ""
  property string age: ""
  property string detail: ""
  property string ref: ""
  property bool shown: true
  property bool animate: true

  signal dismissed()
  signal jumped()

  readonly property var jumpArgv: M.jumpArgv({ ref: card.ref })

  implicitWidth: 380
  implicitHeight: col.implicitHeight + 24
  height: implicitHeight
  radius: Theme.radius.row
  color: Theme.color.surfaceContainer
  border.width: 1
  border.color: Theme.color.outline
  opacity: shown ? 1 : 0
  visible: opacity > 0

  Behavior on opacity {
    enabled: card.animate
    NumberAnimation { duration: Theme.motion.fade; easing.type: Theme.motion.easeOut }
  }

  function jump() {
    if (!card.jumpArgv) return false;
    Quickshell.execDetached(card.jumpArgv);
    card.jumped();
    return true;
  }

  Column {
    id: col
    x: 14
    y: 12
    width: parent.width - 28
    spacing: Theme.space.m

    Item {
      width: parent.width
      height: Theme.font.line.body
      DText {
        anchors.left: parent.left
        anchors.right: ageText.left
        anchors.rightMargin: Theme.space.xl
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        text: card.title
      }
      DText {
        id: ageText
        anchors.right: parent.right
        color: Theme.color.waiting
        text: card.age
      }
    }
    DText {
      width: parent.width
      role: "bodyS"
      dim: true
      elide: Text.ElideRight
      text: card.detail
    }
    Row {
      spacing: 6
      MButton {
        objectName: "nudgeJump"
        kind: "primary"
        text: "Jump there"
        icon: MomentIcons.jump
        usable: card.jumpArgv !== null
        tip: "no ticket to jump to"
        onClicked: card.jump()
      }
      MButton {
        objectName: "nudgeDismiss"
        kind: "outline"
        text: "Dismiss"
        icon: MomentIcons.dismiss
        onClicked: card.dismissed()
      }
    }
  }
}
