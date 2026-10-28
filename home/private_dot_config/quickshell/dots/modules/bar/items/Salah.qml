import Quickshell
import QtQuick
import ".."
import "../../common"

// Next prayer runway, from the same helper the waybar module runs. Nothing to say
// (no prayer times yet) -> zero width.
Chip {
  id: chip

  ScriptJson {
    id: src
    command: [Quickshell.env("HOME") + "/.local/bin/waybar-salah.sh"]
    interval: 60000
  }

  shown: src.text !== "" && src.text !== "—" && !src.failed

  DText {
    anchors.verticalCenter: parent.verticalCenter
    mono: true
    dim: true
    text: src.text
  }
}
