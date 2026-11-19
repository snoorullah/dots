import Quickshell
import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// dots-ops. All ok -> zero width. warn (something asks for an answer) -> waiting wash,
// wrench and a filled circle. fail (a job failed, nobody is waiting) -> failed wash and
// the filled warning diamond alone (the icon is the shape). Source unreadable -> hollow "?" (Stale).
// Twin: `dots-ops status` in a terminal.
Chip {
  id: chip

  readonly property string level: OpsState.shownLevel

  shown: Lamp.on || OpsState.stale || level !== "ok"
  wash: !OpsState.stale && level !== "ok"
  tint: level === "fail" ? Theme.color.failed : Theme.color.waiting

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      visible: !OpsState.stale
      name: chip.level === "fail" ? "warning-diamond" : "wrench"
      active: chip.level === "fail"   // warning-diamond, filled weight: the icon is the shape
      size: Theme.font.size.title
      color: chip.tint
    }
    StatusMark {
      anchors.verticalCenter: parent.verticalCenter
      visible: !OpsState.stale && chip.level !== "fail"
      level: "waiting"
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      mono: true
      visible: !OpsState.stale
      text: OpsState.text !== "" ? OpsState.text : "ops"
      color: Theme.color.fg   // the shape carries the status, the label stays neutral
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
