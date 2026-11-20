import Quickshell
import Quickshell.Wayland
import QtQuick
import "../common" as Common

// Quick capture window: a small card centred on the screen. The shell sets `shown` (IPC,
// keybind); the window exists only while shown. Keyboard focus is exclusive while open so
// typing goes to the field; Esc, an outside click, or a short beat after a save closes it.
// Nothing here sends anything: Enter writes one local task through CaptureCard.
Scope {
  id: root

  property bool shown: false
  property var screen: null            // a ShellScreen; null lets the compositor choose

  function toggle() { root.shown = !root.shown; }

  LazyLoader {
    active: root.shown

    PanelWindow {
      id: win
      screen: root.screen
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      implicitWidth: card.width
      implicitHeight: card.height + 40
      mask: Region { item: card }
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "qs-moments"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Common.DismissGrab {
        windows: [win]
        armed: root.shown
        onDismissed: root.shown = false
      }

      CaptureCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        onCancelled: root.shown = false
        onSubmitted: closeBeat.restart()
        Component.onCompleted: card.focusInput()
      }

      Timer { id: closeBeat; interval: 2400; onTriggered: root.shown = false }
    }
  }
}
