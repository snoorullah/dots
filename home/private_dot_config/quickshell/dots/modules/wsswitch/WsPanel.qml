pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "parts"

// The switcher's body: a card holding one of four views (popover tree, full tree with a rail,
// card grid, rail + map), driven entirely by `m` from js/Model.js build(). Nothing here talks
// to Hyprland; the window (WsSwitcher) and the test scene both feed it.
Item {
  id: root

  property var m: ({ variant: "a", mode: "pop", locked: false, fp: { ws: [], total: 0, needs: 0, name: "", icon: "stack", empty: true }, order: [], profiles: [], foot: [] })
  property bool strip: false          // the popover's own profile strip (the bar has none yet)
  property bool readOnly: false
  property real notchX: width / 2
  property alias filter: bar.field

  signal profilePicked(string name)
  signal hoverProfile(string name)
  signal wsFocus(int id)
  signal wsTab(int index)
  signal winPicked(string addr)
  signal moveTo(string addr, string profile)
  signal retry(string addr)
  signal undo()
  signal edited(string q)
  signal keyed(var event)
  signal startSet(string profile)
  signal newWs(int id)
  signal backSet(string profile)
  signal launcher(string query)

  readonly property bool pop: m.variant === "a" && m.mode === "pop"
  readonly property bool lock: !!m.locked
  readonly property string selAddr: m.sel ? m.sel.addr : ""

  implicitWidth: lock ? 380 : (pop ? (m.hover ? 300 : 360) : 880)
  implicitHeight: lock ? lockCard.implicitHeight + 2 * Theme.space.xxxl : (pop ? popCol.implicitHeight : 560)
  width: implicitWidth
  height: implicitHeight

  Canvas {
    visible: root.pop && !root.lock
    x: Math.max(Theme.radius.card + 4, Math.min(root.width - Theme.radius.card - 4, root.notchX)) - 4
    y: -4
    width: 8; height: 4
    property color fill: Qt.alpha(Theme.color.surface, Theme.alpha.panel)
    onFillChanged: requestPaint()
    onPaint: {
      var c = getContext("2d");
      c.reset();
      c.fillStyle = Qt.rgba(fill.r, fill.g, fill.b, fill.a);
      c.beginPath(); c.moveTo(0, height); c.lineTo(width / 2, 0); c.lineTo(width, height); c.closePath(); c.fill();
    }
  }
  Surface { anchors.fill: parent; corner: Theme.radius.card }

  // ---- locked: one line, no profile and no window name ------------------------------------
  Column {
    id: lockCard
    objectName: "lockCard"
    visible: root.lock
    anchors.centerIn: parent
    width: parent.width - 2 * Theme.space.xxxl
    spacing: Theme.space.l
    Gly { anchors.horizontalCenter: parent.horizontalCenter; name: "lock"; box: 24; color: Theme.color.fgDim }
    DText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Locked. The switcher stays closed."; role: "bodyS" }
    Cap { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "No profile, count or window name is shown on the lock screen." }
  }

  // ---- A, popover ------------------------------------------------------------------------
  Column {
    id: popCol
    visible: root.pop && !root.lock
    width: parent.width
    ProfileStrip {
      objectName: "strip"
      visible: root.strip
      height: visible ? 44 : 0
      x: Theme.space.xl
      topPadding: Theme.space.l
      profiles: root.m.profiles || []
      onPicked: name => root.profilePicked(name)
      onHovered: name => root.hoverProfile(name)
    }
    Item {
      width: parent.width
      implicitHeight: pv.visible ? pv.implicitHeight + 2 * Theme.space.xl : tv.implicitHeight
      height: implicitHeight
      Preview { id: pv; objectName: "preview"; visible: !!root.m.hover; x: Theme.space.xl; y: Theme.space.xl; width: parent.width - 2 * Theme.space.xl; p: root.m.hover }
      TreeView {
        id: tv
        visible: !root.m.hover
        width: parent.width
        m: root.m
        showSalah: !!root.m.salah
        onWsFocus: id => root.wsFocus(id)
        onPicked: addr => root.winPicked(addr)
        onMove: (addr, name) => root.moveTo(addr, name)
        onRetry: addr => root.retry(addr)
        onStartSet: p => root.startSet(p)
        onNewWs: id => root.newWs(id)
        onBackSet: root.backSet(root.m.focus)
      }
    }
    Item {
      width: parent.width
      height: popToast.visible ? popToast.height + Theme.space.xl : 0
      Toast { id: popToast; objectName: "popToast"; x: Theme.space.xl; width: parent.width - 2 * Theme.space.xl; text: root.pop && !root.lock ? (root.m.toast || "") : ""; onUndo: root.undo() }
    }
    Item {
      width: parent.width
      height: Math.max(40, popHints.implicitHeight + 2 * Theme.space.m)
      Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
      Hints { id: popHints; x: Theme.space.xxl; y: Theme.space.m; width: parent.width - 2 * Theme.space.xxl; items: root.m.hover ? [{ k: "Click", l: "pin it open" }, { k: "Esc", l: "close" }] : root.m.foot }
    }
  }

  // ---- A full, B, C ----------------------------------------------------------------------
  Item {
    id: full
    visible: !root.pop && !root.lock
    anchors.fill: parent

    FilterBar {
      id: bar
      width: parent.width
      m: root.m
      readOnly: root.readOnly
      onEdited: q => root.edited(q)
      onKeyed: e => root.keyed(e)
    }
    Item {
      id: mid
      anchors.top: bar.bottom
      anchors.bottom: foot.top
      width: parent.width
      clip: true

      // A full
      Item {
        anchors.fill: parent
        visible: root.m.variant === "a"
        Rail {
          id: rail
          width: 92
          height: parent.height
          profiles: root.m.order || []
          onPicked: name => root.profilePicked(name)
        }
        Rectangle { x: rail.width; width: 1; height: parent.height; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
        TreeView {
          x: rail.width + 1
          width: parent.width - rail.width - 1
          height: parent.height
          visible: !root.m.filtering
          m: root.m
          maxBody: 10000
          showSalah: false
          onWsFocus: id => root.wsFocus(id)
          onPicked: addr => root.winPicked(addr)
          onMove: (addr, name) => root.moveTo(addr, name)
          onRetry: addr => root.retry(addr)
          onStartSet: p => root.startSet(p)
          onNewWs: id => root.newWs(id)
          onBackSet: root.backSet(root.m.focus)
        }
        FilteredView {
          x: rail.width + 1
          width: parent.width - rail.width - 1
          height: parent.height
          visible: !!root.m.filtering
          m: root.m
          onPicked: addr => root.winPicked(addr)
          onLauncher: q => root.launcher(q)
        }
      }
      GridView {
        anchors.fill: parent
        visible: root.m.variant === "b"
        m: root.m
        onPickedProfile: name => root.profilePicked(name)
        onPickedWin: addr => root.winPicked(addr)
        onMove: name => root.moveTo(root.selAddr, name)
        onLauncher: q => root.launcher(q)
        onBackSet: p => root.backSet(p)
      }
      MapView {
        anchors.fill: parent
        visible: root.m.variant === "c"
        m: root.m
        onPickedProfile: name => root.profilePicked(name)
        onPickedWs: i => root.wsTab(i)
        onPickedWin: addr => root.winPicked(addr)
        onFocusWs: id => root.wsFocus(id)
        onMove: name => root.moveTo(root.selAddr, name)
        onStartSet: p => root.startSet(p)
        onNewWs: id => root.newWs(id)
        onBackSet: root.backSet(root.m.focus)
        onLauncher: q => root.launcher(q)
      }
    }
    Item {
      id: foot
      anchors.bottom: parent.bottom
      width: parent.width
      height: Math.max(40, fh.implicitHeight + 2 * Theme.space.m)
      Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
      Hints { id: fh; x: Theme.space.xxl; y: Theme.space.m; width: parent.width - 2 * Theme.space.xxl; items: root.m.foot }
    }
  }

  Toast {
    objectName: "fullToast"
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 56
    width: Math.min(380, parent.width - 24)
    text: root.lock || root.pop ? "" : (root.m.toast || "")
    onUndo: root.undo()
  }
}
