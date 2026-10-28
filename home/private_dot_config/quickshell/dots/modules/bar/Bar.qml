import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../../services"
import "items"

// The bar: three slabs on a transparent 30 px strip, the same height as the waybar it
// stands in for, so `dots-shell use waybar` shifts nothing.
//
//   left   [workspaces]
//   centre [clock · salah]
//   right  [attn · tracking · ops · ctx · caffeine · bell · volume · tray]
//
// On a nominal machine the right slab is volume and tray only. That is intended.
PanelWindow {
  id: bar

  required property var modelData
  property var notifs: null

  screen: modelData
  anchors { top: true; left: true; right: true }
  implicitHeight: Theme.bar.height
  exclusiveZone: Theme.bar.height
  color: "transparent"
  WlrLayershell.namespace: "qs-bar"

  IdleInhibitor {
    window: bar
    enabled: Caffeine.on
  }

  Slab {
    id: leftSlab
    x: Theme.bar.gutter
    Workspaces { screenName: bar.screen.name }
  }

  Slab {
    id: centreSlab
    anchors.horizontalCenter: parent.horizontalCenter
    Clock { screenName: bar.screen.name }
    Salah { screenName: bar.screen.name }
  }

  Slab {
    id: rightSlab
    anchors.right: parent.right
    anchors.rightMargin: Theme.bar.gutter
    Attn { screenName: bar.screen.name }
    Tracking { screenName: bar.screen.name }
    Ops { screenName: bar.screen.name }
    Ctx { id: ctx; screenName: bar.screen.name }
    CaffeineChip { screenName: bar.screen.name }
    Bell { notifs: bar.notifs; screenName: bar.screen.name }
    Volume { screenName: bar.screen.name }
    Tray { screenName: bar.screen.name }
  }

  function cycleCtx() { ctx.cycle(); }
}
