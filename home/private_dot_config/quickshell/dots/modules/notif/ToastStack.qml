pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"

// Toasts, top right, offset 8,38 from the screen corner (just under the bar), stacked
// with an 8 px gap. The window is exactly as tall as what is showing and is unmapped
// when nothing is, so it never swallows a click it has no business with.
//
// Layout is done by hand (reflow) rather than by a Column: an unmapped window is never
// polished, so a Column inside it would never learn its height and the window would
// never map. Toasts report whether they are shown; this adds up the heights itself.
PanelWindow {
  id: win

  property var notifs: null
  property real stackHeight: 0

  function reflow() {
    var y = 0;
    for (var i = 0; i < rep.count; i++) {
      var t = rep.itemAt(i) as Toast;
      if (!t || !t.shown) continue;
      t.y = y;
      y += t.height + Theme.space.l;
    }
    win.stackHeight = Math.max(0, y - Theme.space.l);
  }

  // how many toasts are on screen right now (the IPC test hook asks; nothing binds to it)
  function visibleCount() {
    var n = 0;
    for (var i = 0; i < rep.count; i++) {
      var t = rep.itemAt(i) as Toast;
      if (t && t.shown) n++;
    }
    return n;
  }

  anchors { top: true; right: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: 38
  margins.right: 8
  implicitWidth: 380
  implicitHeight: Math.max(1, stackHeight)
  visible: stackHeight > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-notif"
  WlrLayershell.layer: WlrLayer.Overlay

  Item {
    id: stack
    width: parent.width
    height: win.stackHeight

    Repeater {
      id: rep
      model: win.notifs ? win.notifs.model : null
      onCountChanged: Qt.callLater(win.reflow)

      Toast {
        dnd: win.notifs ? win.notifs.dnd : false
        onShownChanged: win.reflow()
        onHeightChanged: win.reflow()
        Component.onCompleted: win.reflow()
      }
    }
  }
}
