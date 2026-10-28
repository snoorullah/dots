import Quickshell
import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// dots-ops. All ok -> zero width. warn (something asks for an answer) -> amber wash.
// fail (a job failed, nobody is waiting) -> red wash. Source unreadable -> hollow "?".
// Twin: `dots-ops status` in a terminal.
Chip {
  id: chip

  readonly property string level: OpsState.shownLevel

  shown: Lamp.on || OpsState.stale || level !== "ok"
  wash: !OpsState.stale && level !== "ok"
  tint: level === "fail" ? Theme.color.red : Theme.color.amber

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      visible: !OpsState.stale
      text: chip.level === "fail" ? "error" : "build"
      size: Theme.font.size.title
      color: chip.tint
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      mono: true
      visible: !OpsState.stale
      text: OpsState.text !== "" ? OpsState.text : "ops"
      color: Qt.tint(chip.tint, Qt.alpha(Theme.color.fg, 0.45))   // AA on its own wash
    }
    Stale {
      anchors.verticalCenter: parent.verticalCenter
      on: OpsState.stale
    }
  }

  onClicked: button => {
    var home = Quickshell.env("HOME");
    if (button === Qt.RightButton) {
      Quickshell.execDetached([home + "/.local/bin/dots-ops", "perf-mode"]);
    } else {
      Quickshell.execDetached(["ghostty", "--class=dots.ops", "--gtk-single-instance=false",
        "--config-file=" + home + "/.config/ghostty/popup", "-e", home + "/.local/bin/dots-ops", "status"]);
    }
  }
}
