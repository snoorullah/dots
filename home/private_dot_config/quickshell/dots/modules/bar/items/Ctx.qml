import Quickshell
import QtQuick
import ".."
import "../../common"
import "../../../services"

// The active taskwarrior context. "none" is nominal -> zero width. Click cycles it.
// Twin: `qs ipc call dots.bar ctx`.
Chip {
  id: chip

  ScriptJson {
    id: src
    command: [Quickshell.env("HOME") + "/.local/bin/waybar-ctx.sh"]
    interval: 30000
  }

  function cycle() {
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/waybar-ctx.sh", "cycle"]);
  }

  shown: Lamp.on || (!src.failed && src.text !== "" && src.text !== "none")

  DText {
    anchors.verticalCenter: parent.verticalCenter
    mono: true
    dim: true
    text: src.text !== "" && src.text !== "none" ? src.text : "ctx"
  }

  onClicked: button => chip.cycle()
}
