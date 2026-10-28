pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon. Quickshell's server and swaync cannot both own
// org.freedesktop.Notifications, so this asks the bus first and, when another daemon
// holds the name, logs one line and stays out. The bell chip then shows a hollow "?".
// No crash loop, no fight for the name.
Scope {
  id: root

  property bool checked: false
  property bool held: false          // another daemon owns the name
  property bool dnd: false
  readonly property var model: lazy.item ? (lazy.item as NotificationServer).trackedNotifications : null
  readonly property int count: model ? model.values.length : 0

  signal arrived(var notification)

  function clearAll() {
    if (!model) return;
    var v = model.values.slice();
    for (var i = 0; i < v.length; i++) v[i].dismiss();
  }

  Process {
    id: probe
    command: ["busctl", "--user", "status", "org.freedesktop.Notifications"]
    running: true
    onExited: code => {
      root.held = (code === 0);
      root.checked = true;
      if (root.held) console.log("notif: org.freedesktop.Notifications is held by another daemon; not claiming it");
    }
  }

  LazyLoader {
    id: lazy
    active: root.checked && !root.held

    NotificationServer {
      keepOnReload: false
      actionsSupported: true
      bodySupported: true
      imageSupported: true
      onNotification: notification => {
        notification.tracked = true;
        root.arrived(notification);
      }
    }
  }
}
