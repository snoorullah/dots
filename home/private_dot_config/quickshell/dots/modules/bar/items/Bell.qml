import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// Notifications. Nothing held and nothing waiting -> zero width. Do-not-disturb is a
// state I hold open, so it takes the accent (filled bell + accent tint); so does a running
// focus block, which quiets toasts. Amber is reserved for "someone waits on me".
// If another daemon owns the notification bus
// the shell does not claim it and this shows a hollow "?" instead.
// Twins: `qs ipc call dots.notif toggle` / `dnd`.
Chip {
  id: chip

  property var notifs: null
  readonly property bool dnd: notifs ? notifs.quiet : false     // do-not-disturb, or a focus block
  readonly property int count: notifs ? notifs.count : 0
  readonly property bool held: notifs ? notifs.held : false

  shown: Lamp.on || dnd || count > 0 || held
  wash: dnd || Lamp.on
  tint: Theme.color.accent

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      visible: !chip.held
      name: chip.dnd ? "bell-slash" : "bell"
      active: chip.dnd || Lamp.on
      size: Theme.font.size.title
      color: chip.dnd || Lamp.on ? Theme.color.accent : Theme.color.fg
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
