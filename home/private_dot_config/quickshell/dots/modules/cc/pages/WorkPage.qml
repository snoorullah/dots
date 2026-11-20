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
Item {
  id: pg
  objectName: "workPage"
  property bool dim: false
  clip: true

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
  // "HD 8580 Fix the thing": the ticket and a short description, never a TASK- or local: id
  function itemLabel(it) { return Q.label(it.ticket, it.ref, it.title) || "Untitled" }
  function itemTicket(it) { return it.ticket || Q.humanRef(it.ref, it.title) }
  readonly property string taskLabel: task ? (Q.label(task.ticket, task.ref, task.desc) || "Untitled") : ""
  function dueText(u) { return u === "critical" ? "Now" : (u === "time" ? "Due" : (u === "active" ? "Today" : "")) }

  // Header, NOW card and sub-tabs are fixed. The page never scrolls: only the long lists
  // (today's order, board columns, the All table) scroll, each inside its own clipped area.
  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: 24
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
      DText { text: "Your feed, as one list. Duplicates merged."; role: "bodyS"; dim: true; elide: Text.ElideRight; Layout.maximumWidth: 360 }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 16
      Card {
        objectName: "nowCard"
        Layout.fillWidth: true
        Layout.preferredWidth: 8
        Layout.minimumWidth: 0
        implicitHeight: 150
        clip: true
        Column {
          width: parent.width
          Cap { text: "NOW" }
          DText { text: pg.task ? pg.taskLabel : "No task in hand"; role: "page"; width: parent.width; elide: Text.ElideRight; opacity: pg.task ? 1 : 0.5 }
          DText { text: pg.task ? (pg.task.project || "") : "Start one from Today, in order."; role: "bodyS"; dim: true; width: parent.width; elide: Text.ElideRight }
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
        Layout.minimumWidth: 0
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
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      spacing: 16
      Card {
        objectName: "todayListCard"
        Layout.fillWidth: true
        Layout.preferredWidth: 5
        Layout.minimumWidth: 0
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: 0
        pad: 16
        clip: true
        Head { id: todayHead; text: "Today, in order"; icon: "list-numbers"; bottomPadding: 8 }
        Flickable {
          id: todayScroll
          objectName: "todayScroll"
          anchors.top: todayHead.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(0, parent.height - todayHead.height)
          clip: true
          contentWidth: width
          contentHeight: todayCol.height
          boundsBehavior: Flickable.StopAtBounds
          Column {
            id: todayCol
            width: todayScroll.width
            Repeater {
              model: CcState.nextTasks
              Item {
                id: tr
                required property var modelData
                required property int index
                objectName: "todayRow"
                width: todayCol.width
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
                    Layout.minimumWidth: 0
                    spacing: 0
                    DText { objectName: "todayRowTitle"; Layout.fillWidth: true; text: pg.itemLabel(tr.modelData); role: "body"; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                    DText { Layout.fillWidth: true; text: tr.modelData.actor || "You"; role: "bodyS"; dim: true; elide: Text.ElideRight }
                  }
                  DText { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: pg.dueText(tr.modelData.urgency); role: "bodyS"; elide: Text.ElideRight; color: (tr.modelData.urgency === "critical" || tr.modelData.urgency === "time") ? Theme.color.waiting : Theme.color.fgDim }
                }
              }
            }
            DText { visible: CcState.nextTasks.length === 0; text: "Nothing picked for today."; role: "bodyS"; dim: true; topPadding: 8 }
          }
        }
      }
      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 4
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        pad: 16
        clip: true
        Column {
          width: parent.width
          Head { text: "Waiting on others"; icon: "hourglass-medium"; bottomPadding: 8 }
          DText { text: "No data source yet. The feed does not say who a task waits on."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredWidth: 3
        Layout.minimumWidth: 0
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        spacing: 16
        Card {
          Layout.fillWidth: true
          pad: 16
          clip: true
          Column {
            width: parent.width
            Head { text: "Your captures"; icon: "note-pencil"; bottomPadding: 8 }
            DText { text: "No data source yet."; role: "bodyS"; dim: true }
          }
        }
        Card {
          objectName: "untickCard"
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          implicitHeight: 0
          pad: 16
          clip: true
          Head { id: untickHead; text: "Unticketed work"; icon: "ticket" }
          Flickable {
            id: untickScroll
            objectName: "untickScroll"
            anchors.top: untickHead.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(0, parent.height - untickHead.height - 8)
            clip: true
            contentWidth: width
            contentHeight: untickCol.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: untickCol
              width: untickScroll.width
              spacing: 8
              Repeater { model: pg.untracked; DText { required property var modelData; text: Q.plainDesc(modelData.title) || modelData.title; role: "bodyS"; width: untickCol.width; wrapMode: Text.Wrap } }
              DText { visible: pg.untracked.length === 0; text: "None today."; role: "bodyS"; dim: true }
              Btn { visible: pg.untracked.length > 0; text: "Make ticket"; icon: "ticket"; stub: true }
            }
          }
        }
      }
    }

    // ---- Board ----
    RowLayout {
      objectName: "taskBoard"
      visible: CcState.taskView === "Board"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      spacing: 12
      Repeater {
        model: [
          { name: "Next", items: CcState.nextTasks.map(function (t) { return pg.itemLabel(t) }) },
          { name: "Doing", items: pg.task ? [pg.taskLabel] : [] },
          { name: "With an agent", items: CcState.agents.filter(function (a) { return a.tone === "" }).map(function (a) { return a.name }) },
          { name: "Waiting", items: pg.waitingItems.map(function (t) { return pg.itemLabel(t) }) }
        ]
        Rectangle {
          id: bc
          required property var modelData
          objectName: "boardCol"
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.minimumWidth: 0
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          radius: Theme.radius.card
          color: Theme.color.surface
          clip: true
          Row {
            id: bhead
            x: 12
            y: 12
            spacing: 6
            DText { text: bc.modelData.name; role: "bodyS"; font.weight: Font.DemiBold; dim: true }
            DText { text: bc.modelData.items.length; role: "bodyS"; dim: true }
          }
          Flickable {
            id: bscroll
            objectName: "boardScroll"
            x: 12
            y: bhead.y + bhead.height + 8
            width: parent.width - 24
            height: Math.max(0, parent.height - y - 12)
            clip: true
            contentWidth: width
            contentHeight: bcol.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: bcol
              width: bscroll.width
              spacing: 8
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
    }

    // ---- All ----
    ColumnLayout {
      objectName: "taskAll"
      visible: CcState.taskView === "All"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      spacing: 4
      DText { text: "All tasks"; role: "headline" }
      DText { text: "Every source, one row per real piece of work. Duplicates merged."; role: "bodyS"; dim: true; bottomPadding: 12; Layout.fillWidth: true; elide: Text.ElideRight }
      RowLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
          model: [["WORK", 0], ["LIVES IN", 220], ["DUE", 110], ["FROM", 140], ["TODAY", 80]]
          Cap { required property var modelData; Layout.preferredWidth: modelData[1] > 0 ? modelData[1] : -1; Layout.fillWidth: modelData[1] === 0; Layout.leftMargin: 8; text: modelData[0] }
        }
      }
      Flickable {
        id: allScroll
        objectName: "allScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: width
        contentHeight: allCol.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: allCol
          width: allScroll.width
          Repeater {
            model: CcState.nextTasks
            Item {
              id: ar
              required property var modelData
              objectName: "allRow"
              width: allCol.width
              height: 49
              Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
              RowLayout {
                anchors.fill: parent
                anchors.topMargin: 1
                spacing: 0
                DText { Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.leftMargin: 8; text: Q.plainDesc(ar.modelData.title) || pg.itemLabel(ar.modelData); role: "body"; font.weight: Font.Medium; elide: Text.ElideRight }
                DText { Layout.preferredWidth: 220; Layout.leftMargin: 8; text: pg.itemTicket(ar.modelData) || "terminal only"; role: "bodyS"; dim: true; elide: Text.ElideRight }
                DText { Layout.preferredWidth: 110; Layout.leftMargin: 8; text: pg.dueText(ar.modelData.urgency); role: "bodyS"; elide: Text.ElideRight }
                DText { Layout.preferredWidth: 140; Layout.leftMargin: 8; text: ar.modelData.actor || "You"; role: "bodyS"; dim: true; elide: Text.ElideRight }
                DText { Layout.preferredWidth: 80; Layout.leftMargin: 8; text: ""; role: "bodyS" }
              }
            }
          }
          DText { visible: CcState.nextTasks.length === 0; text: "No tasks in the feed."; role: "title"; font.weight: Font.Normal; dim: true; topPadding: 16 }
        }
      }
    }
  }
}
