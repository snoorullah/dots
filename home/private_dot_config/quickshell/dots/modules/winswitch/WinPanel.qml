pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "parts"

// The switcher's body, driven entirely by `m` from js/Switch.js build(). Nothing here talks to
// Hyprland: the window (WinSwitcher) and the test scene both feed it. While `m.mode` is
// "locked" nothing is built or drawn at all, so no title can reach the screen.
Item {
  id: root

  property var m: ({ mode: "locked", cards: [], scopes: [], hints: [], panelW: 0 })
  property bool readOnly: false
  property alias filter: query.field

  signal picked(int index)
  signal scopePicked(string id)
  signal edited(string q)
  signal keyed(var event)
  signal undo()

  readonly property bool live: m.mode !== "locked"
  readonly property int pad: Theme.space.xxl
  readonly property bool strip: m.layout === "strip" || !m.layout
  readonly property int bodyH: m.mode === "nomatch" ? 188
    : strip ? 188 : (m.layout === "grid" ? 350 : Math.min(Math.max(m.cards.length, 1), 8) * 44 + 8)
  readonly property bool hasCaption: !!m.caption && m.mode !== "nomatch"
  readonly property bool hasStatus: !!m.status

  visible: live
  width: live ? m.panelW : 0
  height: live ? pad + 40 + 10 + bodyH + (hasCaption ? 36 : 0) + (hasStatus ? 40 : 0) + pad : 0

  Surface { anchors.fill: parent; corner: Theme.radius.panel }

  // ---- header ----------------------------------------------------------------------------
  Item {
    id: head
    x: root.pad; y: root.pad
    width: parent.width - 2 * root.pad
    height: 40
    ScopeBar { visible: !!root.m.showScope; anchors.verticalCenter: parent.verticalCenter; scopes: root.m.scopes || []; onPicked: id => root.scopePicked(id) }
    Rectangle {
      visible: !!root.m.showGroupChip
      objectName: "groupChip"
      anchors.verticalCenter: parent.verticalCenter
      width: grp.implicitWidth + 28; height: 36; radius: 18
      color: Qt.alpha(Theme.color.accent, Theme.alpha.on)
      border.width: 1; border.color: Theme.color.accent
      Row {
        id: grp
        anchors.centerIn: parent
        spacing: 8
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "stack"; box: 16; color: Theme.color.accent }
        DText { anchors.verticalCenter: parent.verticalCenter; text: "Group, " + (root.m.cards ? root.m.cards.length : 0) + " tabs"; role: "bodyS"; color: Theme.color.accent }
      }
    }
    QueryBar {
      id: query
      visible: !!root.m.showQuery
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - hints.width - Theme.space.xl
      query: root.m.query || ""
      count: root.m.qCount || ""
      ai: !!root.m.ai
      thinking: !!root.m.thinking
      onEdited: q => root.edited(q)
      onKeyed: e => root.keyed(e)
    }
    HintRow { id: hints; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; items: root.m.hints || [] }
  }

  // ---- body ------------------------------------------------------------------------------
  Item {
    id: body
    x: root.pad; y: head.y + 40 + 10
    width: parent.width - 2 * root.pad
    height: root.bodyH
    clip: true

    Rectangle {
      objectName: "noMatch"
      visible: root.m.mode === "nomatch"
      anchors.fill: parent
      radius: Theme.radius.card
      color: Theme.color.bg
      border.width: 1; border.color: Theme.color.outlineVariant
      Column {
        anchors.centerIn: parent
        spacing: 10
        DText { anchors.horizontalCenter: parent.horizontalCenter; text: "No window matches"; role: "headline" }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Esc to clear; 3 for all scopes" }
      }
    }

    // strip: one row, the selection kept in view
    Item {
      id: track
      visible: root.strip && root.m.mode !== "nomatch"
      x: root.m.tx || 0
      y: 16
      width: root.m.contentW || 1
      Behavior on x { Anim { duration: Theme.motion.fast } }
      Repeater {
        model: root.strip ? (root.m.cards || []) : []
        Card {
          id: sc
          required property var modelData
          required property int index
          objectName: "winCard"
          x: index * 212
          c: modelData
          onPicked: root.picked(sc.index)
        }
      }
    }
    Rectangle { visible: !!root.m.overflow && root.strip; width: 56; height: parent.height; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.color.surface } GradientStop { position: 1; color: "transparent" } } }
    Rectangle { visible: !!root.m.overflow && root.strip; x: parent.width - 56; width: 56; height: parent.height; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Theme.color.surface } } }

    // grid: a page of eight
    Grid {
      visible: root.m.layout === "grid" && root.m.mode !== "nomatch"
      y: Theme.space.m
      columns: 4
      spacing: Theme.space.xl
      Repeater {
        model: root.m.layout === "grid" ? root.pageOf(8) : []
        Card {
          id: gcard
          required property var modelData
          required property int index
          objectName: "winCard"
          c: modelData
          onPicked: root.picked(root.pageStart(8) + gcard.index)
        }
      }
    }

    // list: eight rows around the selection
    Column {
      visible: root.m.layout === "list" && root.m.mode !== "nomatch"
      width: parent.width
      Repeater {
        model: root.m.layout === "list" ? root.pageOf(8) : []
        ListRow {
          id: lrow
          required property var modelData
          required property int index
          objectName: "winRow"
          width: parent.width
          c: modelData
          onPicked: root.picked(root.pageStart(8) + lrow.index)
        }
      }
    }
  }

  function pageStart(size) {
    var n = (m.cards || []).length
    if (m.layout === "grid") return Math.floor(m.sel / size) * size
    return Math.max(0, Math.min(m.sel - 3, n - size))
  }
  function pageOf(size) {
    var s = pageStart(size)
    return (m.cards || []).slice(s, s + size)
  }

  // ---- caption ---------------------------------------------------------------------------
  Item {
    id: cap
    visible: root.hasCaption
    x: root.pad; y: body.y + body.height
    width: parent.width - 2 * root.pad
    height: 36
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.xl
      DText { objectName: "capTitle"; anchors.verticalCenter: parent.verticalCenter; text: root.m.caption ? root.m.caption.title : ""; role: "body"; font.weight: Font.DemiBold }
      Repeater {
        model: root.m.caption ? root.m.caption.meta : []
        Cap {
          required property var modelData
          anchors.verticalCenter: parent ? parent.verticalCenter : undefined
          text: modelData.t
          dim: false
          color: modelData.tone === "accent" ? Theme.color.accent : modelData.tone === "warn" ? Theme.color.waiting : Theme.color.fgDim
        }
      }
    }
    Cap { objectName: "capCount"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.m.caption ? root.m.caption.count : "" }
  }

  // ---- status ----------------------------------------------------------------------------
  Rectangle {
    id: status
    objectName: "status"
    visible: root.hasStatus
    x: root.pad; y: cap.y + (root.hasCaption ? 36 : 0) + 4
    width: parent.width - 2 * root.pad
    height: 32
    radius: Theme.radius.row
    color: Qt.alpha(root.m.status && root.m.status.tone === "warn" ? Theme.color.waiting : Theme.color.accent, Theme.alpha.rest + 0.04)
    border.width: 1
    border.color: Theme.color.outlineVariant
    property string text: root.m.status ? root.m.status.text : ""
    Row {
      anchors.fill: parent
      anchors.leftMargin: Theme.space.xl
      anchors.rightMargin: Theme.space.m
      spacing: Theme.space.l
      Gly { anchors.verticalCenter: parent.verticalCenter; name: root.m.status ? root.m.status.icon : "list-bullets"; box: 16; color: root.m.status && root.m.status.tone === "warn" ? Theme.color.waiting : Theme.color.accent }
      Cap { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16 - (undoBtn.visible ? undoBtn.width : 0) - 2 * Theme.space.l; elide: Text.ElideRight; text: status.text; dim: false }
      Btn { id: undoBtn; visible: !!(root.m.status && root.m.status.action); anchors.verticalCenter: parent.verticalCenter; label: "Undo"; kind: "ghost"; onClicked: root.undo() }
    }
  }
}
