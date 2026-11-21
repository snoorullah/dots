pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../../services"

// Alt+Tab. The behaviour lives in WinCtl; this is the window around it: an overlay layer that
// takes the keyboard only while the strip is shown, so a quick flip never grabs anything.
PanelWindow {
  id: win

  property alias ctl: ctl
  readonly property string name: ctl.name

  WinCtl {
    id: ctl
    typing: panel.filter.activeFocus
    onFocusKeys: keys.forceActiveFocus()
    onFocusFilter: t => { panel.filter.forceActiveFocus(); if (t !== "") { panel.filter.text = t; panel.filter.cursorPosition = t.length; } }
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
  margins.top: 96
  margins.left: Math.max(0, ((screen ? screen.width : 1600) - panel.width) / 2)
  implicitWidth: Math.max(panel.width, 1)
  implicitHeight: Math.max(panel.height, 1)
  visible: ctl.shown || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: ctl.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function next() { ctl.next(); }
  function prev() { ctl.prev(); }
  function release() { ctl.release(); }
  function unlocked() { ctl.unlocked(); }

  Item {
    id: keys
    focus: true
    Keys.onPressed: e => ctl.onKey(e)
    Keys.onReleased: e => { if (e.key === Qt.Key_Alt && ctl.shown) { ctl.release(); e.accepted = true; } }
  }

  Item {
    id: card
    width: panel.width
    height: panel.height
    opacity: ctl.shown ? 1 : 0
    transform: Scale {
      origin.x: panel.width / 2
      origin.y: 0
      xScale: ctl.shown ? 1 : 0.96
      yScale: ctl.shown ? 1 : 0.96
      Behavior on xScale { Anim { duration: ctl.shown ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: ctl.shown ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: ctl.shown ? Theme.motion.base : Theme.motion.fast } }

    WinPanel {
      id: panel
      m: ctl.m
      onPicked: i => { ctl.patch({ sel: i }); ctl.commit(); }
      onScopePicked: id => ctl.patch(ctl.scopeKey(id))
      onEdited: q => ctl.edited(q)
      onKeyed: e => ctl.onKey(e)
      onUndo: ctl.undoClose()
    }
  }
}
