import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// Notifications. Nothing held and nothing waiting -> zero width. Do-not-disturb is a
// state I hold open, so it washes amber. If another daemon owns the notification bus
// the shell does not claim it and this shows a hollow "?" instead.
// Twins: `qs ipc call dots.notif toggle` / `dnd`.
Chip {
  id: chip

  property var notifs: null
  readonly property bool dnd: notifs ? notifs.dnd : false
  readonly property int count: notifs ? notifs.count : 0
  readonly property bool held: notifs ? notifs.held : false

  shown: Lamp.on || dnd || count > 0 || held
  wash: dnd || Lamp.on
  tint: Theme.color.amber

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      visible: !chip.held
      text: chip.dnd ? "notifications_off" : "notifications"
      size: Theme.font.size.title
      color: chip.dnd || Lamp.on ? Theme.color.amber : Theme.color.fg
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      mono: true
      visible: !chip.held && chip.count > 0
      text: String(chip.count)
    }
    Stale {
      anchors.verticalCenter: parent.verticalCenter
      on: chip.held
    }
  }

  onClicked: button => {
    if (button === Qt.RightButton) { if (notifs) notifs.dnd = !notifs.dnd; }
    else chip.popout("center");
  }
}
