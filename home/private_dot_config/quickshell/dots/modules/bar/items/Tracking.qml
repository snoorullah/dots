import Quickshell
import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// What the time tracker is running. Not tracking -> zero width (idle is nominal).
Chip {
  id: chip

  ScriptJson {
    id: src
    command: [Quickshell.env("HOME") + "/.local/bin/waybar-tracking.sh"]
    interval: 15000
  }

  shown: Lamp.on || (src.cls === "tracking-on" && !src.failed)

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      text: "timer"
      size: Theme.font.size.title
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      text: src.cls === "tracking-on" && src.text !== "" ? src.text : "tracking"
    }
  }

  onClicked: button => {
    var home = Quickshell.env("HOME");
    Quickshell.execDetached(["ghostty", "--class=dots.tasktui", "--gtk-single-instance=false",
      "--config-file=" + home + "/.config/ghostty/popup-tasktui", "-e", home + "/.local/bin/tw-tui"]);
  }
}
