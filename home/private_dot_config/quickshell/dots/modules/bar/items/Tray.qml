import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import ".."
import "../../theme"

// Status-notifier icons. None -> zero width.
Chip {
  id: chip

  hoverable: false
  shown: SystemTray.items.values.length > 0

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.l

    Repeater {
      model: SystemTray.items

      MouseArea {
        id: slot
        required property var modelData

        width: 16
        height: 16
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
          if (mouse.button === Qt.LeftButton && !slot.modelData.onlyMenu) slot.modelData.activate();
          else if (mouse.button === Qt.MiddleButton) slot.modelData.secondaryActivate();
          else if (slot.modelData.hasMenu) {
            var p = slot.mapToItem(null, 0, slot.height);
            slot.modelData.display(QsWindow.window, p.x, p.y);
          }
        }

        IconImage {
          anchors.fill: parent
          source: slot.modelData.icon
        }
      }
    }
  }
}
