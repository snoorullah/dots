pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Reminders: tasks that are due, tasks scheduled, and the next prayer. j k move, s hides a row
// for this session, d marks it handled here. The task list itself is read-only from here.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property var hidden: ({})
  property real now: 0
  property string status: ""
  signal pick(int row, int col)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property var model: M.reminderRows(doc, hidden, now)
  readonly property var rows: model ? model.rows : []

  onKsChanged: {
    if (!model) return
    var y = ks.row * 40 + (ks.row >= model.dueCount ? 28 : 0)
    flick.ensure(y, 40)
  }

  objectName: "timeReminders"
  spacing: 16

  NoData {
    visible: t.model === null
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    title: "Reminders"
    icon: "bell"
    text: M.emptyText(t.parsed, "reminders")
  }

  Card {
    id: remCard
    objectName: "remindersCard"
    visible: t.model !== null
    Layout.fillWidth: true
    Layout.preferredWidth: 2
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    implicitHeight: 0
    clip: true
    FocusRing { parent: remCard; kind: "pane"; focused: t.inList; radius: Theme.radius.card }
    Flickable {
      id: flick
      objectName: "remScroll"
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: col.height
      boundsBehavior: Flickable.StopAtBounds
      function ensure(y, h) {
        if (y < contentY) contentY = Math.max(0, y - 28)
        else if (y + h > contentY + height) contentY = Math.min(Math.max(0, contentHeight - height), y + h - height)
      }
      Column {
        id: col
        width: flick.width
        spacing: 0
        Repeater {
          model: t.rows
          Column {
            id: rc
            required property var modelData
            required property int index
            readonly property bool sel: t.ks.row === index
            width: col.width
            Item {
              visible: rc.index === 0 || rc.modelData.kind !== t.rows[rc.index - 1].kind
              width: parent.width
              height: visible ? 28 : 0
              Cap { anchors.verticalCenter: parent.verticalCenter; text: rc.modelData.kind === "due" ? "DUE" : "SCHEDULED" }
            }
            Item {
              objectName: "remRow"
              width: parent.width
              height: 40
              Rectangle { anchors.fill: parent; anchors.bottomMargin: 2; radius: Theme.radius.chip; color: rc.sel ? Theme.color.surfaceContainer : "transparent" }
              FocusRing { anchors.bottomMargin: 2; focused: rc.sel && t.inList }
              Rectangle { x: 10; width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: rc.modelData.overdue ? Theme.color.waiting : (rc.modelData.kind === "due" ? Theme.color.accent : Theme.color.fgDim) }
              DText { x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 30 - 260; text: rc.modelData.desc; role: "body"; elide: Text.ElideRight }
              DText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: rc.modelData.when + (rc.modelData.rel !== "" ? "  " + rc.modelData.rel : ""); role: "bodyS"; mono: true; color: rc.modelData.overdue ? Theme.color.waiting : Theme.color.fgDim }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(rc.index, 0) }
            }
          }
        }
        DText { visible: t.rows.length === 0; text: "Nothing due or scheduled."; role: "bodyS"; dim: true }
      }
    }
  }

  ColumnLayout {
    visible: t.model !== null
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    spacing: 16

    Card {
      objectName: "salahCard"
      Layout.fillWidth: true
      Column {
        width: parent.width
        spacing: 8
        Head { text: "Salah next"; icon: "mosque" }
        DText { text: t.model && t.model.salah ? t.model.salah.prayer : "none left today"; role: "headline" }
        DText { visible: t.model && t.model.salah !== null; text: t.model && t.model.salah ? "iqamah " + t.model.salah.at + ", " + t.model.salah.rel : ""; role: "bodyS"; mono: true; dim: true }
      }
    }
    Card {
      objectName: "remindersNote"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      implicitHeight: 0
      clip: true
      Column {
        width: parent.width
        spacing: 8
        Cap { text: "ABOUT THIS LIST" }
        DText { width: parent.width; text: t.status !== "" ? t.status : "Read from the task list. s hides a row until the control centre closes, d marks it handled here. Neither changes the task list."; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
      }
    }
  }
}
