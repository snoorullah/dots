pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "../../services"
import "js/Wall.js" as W

// The wallpaper picker, shown when Ui.open === "wallpaper". The behaviour lives in WallCtl; this
// is the window around it: a centred overlay card that takes the keyboard while it is open.
PanelWindow {
  id: win

  property alias ctl: ctl
  readonly property string name: ctl.name

  WallCtl {
    id: ctl
    typing: panel.search.activeFocus
    searchText: panel.search.text
    onFocusKeys: keys.forceActiveFocus()
    onFocusSearch: t => { panel.search.forceActiveFocus(); if (t !== "") { panel.search.text = t; panel.search.cursorPosition = t.length; } }
    onClearSearch: panel.search.text = ""
  }

  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
  // PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: Math.max(Theme.bar.height + 8, ((screen ? screen.height : 900) - panel.height) / 2)
  margins.left: Math.max(0, ((screen ? screen.width : 1600) - panel.width) / 2)
  implicitWidth: panel.width
  implicitHeight: panel.height
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
    width: panel.width
    height: panel.height
    opacity: ctl.wanted ? 1 : 0
    transform: Scale {
      origin.x: panel.width / 2
      origin.y: panel.height / 2
      xScale: ctl.wanted ? 1 : 0.92
      yScale: ctl.wanted ? 1 : 0.92
      Behavior on xScale { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: ctl.wanted ? Theme.motion.base : Theme.motion.fast } }

    WallPanel {
      id: panel
      m: ctl.m
      onPicked: path => { ctl.patch({ sel: path, toast: false }); ctl.side({ type: "preview" }); }
      onFavourite: path => ctl.run("fav", ["fav", path])
      onApplied: stay => ctl.side(W.nav(ctl.m, ctl.st, stay ? "space" : "enter").side)
      onClosed: ctl.close()
      onEdited: q => ctl.patch({ query: q })
      onKeyed: e => ctl.onKey(e)
      onFolderAsked: { ctl.patch({ folderPrompt: true }); panel.search.forceActiveFocus(); }
      onUntuneToggled: ctl.patch({ untuned: !ctl.st.untuned })
      onPaletteChosen: i => ctl.patch({ extract: i, untuned: false })
      onTargetCycled: ctl.patch(W.nav(ctl.m, ctl.st, "m").st)
      onShuffleToggled: ctl.side({ type: "shuffle", on: !ctl.m.shuffle.on })
      onLockToggled: ctl.side({ type: "lock", on: !ctl.m.lock })
      onUndone: ctl.side({ type: "undo" })
      onSuggestionDismissed: ctl.patch({ aiOpen: false })
    }
  }
}
