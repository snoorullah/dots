import Quickshell
import QtQuick
import ".."
import "../../common"
import "../../../services"

// Date and time. Click opens the calendar, middle-click the media popout (only when a
// player exists). Twins: `qs ipc call dots.bar calendar` / `media`.
Chip {
  id: chip

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  DText {
    anchors.verticalCenter: parent.verticalCenter
    mono: true
    text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm")
  }

  onClicked: button => {
    if (button === Qt.MiddleButton) { if (Mpris.present) chip.popout("media"); }
    else chip.popout("calendar");
  }
}
