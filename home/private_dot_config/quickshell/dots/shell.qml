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
import "ipc"
import "services"

ShellRoot {
  id: root

  NotifServer { id: notifs }

  Variants {
    model: Quickshell.screens

    Bar {
      notifs: notifs
    }
  }

  ToastStack {
    id: toasts
    notifs: notifs
  }
  NotifCenter { notifs: notifs }
  QuickPanel { notifs: notifs }
  MediaPopout {}
  CalendarPopout {}
  Osd {}

  Ipc {
    notifs: notifs
    toasts: toasts
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
