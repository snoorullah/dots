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
    Behavior on opacity { Anim { duration: Hud.shown ? Theme.motion.base : Theme.motion.fast } }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Theme.space.xxl
      anchors.rightMargin: Theme.space.xxl
      spacing: Theme.space.xl

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        text: Hud.kind === "brightness" ? "brightness_6" : (Hud.muted || Hud.value === 0 ? "volume_off" : "volume_up")
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
