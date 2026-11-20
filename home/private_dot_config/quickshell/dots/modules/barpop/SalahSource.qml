import Quickshell
import Quickshell.Io
import QtQuick
import "js/Salah.js" as Salah

// Reads the prayer times file (written by adhd-prayer-times.sh, regenerated daily) and
// parses it. Read-only. A clock tick re-evaluates which prayer is next. Missing or empty
// file -> `parsed.rows` is empty and every surface says nothing rather than guessing.
Item {
  id: root

  readonly property string path: Quickshell.env("DOTS_PRAYER_CONF")
    || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/adhd/prayer-times.conf")

  property var parsed: ({ date: "", rows: [] })
  property date now: new Date()
  readonly property var model: Salah.build(parsed, now)
  // minutes to the next adhan today, or -1 when a window is open / none is left
  readonly property int minutesToNext: (model.ok && model.cur < 0 && model.hero.label === "NEXT")
    ? parsed.rows[model.next].adhan - (now.getHours() * 60 + now.getMinutes()) : -1

  FileView {
    path: root.path
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parsed = Salah.parseConf(text())
    onLoadFailed: root.parsed = ({ date: "", rows: [] })
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }
}
