pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../../services"
import "providers"
import "js/Model.js" as M
import "parts"

// The launcher window (board `Launcher`), shown when Ui.open === "launcher". Super+Space opens it,
// otter-launcher moved to Super+Alt+Space. The provider list is static and ordered (chip order, All first);
// nothing is scanned. Contract: docs/shell/specs/launcher-contract.md
PanelWindow {
  id: win

  readonly property string name: "launcher"
  property bool locked: false           // no lock-state source yet; hyprlock owns the lock, a surface may set this
  property string startMode: ""         // a prefix ("c:") the opener wants, bound by the integration
  readonly property bool wanted: Ui.open === name
  readonly property bool shown: wanted && !locked

  SalahSource { id: salahSrc }
  readonly property bool salah: salahSrc.model.ok && salahSrc.model.cur >= 0

  // ---- providers: static, ordered ---------------------------------------------------------
  All { id: all; sources: [apps, cmds, math, clipb, dict, files, fonts, wins, snips, emoji, hosts, kube] }
  Apps { id: apps }
  Commands { id: cmds }
  Math { id: math }
  Clipboard { id: clipb }
  Dictionary { id: dict }
  Files { id: files }
  Fonts { id: fonts }
  Windows { id: wins }
  Snippets { id: snips }
  Emoji { id: emoji }
  Hosts { id: hosts }
  Kube { id: kube }

  // chip order follows the board: All, Clipboard, Dictionary, Files, Fonts, Commands, Math, then the rest
  readonly property var providers: [all, clipb, dict, files, fonts, cmds, math, wins, snips, emoji, hosts, kube, apps]

  LauncherState {
    id: core
    providers: win.providers
    blocked: win.locked ? "locked" : (win.salah ? "salah" : "")
    startPrefix: win.startMode
    open: win.shown
    onCloseRequested: Ui.close()
    // a toast would die with the window: a replaceable low-urgency notification carries it
    onFarewell: text => Quickshell.execDetached(["notify-send", "-a", "launcher", "-u", "low", "-t", "2500",
                                                 "-h", "string:x-canonical-private-synchronous:dots-launcher", text])
  }

  // ---- window ----------------------------------------------------------------------------
  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: Theme.bar.height + 10
  margins.left: M.centred(screen ? screen.width : 1600, card.width)
  implicitWidth: card.width
  implicitHeight: card.height
  visible: wanted || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  DismissGrab { windows: [win]; armed: win.wanted; onDismissed: Ui.close() }

  Card {
    id: card
    st: core
    opacity: win.wanted ? 1 : 0
    scale: win.wanted ? 1 : 0.96
    transformOrigin: Item.Top
    Behavior on opacity { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
    Behavior on scale { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
    onVisibleChanged: if (visible && win.wanted) card.field.forceActiveFocus()
  }

  // open with text already in the field (IPC dots.launcher query)
  function openWith(t) {
    startMode = "";
    Ui.open = name;
    Qt.callLater(function () { card.field.text = t; core.setText(t); });
  }

  onWantedChanged: if (wanted) Qt.callLater(function () { card.field.forceActiveFocus(); })
}
