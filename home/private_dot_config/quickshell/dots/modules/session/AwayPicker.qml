pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../../services"
import "js/Session.js" as S

// Super+Esc: why are you stepping away? Shown while Ui.open === "away". Picking a row runs
// py/session.py declare KEY, which is `timetrack away --declare KEY` then `loginctl
// lock-session`, the same two commands the old fzf picker ran. Esc or an outside click
// closes it: nothing is recorded and nothing locks. Nothing leaves the machine.
PanelWindow {
  id: win

  readonly property string name: "away"
  readonly property bool wanted: Ui.open === name
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("py/session.py").toString().replace(/^file:\/\//, ""))
  property var rows: S.awayRows([])

  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  implicitWidth: card.width
  implicitHeight: card.height
  visible: wanted || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onWantedChanged: {
    if (wanted) { win.rows = S.awayRows([]); list.current = 0; load.running = true; list.forceActiveFocus() }
  }

  DismissGrab { windows: [win]; armed: win.wanted; onDismissed: Ui.close() }

  Process {
    id: load
    command: S.helperArgv(win.helper, "choices")
    stdout: StdioCollector {
      onStreamFinished: {
        try { win.rows = S.awayRows(JSON.parse(text)) } catch (e) { console.log("AwayPicker: choices unreadable") }
      }
    }
  }

  Surface {
    id: card
    corner: Theme.radius.card
    width: 420
    height: list.implicitHeight + 2 * Theme.space.xxl
    opacity: win.wanted ? 1 : 0
    Behavior on opacity { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }

    AwayList {
      id: list
      x: Theme.space.xxl
      y: Theme.space.xxl
      width: parent.width - 2 * Theme.space.xxl
      rows: win.rows
      onCancelled: Ui.close()
      onPicked: key => {
        Ui.close()
        Quickshell.execDetached(S.helperArgv(win.helper, "declare", key))
      }
    }
  }
}
