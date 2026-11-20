import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import "../../services"

// The full-screen control centre. Exists only while Ui.cc is set (LazyLoader), takes the
// keyboard exclusively so Esc and the action keys reach it, fades in over motion.slow.
// Esc or Back to task calls Ui.toggleCc().
Scope {
  id: root

  readonly property var screenObj: {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === Ui.screenName) return list[i]
    return list.length > 0 ? list[0] : null
  }

  LazyLoader {
    active: Ui.cc

    PanelWindow {
      id: win
      screen: root.screenObj
      color: Theme.color.bg
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "qs-cc"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      CcView {
        id: view
        anchors.fill: parent
        opacity: 0
        onCloseRequested: Ui.toggleCc()
        Component.onCompleted: { view.forceActiveFocus(); fade.start() }
        NumberAnimation { id: fade; target: view; property: "opacity"; from: 0; to: 1; duration: Theme.motion.slow; easing.type: Theme.motion.easeOut }
      }
    }
  }
}
