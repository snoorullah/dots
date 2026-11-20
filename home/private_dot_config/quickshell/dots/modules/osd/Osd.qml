import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../../services"

// Volume and brightness, 220 x 48, bottom centre, 96 up from the edge. It replaces
// swayosd when the switch flips. Click-through: the window takes no input at all.
PanelWindow {
  id: win

  anchors { bottom: true }
// PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.bottom: 96
  implicitWidth: 220
  implicitHeight: 48
  visible: Hud.shown || card.opacity > 0.01
  color: "transparent"
  mask: Region {}
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-osd"
  WlrLayershell.layer: WlrLayer.Overlay

  Surface {
    id: card
    anchors.fill: parent
    opacity: Hud.shown ? 1 : 0
    Behavior on opacity { Anim { duration: Theme.motion.fade } }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Theme.space.xxl
      anchors.rightMargin: Theme.space.xxl
      spacing: Theme.space.xl

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: Hud.kind === "brightness" ? "sun-dim" : (Hud.muted || Hud.value === 0 ? "speaker-slash" : "speaker-high")
        size: Theme.font.size.headline
      }
      OsdBar {
        anchors.verticalCenter: parent.verticalCenter
        width: 100
        value: Hud.value
        muted: Hud.muted
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        mono: true
        text: Math.round(Hud.value * 100) + "%"
      }
    }
  }
}
