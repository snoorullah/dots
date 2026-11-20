import QtQuick
import "../theme"
import "items"

// The bar, drawn from one plain `model` (see js/BarModel.js and Bar.qml for what builds it).
// No service is touched here, which is what lets tests/bar-ui.sh render every board state
// from fixtures. Three pills on a transparent strip:
//
//   left    logo | profiles | workspaces + logos | task, detour
//   centre  time . date . prayer
//   right   waiting symbols | fault | music | metrics, logout | tray | bell
//
// A click is reported, never acted on: toggleRequested(name, x) with the window-local x the
// popout points its notch at, and logoClicked(). Bar.qml connects them to Ui.
Item {
  id: view

  property var model: ({})
  property var trayModel: null
  property real eqTime: -1          // pin the equalizer for screenshots
  readonly property int pillHeight: Theme.space.xxxl + Theme.space.xxl
  readonly property int stripHeight: pillHeight + Theme.space.m

  signal toggleRequested(string name, real x)
  signal logoClicked()
  signal workspaceRequested(int id)

  readonly property var m: model || ({})
  readonly property var waits: m.waits || ({ shown: [], more: 0 })
  readonly property var fault: m.fault || ({ kind: "none", text: "" })
  readonly property var music: m.music || ({ present: false })

  implicitHeight: stripHeight

  // room the task text may take before the left pill would touch the centre pill
  readonly property real leftRoom: (width - centreSlab.implicitWidth) / 2 - Theme.space.m - Theme.bar.gutter
    - (leftSlab.padLeft + leftSlab.padRight + logoMark.width + profilesRow.width + workspacesRow.width + 3 + 6 * leftSlab.gap)

  Slab {
    id: leftSlab
    objectName: "leftPill"
    x: Theme.bar.gutter
    y: (view.height - height) / 2
    padLeft: Theme.space.s + 2
    padRight: Theme.space.xl
    gap: Theme.space.m

    Logo {
      id: logoMark
      objectName: "logo"
      anchors.verticalCenter: parent.verticalCenter
      onClicked: view.logoClicked()
    }
    Divider {}
    Profiles {
      id: profilesRow
      objectName: "profiles"
      profiles: view.m.profiles || []
      active: view.m.activeProfile || ""
    }
    Divider {}
    Workspaces {
      id: workspacesRow
      objectName: "workspaces"
      workspaces: view.m.workspaces || []
      pinHover: view.m.hoverWs !== undefined ? view.m.hoverWs : -1
      onFocusRequested: id => view.workspaceRequested(id)
    }
    Divider { visible: taskText.task !== "" && taskText.maxText >= 48 }
    TaskText {
      id: taskText
      objectName: "task"
      maxText: Math.max(0, Math.min(170, view.leftRoom - (view.m.detour ? 80 : 0)))
      task: view.m.task || ""
      detour: view.m.detour || ""
    }
  }

  Slab {
    id: centreSlab
    objectName: "centrePill"
    anchors.horizontalCenter: parent.horizontalCenter
    y: (view.height - height) / 2
    padLeft: Theme.space.m
    padRight: Theme.space.m

    ClockBlock {
      objectName: "clockBlock"
      clock: view.m.clock || ""
      date: view.m.date || ""
      salah: view.m.salah || ""
      onActivated: (name, x) => view.toggleRequested(name, x)
    }
  }

  Slab {
    id: rightSlab
    objectName: "rightPill"
    anchors.right: parent.right
    anchors.rightMargin: Theme.bar.gutter
    y: (view.height - height) / 2
    padLeft: Theme.space.xl
    padRight: Theme.space.m
    gap: Theme.space.m

    Waits {
      objectName: "waits"
      shown: view.waits.shown
      more: view.waits.more
      onActivated: (name, x) => view.toggleRequested(name, x)
    }
    Divider { visible: view.waits.shown.length > 0 }
    Fault {
      kind: view.fault.kind
      text: view.fault.text
      onClicked: b => view.toggleRequested("system", mapToItem(null, width / 2, 0).x)
    }
    Divider { visible: view.fault.kind !== "none" }
    Music {
      music: view.music
      blockWidth: (view.waits.shown.length + (view.waits.more > 0 ? 1 : 0) + (view.fault.kind !== "none" ? 1 : 0)) >= 3 ? 230 : 270
      eqTime: view.eqTime
      onClicked: b => view.toggleRequested("media", mapToItem(null, width / 2, 0).x)
    }
    Divider { visible: view.music.present && (metrics.visible || logout.visible) }
    Metrics {
      id: metrics
      metrics: view.m.metrics || []
      onClicked: b => view.toggleRequested("system", mapToItem(null, width / 2, 0).x)
    }
    LogoutChip {
      id: logout
      anchors.verticalCenter: parent.verticalCenter
      time: view.m.logout || ""
    }
    Divider { visible: tray.visible }
    TrayChip {
      id: tray
      trayModel: view.trayModel
      onActivated: (name, x) => view.toggleRequested(name, x)
    }
    Divider { visible: view.waits.shown.length > 0 || view.fault.kind !== "none" || view.music.present || metrics.visible || logout.visible || tray.visible }
    Bell {
      dot: !!(view.m.bell && view.m.bell.dot)
      quiet: !!(view.m.bell && view.m.bell.quiet)
      onActivated: (name, x) => view.toggleRequested(name, x)
    }
  }
}
