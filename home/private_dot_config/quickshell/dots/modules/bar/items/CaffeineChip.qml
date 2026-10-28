import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// Screen kept awake (CaffeineChip: the Caffeine singleton owns the state). Off is nominal -> zero width. Twin: `qs ipc call dots.bar caffeine`.
Chip {
  id: chip

  shown: Lamp.on || Caffeine.on
  wash: true
  tint: Theme.color.amber

  Icon {
    anchors.verticalCenter: parent.verticalCenter
    text: "coffee"
    size: Theme.font.size.title
    color: Theme.color.amber
  }

  onClicked: button => Caffeine.toggle()
}
