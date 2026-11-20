pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../../services"
import "js/Menu.js" as M

// The logo menu, shown when Ui.open === "logomenu" (right-click the bar logo, hold 450 ms, or
// Super+Shift+Space). The behaviour lives in LogoCtl; this is the popout window around it.
PanelWindow {
  id: win

  property alias ctl: ctl
  readonly property string name: ctl.name

  LogoCtl {
    id: ctl
    typing: panel.filter.activeFocus
    onFocusKeys: keys.forceActiveFocus()
    onFocusFilter: t => { panel.filter.forceActiveFocus(); panel.filter.text = t; panel.filter.cursorPosition = t.length; }
    onClearFilter: panel.filter.text = ""
  }

  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: Theme.bar.height + 2
  margins.left: Math.max(Theme.space.l, Math.min((screen ? screen.width : 1600) - panel.width - Theme.space.l, Ui.anchorX - 20))
  implicitWidth: panel.width
  implicitHeight: panel.height + 4
  visible: ctl.wanted || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: ctl.wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  DismissGrab { windows: [win]; armed: ctl.wanted; onDismissed: ctl.close() }

  Item { id: keys; focus: true; Keys.onPressed: e => ctl.onKey(e) }

  Item {
    id: card
    y: 4
    width: panel.width
    height: panel.height
    opacity: ctl.wanted ? 1 : 0
    transform: Scale {
      origin.x: 20
      origin.y: 0
      xScale: ctl.wanted ? 1 : 0.92
      yScale: ctl.wanted ? 1 : 0.92
      Behavior on xScale { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }

    LogoPanel {
      id: panel
      m: ctl.m
      onRun: id => { var r = M.nav(ctl.m, ctl.st, "enter", false, id); ctl.patch(r.st); ctl.side(r.side); }
      onModePicked: name => ctl.pickMode(name)
      onEdited: q => ctl.patch({ query: q })
      onKeyed: e => ctl.onKey(e)
      onCancelLogout: ctl.cancelLogout()
      onAsked: ctl.patch({ ai: !ctl.st.ai })
    }
  }
}
