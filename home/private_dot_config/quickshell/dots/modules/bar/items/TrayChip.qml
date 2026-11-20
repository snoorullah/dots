import QtQuick
import Quickshell.Widgets
import "../../theme"
import ".."

// Status-notifier icons, as one target that opens the tray popout. Zero width with none.
// `trayModel` is SystemTray.items in the shell; a ListModel of { icon } in tests.
Chip {
  id: root

  property var trayModel: null
  readonly property int count: repeater.count
  signal activated(string popout, real x)

  objectName: "tray"
  visible: count > 0
  padX: Theme.space.s

  Repeater {
    id: repeater
    model: root.trayModel

    IconImage {
      required property var modelData
      anchors.verticalCenter: parent.verticalCenter
      implicitSize: Theme.font.size.title
      source: modelData.icon
    }
  }

  onClicked: b => root.activated("tray", root.mapToItem(null, root.width / 2, 0).x)
}
