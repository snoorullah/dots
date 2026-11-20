import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Locked or Salah: the launcher stays closed and nothing is queried. One icon, one line, one reason.
Item {
  id: root

  property string why: "locked"        // locked | salah

  Column {
    objectName: "closedCard"
    anchors.centerIn: parent
    width: parent.width - 96
    spacing: 10
    Gly { anchors.horizontalCenter: parent.horizontalCenter; name: root.why === "salah" ? "clock" : "lock"; box: 24; color: Theme.color.fgDim }
    DText {
      objectName: "closedTitle"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.why === "salah" ? "Salah time. The launcher is closed." : "Locked. The launcher stays closed."
      role: "bodyS"
    }
    DText {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.why === "salah" ? "It opens again when the prayer window ends. Nothing is searched meanwhile."
                                 : "Nothing is searched or listed while the screen is locked."
      role: "bodyS"
      font.pixelSize: Theme.font.size.caption
      dim: true
    }
  }
}
