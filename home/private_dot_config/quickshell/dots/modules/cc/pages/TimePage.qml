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
Item {
  id: pg
  objectName: "timePage"
  property bool dim: false
  clip: true

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
  // "HD 8580 Fix the thing": the ticket and a short description, never a TASK- or local: id
  function nextLabel(t) { return Q.label(t.ticket, t.ref, t.title) || "Untitled" }
  readonly property bool implemented: CcState.timeTab === "Today" || CcState.timeTab === "Week" || CcState.timeTab === "Heatmap" || CcState.timeTab === "Report"
  readonly property real dayElapsed: CcState.loginTs > 0 ? Math.max(0, Feed.nowTs - CcState.loginTs) : -1

  // Header and sub-tabs are fixed. The page itself never scrolls: on Today only the right-hand
  // list scrolls; the other sub-tabs fit their card and are clipped.
  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: 24
    spacing: 16

    Flow {
      Layout.fillWidth: true
      spacing: 2
      Repeater {
        model: pg.tabs
        Seg { required property string modelData; objectName: "timeTab"; text: modelData; h: 28; pad: 12; on: CcState.timeTab === modelData; onColor: Theme.color.outlineVariant; onClicked: CcState.timeTab = modelData }
      }
    }

    // ---- Today ----
    ColumnLayout {
      objectName: "timeToday"
      visible: CcState.timeTab === "Today"
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 16

      RowLayout {
        Layout.fillWidth: true
        spacing: 16
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "Day so far"; icon: "sign-out"; value: pg.dayElapsed >= 0 ? Q.hm(pg.dayElapsed) : "--:--"; note: pg.dayElapsed >= 0 ? "since you logged in at " + Q.clock(CcState.loginTs) : "no session open"; dim: pg.dayElapsed < 0 }
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "This week"; icon: "calendar-blank"; value: Q.hm(pg.buckets ? pg.buckets.week.workedSec : 0); note: (pg.buckets ? pg.buckets.week.tasksDone : 0) + " tasks done" }
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; label: "This month"; icon: "calendar-dots"; value: Q.hm(pg.buckets ? pg.buckets.month.workedSec : 0); note: (pg.buckets ? pg.buckets.month.tasksDone : 0) + " tasks done" }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16

        // left two thirds: fixed
        ColumnLayout {
          Layout.fillWidth: true
          Layout.preferredWidth: 2
          Layout.fillHeight: true
          spacing: 16

          Card {
            objectName: "todayCard"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Column {
              width: parent.width
              spacing: 12
              Head { text: "Today"; icon: "clock" }
              Item {
                id: barBox
                objectName: "todayBar"
                width: parent.width
                height: 28
                clip: true
                readonly property var segs: pg.today ? pg.today.byProject : []
                readonly property var widths: Q.barWidths(segs.map(function (p) { return p.sec }), width, 2)
                Repeater {
                  model: barBox.segs
                  Rectangle {
                    required property var modelData
                    required property int index
                    x: {
                      var sum = 0
                      for (var i = 0; i < index; i++) sum += barBox.widths[i] + 2
                      return sum
                    }
                    width: barBox.widths[index] || 0
                    height: 28
                    radius: 4
                    color: Qt.alpha(Theme.color.accent, 1 - Math.min(0.6, index * 0.25))
                  }
                }
              }
              DText { text: pg.today ? Q.hm(pg.today.workedSec) + " worked across " + pg.today.byProject.length + " projects." : "No activity yet today."; role: "bodyS"; dim: true }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            spacing: 16
            Card {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignTop
              pad: 16
              clip: true
              Column {
                width: parent.width
                spacing: 10
                Cap { text: "NEXT" }
                DText { text: CcState.nextTasks.length ? pg.nextLabel(CcState.nextTasks[0]) : "Nothing picked"; role: "headline"; font.weight: Font.Normal; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
                DText { text: CcState.nextTasks.length > 1 ? "Then: " + CcState.nextTasks.slice(1, 3).map(pg.nextLabel).join(", ") : ""; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight }
              }
            }
            Card {
              objectName: "whereTime"
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.minimumWidth: 0
              Layout.fillHeight: true
              Layout.minimumHeight: 0
              implicitHeight: 0
              pad: 16
              clip: true
              Column {
                id: whereHead
                width: parent.width
                spacing: 10
                Cap { text: "WHERE TIME WENT" }
                Flow {
                  width: parent.width
                  spacing: 2
                  Repeater {
                    model: ["Project", "Item", "Agent", "App"]
                    Seg { required property string modelData; objectName: "timeBy"; text: modelData; h: 24; pad: 10; on: CcState.timeBy === modelData; onColor: Theme.color.outlineVariant; onClicked: CcState.timeBy = modelData }
                  }
                }
              }
              Flickable {
                id: whereScroll
                objectName: "whereScroll"
                anchors.top: whereHead.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.max(0, parent.height - whereHead.height - 10)
                clip: true
                contentWidth: width
                contentHeight: whereCol.height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: whereCol
                  width: whereScroll.width
                  spacing: 10
                  Repeater {
                    model: pg.rows
                    TimeRow { required property var modelData; width: whereCol.width; n: modelData.n; v: modelData.v; w: modelData.w }
                  }
                  DText { visible: pg.rows.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
                }
              }
            }
          }
        }

        // right third: Focus fixed, "Done today" scrolls on its own
        ColumnLayout {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.fillHeight: true
          spacing: 16

          Card {
            Layout.fillWidth: true
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
            objectName: "doneCard"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: 0
            pad: 16
            clip: true
            Cap { id: doneCap; text: "DONE TODAY" }
            Flickable {
              id: doneScroll
              objectName: "doneScroll"
              anchors.top: doneCap.bottom
              anchors.topMargin: 10
              anchors.left: parent.left
              anchors.right: parent.right
              height: Math.max(0, parent.height - doneCap.height - 10)
              clip: true
              contentWidth: width
              contentHeight: doneCol.height
              boundsBehavior: Flickable.StopAtBounds
              Column {
                id: doneCol
                width: doneScroll.width
                spacing: 6
                Repeater { model: pg.done; DText { required property string modelData; width: doneCol.width; text: modelData; role: "bodyS"; elide: Text.ElideRight } }
                DText { visible: pg.done.length === 0; text: "Nothing closed or reviewed yet."; role: "bodyS"; dim: true }
              }
            }
          }
        }
      }
    }

    // ---- Week ----
    ColumnLayout {
      objectName: "timeWeek"
      visible: CcState.timeTab === "Week"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      spacing: 16
      RowLayout {
        Layout.fillWidth: true
        spacing: 16
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignTop; label: "Week"; icon: "calendar-blank"; value: Q.hm(pg.buckets ? pg.buckets.week.workedSec : 0); note: (pg.buckets ? pg.buckets.week.tasksDone : 0) + " tasks done" }
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignTop; label: "Month"; icon: "calendar-dots"; value: Q.hm(pg.buckets ? pg.buckets.month.workedSec : 0); note: (pg.buckets ? pg.buckets.month.tasksDone : 0) + " tasks done" }
        Stat { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignTop; label: "Quarter"; icon: "calendar-check"; value: Q.hm(pg.buckets ? pg.buckets.quarter.workedSec : 0); note: (pg.buckets ? pg.buckets.quarter.tasksDone : 0) + " tasks done" }
      }
      // the two lists share the card; each scrolls on its own
      Card {
        objectName: "weekCard"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: 0
        clip: true
        Item {
          id: weekProj
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: (parent.width - 32) / 2
          Cap { id: wpCap; text: "BY PROJECT" }
          Flickable {
            id: wpScroll
            objectName: "weekScroll"
            anchors.top: wpCap.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            contentWidth: width
            contentHeight: wpCol.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: wpCol
              width: wpScroll.width
              spacing: 8
              Repeater { model: pg.weekRows; TimeRow { required property var modelData; width: wpCol.width; n: modelData.n; v: modelData.v } }
              DText { visible: pg.weekRows.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
            }
          }
        }
        Item {
          id: weekItem
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: (parent.width - 32) / 2
          Cap { id: wiCap; text: "BY ITEM" }
          Flickable {
            id: wiScroll
            objectName: "weekScroll"
            anchors.top: wiCap.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            contentWidth: width
            contentHeight: wiCol.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: wiCol
              width: wiScroll.width
              spacing: 8
              Repeater { model: pg.weekItems; TimeRow { required property var modelData; width: wiCol.width; n: modelData.n; v: modelData.v } }
              DText { visible: pg.weekItems.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
            }
          }
        }
      }
    }

    // ---- Heatmap ----
    Card {
      id: heatCard
      objectName: "timeHeat"
      visible: CcState.timeTab === "Heatmap"
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      clip: true
      Column {
        id: heatCol
        width: parent.width
        spacing: 16
        Cap { text: "LAST 119 DAYS" }
        // cells follow the card's width: 17 columns, the label column and the gaps taken off
        Ov.Heatmap {
          objectName: "heatGrid"
          gap: 4
          labels: true
          cellSize: Math.max(8, Math.min(28, Math.floor((heatCol.width - 56 - 16 * 4) / 17)))
          days: Feed.heatDoc ? Feed.heatDoc.days : []
        }
        Flow {
          width: parent.width
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
      Layout.alignment: Qt.AlignTop
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
      Layout.alignment: Qt.AlignTop
      Column {
        width: parent.width
        spacing: 8
        Head { text: CcState.timeTab; icon: "clock" }
        DText { text: "No data source yet. The overview files do not carry this view."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
      }
    }

    // sub-tabs that fit their card sit at the top; the rest of the page stays empty
    Item { visible: CcState.timeTab !== "Today" && CcState.timeTab !== "Week"; Layout.fillHeight: true }
  }
}
