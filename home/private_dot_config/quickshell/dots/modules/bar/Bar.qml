import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import QtQuick
import "../theme"
import "../common"
import "../overview"
import "../moments"
import "../../services"
import "js/BarModel.js" as Model

// The bar window. Wiring only: it reads the services, builds one plain model with
// js/BarModel.js and hands it to BarView, then turns BarView's click signals into Ui calls.
// Public API kept for shell.qml: `notifs`. Layout and states are in docs/shell/specs/bar.md.
PanelWindow {
  id: bar

  required property var modelData
  property var notifs: null

  screen: modelData
  anchors { top: true; left: true; right: true }
  implicitHeight: view.stripHeight
  exclusiveZone: view.stripHeight
  color: "transparent"
  WlrLayershell.namespace: "qs-bar"

  IdleInhibitor {
    window: bar
    enabled: Caffeine.on
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // the next prayer, from the helper the old bar ran; its text is turned into a runway
  ScriptJson {
    id: salahSrc
    command: [Quickshell.env("HOME") + "/.local/bin/waybar-salah.sh"]
    interval: 60000
  }

  // STUB: profiles have no data source yet, so this list is fixed and nothing selects one
  readonly property var profiles: [
    { name: "Agents", icon: "sparkle" },
    { name: "Dev", icon: "terminal-window" },
    { name: "Web", icon: "globe" },
    { name: "Comms", icon: "chat-circle" },
    { name: "Review", icon: "git-pull-request" },
    { name: "Notes", icon: "notebook" },
    { name: "Other", icon: "stack" }
  ]

  // an app's logo: its desktop entry's icon, else an icon named like its window class
  function appIcon(cls) {
    if (!cls) return "";
    var e = DesktopEntries.heuristicLookup(cls);
    var p = Quickshell.iconPath(e && e.icon ? e.icon : cls.toLowerCase(), true);
    return p ? p : "";
  }

  readonly property var toplevels: {
    var out = [];
    var v = Hyprland.toplevels.values;
    for (var i = 0; i < v.length; i++) {
      var t = v[i];
      var c = t.lastIpcObject ? t.lastIpcObject["class"] : "";
      if (t.workspace && c) out.push({ wsId: t.workspace.id, cls: c, icon: bar.appIcon(c) });
    }
    return out;
  }

  readonly property var lampWaits: [
    { id: "l1", kind: "agent", ageSec: 720 },
    { id: "l2", kind: "review", ageSec: 180 },
    { id: "l3", kind: "alert", ageSec: 120 }
  ]

  readonly property var wsModel: Model.workspaces(Hypr.workspaces, bar.toplevels, Hypr.activeId, 3)

  readonly property var viewModel: {
    var player = Mpris.active;
    var today = Feed.today;
    var lamp = Lamp.on;
    var active = "";
    for (var i = 0; i < bar.wsModel.length; i++)
      if (bar.wsModel[i].active) active = bar.wsModel[i].name;
    var names = [];
    for (var j = 0; j < bar.profiles.length; j++) names.push(bar.profiles[j].name);
    return {
      profiles: bar.profiles,
      activeProfile: Model.activeProfile(names, active),
      workspaces: bar.wsModel,
      task: Model.taskText(Feed.task),
      detour: MomentState.detour.text,    // now.json away clock (modules/moments)
      clock: Qt.formatDateTime(clock.date, "HH:mm"),
      date: Qt.formatDateTime(clock.date, "ddd d MMM"),
      salah: Model.salahLabel(salahSrc.failed ? "" : salahSrc.text, clock.date),
      waits: Model.waitSymbols(lamp ? bar.lampWaits : Feed.attentionItems, 3),
      fault: lamp ? { kind: "failed", text: "lamp test" }
                  : Model.fault({ level: OpsState.level, text: OpsState.text, stale: OpsState.stale }, Feed.degraded),
      music: {
        present: Mpris.present,
        playing: player ? player.isPlaying : false,
        title: player ? player.trackTitle : "",
        artist: player ? player.trackArtist : "",
        art: player ? player.trackArtUrl : ""
      },
      metrics: Model.metrics({ tasks: today ? today.tasksDone : undefined, workedSec: today ? today.workedSec : undefined }),
      logout: "",                         // STUB: no source
      bell: {
        dot: lamp || (bar.notifs ? (bar.notifs.count > 0 || bar.notifs.held) : false),
        quiet: bar.notifs ? bar.notifs.quiet : false
      }
    };
  }

  BarView {
    id: view
    anchors.fill: parent
    model: bar.viewModel
    trayModel: SystemTray.items
    onToggleRequested: (name, x) => Ui.toggle(name, bar.screen.name, x)
    onLogoClicked: Ui.toggleCc()
    onWorkspaceRequested: id => Hypr.focus(id)
  }
}
