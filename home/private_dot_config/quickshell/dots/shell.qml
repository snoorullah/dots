//@ pragma UseQApplication
// qs-dots: the bar, notifications, OSD, media, quick panel and calendar.
// The overview surface (pill, card, panel) is a separate set of files under
// modules/overview/ that this root loads only if they exist.
import Quickshell
import Quickshell.Io
import QtQuick
import "modules/bar"
import "modules/notif"
import "modules/osd"
import "modules/media"
import "modules/quick"
import "modules/calendar"
import "modules/barpop"
import "modules/cc"
import "modules/sidebar"
import "modules/system"
import "modules/moments"
import "ipc"
import "services"

ShellRoot {
  id: root

  NotifServer { id: notifServer }

  Variants {
    model: Quickshell.screens

    Bar {
      notifs: notifServer
    }
  }

  ToastStack {
    id: toasts
    notifs: notifServer
  }
  NotifCenter { notifs: notifServer }
  // Replaced by SystemPanel (Ui.open "system"); only an explicit "quick" opens it.
  QuickPanel { notifs: notifServer }
  SystemPanel { notifs: notifServer }
  MediaPopout {}
  CalendarPopout {}
  SalahPopout {}
  WaitingPopout {}
  AgentPopout {}
  TrayPopout {}
  ControlCentre {}
  Sidebar {}
  QuickCapture { id: quickCapture }
  Osd {}

  Ipc {
    notifs: notifServer
    toasts: toasts
    capture: quickCapture
  }

  // The overview host, once its file exists (the shell runs green without it).
  FileView {
    path: Quickshell.shellPath("modules/overview/OverviewHost.qml")
    onLoaded: host.active = true
  }
  Loader {
    id: host
    active: false
    asynchronous: true
    source: Qt.resolvedUrl("modules/overview/OverviewHost.qml")
    onLoaded: Overview.host = item
  }
}
