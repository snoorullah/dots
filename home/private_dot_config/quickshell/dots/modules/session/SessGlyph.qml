import QtQuick
import "../common"

// An icon in a box of the board's pixel size: the glyph is drawn larger (SessIcons.px) and
// centred, so layout keeps the board's numbers. `key` is a SessIcons key.
Item {
  id: root

  property string key: ""
  property real boardSize: 16
  property alias color: glyph.color

  implicitWidth: boardSize
  implicitHeight: boardSize

  Icon {
    id: glyph
    anchors.centerIn: parent
    name: SessIcons.name(root.key)
    size: SessIcons.px(root.boardSize)
  }
}
