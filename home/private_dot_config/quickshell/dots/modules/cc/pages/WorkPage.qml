pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview
import "../js/Queue.js" as Q

// Tasks: the task in hand, then Today / Board / All over what the feed knows. Anything the
// feed has no field for (blocked-on-others, captures list) says "no data" rather than inventing rows.
Flickable {
  id: pg
  property bool dim: false
  clip: true
  contentWidth: width
  contentHeight: col.height + 48
  boundsBehavior: Flickable.StopAtBounds

  readonly property var task: Feed.task
  readonly property int taskSec: {
    if (!task) return 0
    var rows = Feed.today ? Feed.today.byRef : []
    for (var i = 0; i < rows.length; i++) if (rows[i].ref === task.ref) return rows[i].sec
    return task.startedAt ? Math.max(0, Feed.nowTs - task.startedAt) : 0
  }
  readonly property var untracked: {
    var out = []
    CcState.all.forEach(function (it) { if (it.kind === "capture") out.push(it) })
    return out
  }
  readonly property var waitingItems: {
    var out = []
    CcState.all.forEach(function (it) { if (it.tone === "wait") out.push(it) })
    return out
  }
  function dueText(u) { return u === "critical" ? "Now" : (u === "time" ? "Due" : (u === "active" ? "Today" : "")) }

  ColumnLayout {
    id: col
    x: 24
    y: 24
    width: pg.width - 48
    spacing: 16

    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      DText { text: "Tasks"; role: "headline"; Layout.rightMargin: 12 }
      Repeater {
        model: [["Today", "calendar-check"], ["Board", "kanban"], ["All", "list-bullets"]]
        Seg { required property var modelData; objectName: "taskView"; text: modelData[0]; icon: modelData[1]; h: 28; on: CcState.taskView === modelData[0]; onClicked: CcState.taskView = modelData[0] }
      }
      Item { Layout.fillWidth: true }
      DText { text: "Your feed, as one list. Duplicates merged."; role: "bodyS"; dim: true }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 16
      Card {
        objectName: "nowCard"
        Layout.fillWidth: true
        Layout.preferredWidth: 8
        implicitHeight: 150
        Column {
          anchors.fill: parent
          Column {
            width: parent.width
            Cap { text: "NOW" }
            DText { text: pg.task ? pg.task.desc : "No task in hand"; role: "page"; width: parent.width; elide: Text.ElideRight; opacity: pg.task ? 1 : 0.5 }
            DText { text: pg.task ? ((pg.task.ref || "") + (pg.task.project ? " · " + pg.task.project : "")) : "Start one from Today, in order."; role: "bodyS"; dim: true; width: parent.width; elide: Text.ElideRight }
          }
        }
        Row {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          spacing: 8
          Btn { text: "Done"; icon: "check"; primary: true; stub: true }
          Btn { objectName: "nowBreakdown"; text: "Break down with agent"; icon: "tree-structure"; blocked: !pg.task || !pg.task.ref; onClicked: Actions.breakdown(pg.task) }
          Btn { text: "Blocked on someone"; icon: "prohibit"; stub: true }
          Btn { text: "Comment"; icon: "chat-circle"; stub: true }
          Btn { text: "Copy link"; icon: "link"; stub: true }
        }
      }
      Stat {
        Layout.fillWidth: true
        Layout.preferredWidth: 4
        implicitHeight: 150
        label: "Time on this task"
        icon: "timer"
        value: Q.hm(pg.taskSec)
        note: pg.task ? "since it was started" : "no task in hand"
        dim: !pg.task
      }
    }

    // ---- Today ----
    RowLayout {
      objectName: "taskToday"
      visible: CcState.taskView === "Today"
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: 16
      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 5
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          width: parent.width
          Head { text: "Today, in order"; icon: "list-numbers"; bottomPadding: 8 }
          Repeater {
            model: CcState.nextTasks
            Item {
              id: tr
              required property var modelData
              required property int index
              objectName: "todayRow"
              width: parent.width
              height: 56
              Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 8
                DText { Layout.preferredWidth: 24; text: String(tr.index + 1); role: "bodyS"; dim: true }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  DText { Layout.fillWidth: true; text: tr.modelData.title; role: "body"; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                  DText { Layout.fillWidth: true; text: tr.modelData.ref || ""; role: "bodyS"; dim: true; elide: Text.ElideRight }
                }
                DText { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: pg.dueText(tr.modelData.urgency); role: "bodyS"; color: (tr.modelData.urgency === "critical" || tr.modelData.urgency === "time") ? Theme.color.waiting : Theme.color.fgDim }
              }
            }
          }
          DText { visible: CcState.nextTasks.length === 0; text: "Nothing picked for today."; role: "bodyS"; dim: true; topPadding: 8 }
        }
      }
      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 4
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          width: parent.width
          Head { text: "Waiting on others"; icon: "hourglass-medium"; bottomPadding: 8 }
          DText { text: "No data source yet. The feed does not say who a task waits on."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredWidth: 3
        Layout.alignment: Qt.AlignTop
        spacing: 16
        Card {
          Layout.fillWidth: true
          pad: 16
          Column {
            width: parent.width
            Head { text: "Your captures"; icon: "note-pencil"; bottomPadding: 8 }
            DText { text: "No data source yet."; role: "bodyS"; dim: true }
          }
        }
        Card {
          Layout.fillWidth: true
          pad: 16
          Column {
            width: parent.width
            spacing: 8
            Head { text: "Unticketed work"; icon: "ticket" }
            Repeater { model: pg.untracked; DText { required property var modelData; text: modelData.title; role: "bodyS"; width: parent.width; wrapMode: Text.Wrap } }
            DText { visible: pg.untracked.length === 0; text: "None today."; role: "bodyS"; dim: true }
            Btn { visible: pg.untracked.length > 0; text: "Make ticket"; icon: "ticket"; stub: true }
          }
        }
      }
    }

    // ---- Board ----
    RowLayout {
      objectName: "taskBoard"
      visible: CcState.taskView === "Board"
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: 12
      Repeater {
        model: [
          { name: "Next", items: CcState.nextTasks.map(function (t) { return t.title }) },
          { name: "Doing", items: pg.task ? [pg.task.desc] : [] },
          { name: "With an agent", items: CcState.agents.filter(function (a) { return a.tone === "" }).map(function (a) { return a.name }) },
          { name: "Waiting", items: pg.waitingItems.map(function (t) { return t.title }) }
        ]
        Rectangle {
          id: bc
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.alignment: Qt.AlignTop
          implicitHeight: bcol.implicitHeight + 24
          radius: Theme.radius.card
          color: Theme.color.surface
          Column {
            id: bcol
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 8
            Row {
              spacing: 6
              DText { text: bc.modelData.name; role: "bodyS"; font.weight: Font.DemiBold; dim: true }
              DText { text: bc.modelData.items.length; role: "bodyS"; dim: true }
            }
            Repeater {
              model: bc.modelData.items
              Rectangle {
                required property string modelData
                width: bcol.width
                height: ct.implicitHeight + 20
                radius: Theme.radius.row
                color: Theme.color.surfaceContainer
                DText { id: ct; x: 10; y: 10; width: parent.width - 20; text: parent.modelData; role: "bodyS"; wrapMode: Text.Wrap }
              }
            }
          }
        }
      }
    }

    // ---- All ----
    ColumnLayout {
      objectName: "taskAll"
      visible: CcState.taskView === "All"
      Layout.fillWidth: true
      spacing: 4
      DText { text: "All tasks"; role: "headline" }
      DText { text: "Every source, one row per real piece of work. Duplicates merged."; role: "bodyS"; dim: true; bottomPadding: 12 }
      RowLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
          model: [["WORK", 0], ["LIVES IN", 220], ["DUE", 110], ["FROM", 140], ["TODAY", 80]]
          Cap { required property var modelData; Layout.preferredWidth: modelData[1] > 0 ? modelData[1] : -1; Layout.fillWidth: modelData[1] === 0; Layout.leftMargin: 8; text: modelData[0] }
        }
      }
      Repeater {
        model: CcState.nextTasks
        Item {
          id: ar
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 49
          Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
          RowLayout {
            anchors.fill: parent
            anchors.topMargin: 1
            spacing: 0
            DText { Layout.fillWidth: true; Layout.leftMargin: 8; text: ar.modelData.title; role: "body"; font.weight: Font.Medium; elide: Text.ElideRight }
            DText { Layout.preferredWidth: 220; Layout.leftMargin: 8; text: ar.modelData.ref || "terminal only"; role: "bodyS"; dim: true; elide: Text.ElideRight }
            DText { Layout.preferredWidth: 110; Layout.leftMargin: 8; text: pg.dueText(ar.modelData.urgency); role: "bodyS" }
            DText { Layout.preferredWidth: 140; Layout.leftMargin: 8; text: ar.modelData.actor || "You"; role: "bodyS"; dim: true }
            DText { Layout.preferredWidth: 80; Layout.leftMargin: 8; text: ""; role: "bodyS" }
          }
        }
      }
      DText { visible: CcState.nextTasks.length === 0; text: "No tasks in the feed."; role: "title"; font.weight: Font.Normal; dim: true; topPadding: 16 }
    }
  }
}
