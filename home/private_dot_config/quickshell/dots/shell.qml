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
import "modules/wsswitch"
// Each of these modules ships its own Dispatcher/WinPanel-style helper types, so they are
// imported under a qualifier to keep names from colliding.
import "modules/session" as Sess
import "modules/launcher" as Lnch
import "modules/winswitch" as WinSw
import "modules/wallpaper" as Wall
import "modules/logomenu" as Logo
import "modules/windows" as Wins
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
  WsSwitcher {}
  Sess.SessionMenu { id: sessionMenu }
  Sess.AwayPicker {}
  Lnch.Launcher { id: launcher }
  WinSw.WinSwitcher { id: winSwitcher }
  Wall.WallpaperPicker {}
  Logo.LogoMenu {}
  Wins.WindowsPopout {}
  Wins.TabsOverlay {}
  Sidebar {}
  QuickCapture { id: quickCapture }
  Osd {}

  Ipc {
    notifs: notifServer
    toasts: toasts
    capture: quickCapture
    launcher: launcher
    winSwitcher: winSwitcher
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
