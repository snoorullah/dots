pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import "../common"
import "../../services"
import "js/Session.js" as S

// The session popout, shown while Ui.open === "session". Buttons run loginctl and systemctl
// argv, nothing else. The destructive ones are greyed while a long command runs in a herdr
// pane (py/session.py blocker, asked each time the card opens). Log out ends the session;
// the day-end record is the clock daemon's. `backupArgv` stays null until a backup command exists.
Popout {
  id: pop

  name: "session"
  panelWidth: 392

  property var backupArgv: null
  property string early: ""
  property var blocker: ({ pending: true })
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("py/session.py").toString().replace(/^file:\/\//, ""))
  readonly property var buttons: S.sessionButtons({
    sessionId: Quickshell.env("XDG_SESSION_ID"), user: Quickshell.env("USER"),
    early: pop.early, backup: pop.backupArgv }, pop.blocker)

  onWantedChanged: if (wanted) { pop.blocker = ({ pending: true }); ask.running = true }

  Timer {
    id: lateGuard
    interval: 300
    onTriggered: if (pop.blocker.pending) pop.blocker = ({ blocked: false, unchecked: true })
  }

  Process {
    id: ask
    command: S.helperArgv(pop.helper, "blocker")
    // the helper not starting or dying is a finished check too: say unchecked, not "still checking"
    onRunningChanged: if (!running) lateGuard.restart()
    stdout: StdioCollector {
      onStreamFinished: {
        try { pop.blocker = JSON.parse(text) } catch (e) { pop.blocker = ({ blocked: false, unchecked: true }) }
      }
    }
  }

  SessionCard {
    width: parent.width
    buttons: pop.buttons
    blocker: pop.blocker
    onClosed: Ui.close()
    onActivated: act => {
      if (act.op !== "argv") return
      Ui.close()
      Quickshell.execDetached(act.argv)
    }
  }
}
