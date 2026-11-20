pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "js/Groups.js" as G
import "js/Dispatch.js" as D

// The tab strip for the focused window's Hyprland group, laid over the top edge of the group.
// Hyprland's own group bar should be off (group.groupbar.enabled = false) or the two draw twice.
// Hidden when the focused window is alone. Click a tab to focus it, the mark closes it.
PanelWindow {
  id: win

  property bool masked: false            // screen share on: sensitive tab titles read "Masked title"

  function norm(a) { var s = String(a); return s.indexOf("0x") === 0 ? s : "0x" + s; }

  readonly property var clients: Hyprland.toplevels.values.map(function (t) {
    var o = t.lastIpcObject || ({});
    return { addr: win.norm(t.address), cls: o["class"] || "", title: t.title || o.title || "",
             grouped: (o.grouped || []).map(win.norm), at: o.at || [0, 0], size: o.size || [0, 0] };
  })
  readonly property string activeAddr: Hyprland.activeToplevel ? win.norm(Hyprland.activeToplevel.address) : ""
  readonly property var m: G.build(clients, activeAddr, masked)
  readonly property var me: {
    for (var i = 0; i < clients.length; i++) if (clients[i].addr === activeAddr) return clients[i];
    return null;
  }
  readonly property var mon: Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.lastIpcObject || ({})) : ({})

  screen: {
    var n = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === n) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.left: me ? Math.max(0, me.at[0] - (mon.x || 0)) : 0
  margins.top: me ? Math.max(0, me.at[1] - (mon.y || 0) + 6) : 0
  implicitWidth: me ? Math.max(240, me.size[0]) : 240
  implicitHeight: bar.height
  visible: m.show
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // group changes do not always move the window list: refresh on the events that change a group
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["changegroupactive", "togglegroup", "moveintogroup", "moveoutofgroup", "activewindowv2", "closewindow"].indexOf(event.name) >= 0)
        Hyprland.refreshToplevels();
    }
  }

  Runner { id: run }

  TabsBar {
    id: bar
    width: parent.width
    m: win.m
    onPicked: addr => run.run(D.focusTab(addr), "focus")
    onClosed: addr => run.run(D.closeTab(addr), "close")
  }
}
