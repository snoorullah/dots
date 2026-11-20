import QtQuick
import "../common"

// An icon in a box of the board's pixel size. The glyph is drawn larger (SysIcons.px) so it
// looks the size the board shows, and centred, so layout still uses the board's numbers.
// `key` is a SysIcons key (or a Phosphor name).
Item {
  id: root

  property string key: ""
  property real boardSize: 16
  property bool active: false
  property alias color: glyph.color

  implicitWidth: boardSize
  implicitHeight: boardSize

  Icon {
    id: glyph
    anchors.centerIn: parent
    name: SysIcons.name(root.key)
    active: root.active
    size: SysIcons.px(root.boardSize)
  }
}
