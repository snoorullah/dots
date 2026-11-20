pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview
import qs.modules.overview.parts as Ov
import "../js/Queue.js" as Q

// Time: sub-tabs over activity.json, heatmap.json and mirror.json. Sub-tabs whose data
// the overview files do not carry (Days, Focus zones, Progress, Screen and health, Reminders)
// show one card saying so.
Flickable {
  id: pg
  property bool dim: false
  clip: true
  contentWidth: width
  contentHeight: col.height + 48
  boundsBehavior: Flickable.StopAtBounds

  readonly property var tabs: ["Today", "Week", "Days", "Heatmap", "Focus zones", "Progress", "Report", "Screen and health", "Reminders"]
  readonly property var today: Feed.today
  readonly property var buckets: Feed.actDoc ? Feed.actDoc.buckets : null
  readonly property var rows: Q.timeRows(today, CcState.timeBy)
  readonly property var weekRows: Q.timeRows(buckets ? buckets.week : null, "Project")
  readonly property var weekItems: Q.timeRows(buckets ? buckets.week : null, "Item")
  readonly property var heat: Q.heatTotals(Feed.heatDoc ? Feed.heatDoc.days : [])
  readonly property var done: {
    var out = []
    var refs = Feed.mirrorDoc ? Feed.mirrorDoc.refs : []
    for (var i = 0; i < refs.length; i++) {
      var r = refs[i]
      if (r.closedAt && Feed.nowTs - r.closedAt < 86400) out.push("Closed " + (r.title || r.ref))
      else if (r.reviewedAt && Feed.nowTs - r.reviewedAt < 86400) out.push("Reviewed " + (r.title || r.ref))
    }
    return out
  }
  readonly property bool implemented: CcState.timeTab === "Today" || CcState.timeTab === "Week" || CcState.timeTab === "Heatmap" || CcState.timeTab === "Report"
  readonly property real dayElapsed: CcState.loginTs > 0 ? Math.max(0, Feed.nowTs - CcState.loginTs) : -1

  ColumnLayout {
    id: col
    x: 24
    y: 24
    width: pg.width - 48
    spacing: 16

    Row {
      spacing: 2
      Repeater {
        model: pg.tabs
        Seg { required property string modelData; objectName: "timeTab"; text: modelData; h: 28; pad: 12; on: CcState.timeTab === modelData; onColor: Theme.color.outlineVariant; onClicked: CcState.timeTab = modelData }
      }
    }

    // ---- Today ----
    GridLayout {
      objectName: "timeToday"
      visible: CcState.timeTab === "Today"
      Layout.fillWidth: true
      columns: 3
      columnSpacing: 16
      rowSpacing: 16

      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Day so far"; icon: "sign-out"; value: pg.dayElapsed >= 0 ? Q.hm(pg.dayElapsed) : "--:--"; note: pg.dayElapsed >= 0 ? "since you logged in at " + Q.clock(CcState.loginTs) : "no session open"; dim: pg.dayElapsed < 0 }
      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "This week"; icon: "calendar-blank"; value: Q.hm(pg.buckets ? pg.buckets.week.workedSec : 0); note: (pg.buckets ? pg.buckets.week.tasksDone : 0) + " tasks done" }
      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "This month"; icon: "calendar-dots"; value: Q.hm(pg.buckets ? pg.buckets.month.workedSec : 0); note: (pg.buckets ? pg.buckets.month.tasksDone : 0) + " tasks done" }

      Card {
        Layout.columnSpan: 2
        Layout.fillWidth: true
        Layout.preferredWidth: 2
        Layout.alignment: Qt.AlignTop
        Column {
          width: parent.width
          spacing: 12
          Head { text: "Today"; icon: "clock" }
          Row {
            objectName: "todayBar"
            width: parent.width
            height: 28
            spacing: 2
            Repeater {
              model: pg.today ? pg.today.byProject : []
              Rectangle {
                required property var modelData
                required property int index
                width: Math.max(2, (parent.width - 2 * Math.max(0, pg.today.byProject.length - 1)) * modelData.sec / Math.max(1, pg.today.workedSec))
                height: 28
                radius: 4
                color: Qt.alpha(Theme.color.accent, 1 - Math.min(0.6, index * 0.25))
              }
            }
          }
          DText { text: pg.today ? Q.hm(pg.today.workedSec) + " worked across " + pg.today.byProject.length + " projects." : "No activity yet today."; role: "bodyS"; dim: true }
        }
      }
      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        Column {
          width: parent.width
          spacing: 8
          Head { text: "Focus"; icon: "crosshair" }
          DText { text: Feed.focusRunning ? ("Running, " + Q.hm(Feed.focusElapsed) + " of " + Q.hm(Feed.focusTarget)) : (Feed.focus && Feed.focus.state === "break" ? "On a break." : "Not running."); role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
          Row {
            spacing: 8
            Btn { objectName: "focusStart"; visible: !Feed.focusRunning; text: "Start"; icon: "timer"; onClicked: Actions.focus("start") }
            Btn { objectName: "focusStop"; visible: Feed.focusRunning; text: "Stop"; onClicked: Actions.focus("stop") }
            Btn { objectName: "focusBreak"; text: "Break"; onClicked: Actions.focus("break") }
          }
        }
      }

      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          width: parent.width
          spacing: 10
          Cap { text: "NEXT" }
          DText { text: CcState.nextTasks.length ? CcState.nextTasks[0].title : "Nothing picked"; role: "headline"; font.weight: Font.Normal; width: parent.width; wrapMode: Text.Wrap }
          DText { text: CcState.nextTasks.length > 1 ? "Then: " + CcState.nextTasks.slice(1, 3).map(function (t) { return t.title }).join(", ") : ""; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        }
      }
      Card {
        objectName: "whereTime"
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          width: parent.width
          spacing: 10
          Cap { text: "WHERE TIME WENT" }
          Row {
            spacing: 2
            Repeater {
              model: ["Project", "Item", "Agent", "App"]
              Seg { required property string modelData; objectName: "timeBy"; text: modelData; h: 24; pad: 10; on: CcState.timeBy === modelData; onColor: Theme.color.outlineVariant; onClicked: CcState.timeBy = modelData }
            }
          }
          Repeater {
            model: pg.rows
            TimeRow { required property var modelData; width: parent.width; n: modelData.n; v: modelData.v; w: modelData.w }
          }
          DText { visible: pg.rows.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
        }
      }
      Card {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          width: parent.width
          spacing: 6
          Cap { text: "DONE TODAY" }
          Repeater { model: pg.done; DText { required property string modelData; width: parent.width; text: modelData; role: "bodyS"; elide: Text.ElideRight } }
          DText { visible: pg.done.length === 0; text: "Nothing closed or reviewed yet."; role: "bodyS"; dim: true }
        }
      }
    }

    // ---- Week ----
    GridLayout {
      objectName: "timeWeek"
      visible: CcState.timeTab === "Week"
      Layout.fillWidth: true
      columns: 3
      columnSpacing: 16
      rowSpacing: 16
      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Week"; icon: "calendar-blank"; value: Q.hm(pg.buckets ? pg.buckets.week.workedSec : 0); note: (pg.buckets ? pg.buckets.week.tasksDone : 0) + " tasks done" }
      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Month"; icon: "calendar-dots"; value: Q.hm(pg.buckets ? pg.buckets.month.workedSec : 0); note: (pg.buckets ? pg.buckets.month.tasksDone : 0) + " tasks done" }
      Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Quarter"; icon: "calendar-check"; value: Q.hm(pg.buckets ? pg.buckets.quarter.workedSec : 0); note: (pg.buckets ? pg.buckets.quarter.tasksDone : 0) + " tasks done" }
      Card {
        Layout.columnSpan: 3
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Row {
          width: parent.width
          spacing: 32
          Column {
            width: (parent.width - 32) / 2
            spacing: 8
            Cap { text: "BY PROJECT" }
            Repeater { model: pg.weekRows; TimeRow { required property var modelData; width: parent.width; n: modelData.n; v: modelData.v } }
            DText { visible: pg.weekRows.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
          }
          Column {
            width: (parent.width - 32) / 2
            spacing: 8
            Cap { text: "BY ITEM" }
            Repeater { model: pg.weekItems; TimeRow { required property var modelData; width: parent.width; n: modelData.n; v: modelData.v } }
            DText { visible: pg.weekItems.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
          }
        }
      }
    }

    // ---- Heatmap ----
    Card {
      objectName: "timeHeat"
      visible: CcState.timeTab === "Heatmap"
      Layout.fillWidth: true
      Column {
        width: parent.width
        spacing: 16
        Cap { text: "LAST 119 DAYS" }
        Ov.Heatmap { cellSize: 18; gap: 4; labels: true; days: Feed.heatDoc ? Feed.heatDoc.days : [] }
        Row {
          spacing: 40
          Column { Cap { text: "TOTAL" } DText { text: Q.hm(pg.heat.totalSec); role: "headline" } }
          Column { Cap { text: "DAYS WORKED" } DText { text: String(pg.heat.daysWorked); role: "headline" } }
          Column { Cap { text: "DAILY AVERAGE" } DText { text: Q.hm(pg.heat.avgSec); role: "headline" } }
          Column { Cap { text: "BEST DAY" } DText { text: pg.heat.best ? Q.hm(pg.heat.best.sec) + ", " + pg.heat.best.d : "-"; role: "headline" } }
        }
      }
    }

    // ---- Report ----
    Card {
      objectName: "timeReport"
      visible: CcState.timeTab === "Report"
      Layout.fillWidth: true
      Column {
        width: parent.width
        spacing: 12
        Head { text: "Report"; icon: "list-bullets" }
        DText { text: "Builds today's report with the local tracker. Nothing is sent."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        Btn { objectName: "runReport"; text: "Run report"; icon: "list-plus"; onClicked: Actions.report() }
      }
    }

    // ---- everything else ----
    Card {
      objectName: "timeNoData"
      visible: !pg.implemented
      Layout.fillWidth: true
      Column {
        width: parent.width
        spacing: 8
        Head { text: CcState.timeTab; icon: "clock" }
        DText { text: "No data source yet. The overview files do not carry this view."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
      }
    }
  }
}
