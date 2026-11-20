pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "js/Menus.js" as Menus

// What the system popout holds: the quick view, one drill-in menu, or the session card.
// The swap fades over motion.fade; nothing else moves. Takes state in, emits intents out.
Item {
  id: root

  property var st: ({})
  property string view: ""              // "" | a menu id | "session"
  property var env: ({})                // {sessionId, user} for the log-out argv
  property real maxBody: 640
  signal activated(var act)
  signal moved(var act, real fraction)
  signal meterMoved(string which, real fraction)
  signal mediaCommand(string what)
  signal viewRequested(string view)

  readonly property bool isSession: view === "session"
  readonly property var menuModel: (view !== "" && !isSession) ? Menus.menu(view, st) : null
  readonly property bool inMenu: menuModel !== null

  implicitHeight: isSession ? session.implicitHeight : inMenu ? menu.implicitHeight : quick.implicitHeight

  QuickView {
    id: quick
    width: parent.width
    st: root.st
    selected: root.view
    visible: opacity > 0.01
    opacity: root.view === "" ? 1 : 0
    Behavior on opacity { Anim { duration: Theme.motion.fade } }
    onTileToggled: id => root.activated(Menus.tileAct(id, root.st))
    onTileOpened: id => root.viewRequested(id)
    onMeterMoved: (which, f) => root.meterMoved(which, f)
    onMeterOpened: id => root.viewRequested(id)
    onMediaCommand: what => root.mediaCommand(what)
    onPowerClicked: root.viewRequested("session")
  }

  SysMenuCard {
    id: menu
    width: parent.width
    model: root.menuModel
    maxBody: root.maxBody
    visible: opacity > 0.01
    opacity: root.inMenu ? 1 : 0
    Behavior on opacity { Anim { duration: Theme.motion.fade } }
    onActivated: act => root.activated(act)
    onMoved: (act, f) => root.moved(act, f)
    onClosed: root.viewRequested("")
  }

  SysSession {
    id: session
    width: parent.width
    buttons: Menus.sessionButtons(root.st, root.env)
    blocker: root.st && root.st.session ? (root.st.session.blocker || "") : ""
    visible: opacity > 0.01
    opacity: root.isSession ? 1 : 0
    Behavior on opacity { Anim { duration: Theme.motion.fade } }
    onActivated: act => root.activated(act)
    onClosed: root.viewRequested("")
  }
}
