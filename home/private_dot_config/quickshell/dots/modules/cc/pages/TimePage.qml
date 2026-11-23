pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview
import "../js/Queue.js" as Q
import "../js/Metrics.js" as M
import "../js/AgentMetrics.js" as AM
import "time"

// Time: ten sub-tabs. Today still reads the overview files (activity.json, mirror.json). Agents
// reads agent-metrics.json (through CcState). The other eight read metrics.json (docs/shell/specs/cc-time-kpis.md), which the daemon computes;
// a sub-tab whose section is missing says which source is missing instead of drawing zeros.
// Keys: the view resolves every key with js/Keys.js and offers it to handleKey() first.
Item {
  id: pg
  objectName: "timePage"
  property bool dim: false
  clip: true

  // ---- metrics.json ----------------------------------------------------------------------
  // tests point metricsPath at a fixture; in a session it is the overview's state dir
  property string metricsPath: Feed.dir + "/metrics.json"
  property string metricsText: ""
  readonly property var parsed: M.parse(metricsText, 0)
  readonly property real docAge: (parsed.doc && parsed.doc.ts > 0) ? Math.max(0, Feed.nowTs - parsed.doc.ts) : -1
  readonly property real docNow: (parsed.doc && parsed.doc.ts > 0) ? Math.max(Feed.nowTs, parsed.doc.ts) : Feed.nowTs
  property bool metricsTried: false
  // the age shown beside the sub-tabs: the file the current sub-tab reads
  readonly property real stampAge: {
    if (sub === "agents") { var a = CcState.agentMetrics.doc; return a && a.ts > 0 ? Math.max(0, Feed.nowTs - a.ts) : -1 }
    return parsed.state === "ok" ? docAge : -1
  }
  FileView {
    path: pg.metricsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { pg.metricsText = text(); pg.metricsTried = true }
    onLoadFailed: { pg.metricsText = ""; pg.metricsTried = true }
  }

  // ---- keyboard state ----------------------------------------------------------------------
  readonly property string sub: CcState.subId
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property var hiddenRem: ({})
  property string remStatus: ""
  readonly property bool inList: CcState.pane === "list" || CcState.pane === "detail"
  readonly property bool inDetail: CcState.pane === "detail"
  function setKs(patch) {
    var n = {}
    for (var k in ks) n[k] = ks[k]
    for (var p in patch) n[p] = patch[p]
    pg.ks = n
  }
  // the cursor starts on today (week, heatmap) once the numbers are in
  property bool seeded: false
  function seed() {
    if (!parsed.doc) return
    var c = M.initCursor(parsed.doc, sub, ks.weekOff)
    pg.setKs({ row: c.row, col: c.col, detail: false, scroll: 0 })
    pg.seeded = true
  }
  onParsedChanged: if (!seeded) seed()
  onSubChanged: {
    pg.setKs({ row: 0, col: 0, detail: false, scroll: 0 })
    pg.seeded = false
    pg.seed()
    if (CcState.pane === "detail") CcState.pane = "list"
  }
  Connections {
    target: CcState
    function onTimeScrolled(dy) { whereScroll.contentY = Math.max(0, Math.min(Math.max(0, whereScroll.contentHeight - whereScroll.height), whereScroll.contentY + dy)) }
    function onPaneChanged() { if (CcState.pane !== "detail" && pg.ks.detail) pg.setKs({ detail: false, scroll: 0 }) }
  }
  function extras() {
    var e = { weeks: M.weeksAvailable(parsed.doc), legend: 0, zones: 0, reminders: 0, agents: 0 }
    if (sub === "agents") e.agents = agentsTab.all.length
    if (!parsed.doc) return e
    if (sub === "week") e.legend = M.weekModel(parsed.doc, ks.weekOff).legend.length
    if (sub === "zones" && M.present(parsed.doc, "zones")) e.zones = M.zoneRanks(parsed.doc, ks.period === 2 ? "month" : "week").rows.length
    if (sub === "reminders") { var r = M.reminderRows(parsed.doc, hiddenRem, docNow); e.reminders = r ? r.rows.length : 0 }
    return e
  }
  function applyNav(r, st) {
    if (r.st.sub !== st.sub) CcState.timeTab = M.subName(r.st.sub)   // first: a sub-tab change resets the cursor
    pg.ks = { row: r.st.row, col: r.st.col, period: r.st.period, weekOff: r.st.weekOff, detail: r.st.detail, scroll: r.st.scroll }
    if (r.st.zone !== st.zone) CcState.pane = r.st.zone
  }
  function reminderAct(kind) {
    var m = M.reminderRows(parsed.doc, hiddenRem, docNow)
    var row = m ? m.rows[ks.row] : null
    if (!row) { pg.remStatus = "Nothing selected."; return }
    var h = {}
    for (var k in hiddenRem) h[k] = hiddenRem[k]
    h[row.key] = true
    pg.hiddenRem = h
    pg.remStatus = (kind === "done" ? "Marked handled here: " : "Hidden until the control centre closes: ") + row.desc + ". The task list is unchanged."
    pg.setKs({ row: Math.max(0, Math.min(ks.row, m.rows.length - 2)) })
  }
  // Enter or o on an agent row: focus that agent's herdr pane when it is live
  function agentJump(live) {
    if (live && CcState.jumpRow(live)) return
    var c = agentsTab.current()
    CcState.say(c.row && c.row.kind === "agent" ? c.row.label + " has no live pane to jump to." : "Only an agent row has a pane to jump to.")
  }
  // The view calls this with the resolved action before it applies it. True means taken.
  // The sub-tab whose side panels the keyboard scrolls (Week, Heatmap, Report, Screen and health)
  function scrollTarget() {
    return pg.sub === "week" ? weekTab : pg.sub === "heatmap" ? heatTab : pg.sub === "report" ? reportTab : pg.sub === "screen" ? screenTab : pg.sub === "agents" ? agentsTab : null
  }
  function handleKey(res, st) {
    var mine = ["move", "top", "bottom", "page", "col", "period", "primary", "scroll", "act.copy", "act.run", "act.snooze", "act.done", "act.open"]
    if (st.page !== "time" || st.sub === "today" || mine.indexOf(res.action) < 0) return false   // Today's keys live in CcState.apply
    var sc = pg.scrollTarget()
    if (sc && st.zone !== "detail" && (res.action === "scroll"
        || ((st.sub === "screen" || st.sub === "report") && ["move", "page", "top", "bottom"].indexOf(res.action) >= 0))) {
      var a = res.action, n = Number(res.arg) || 0
      sc.scrollBy(a === "top" ? -100000 : a === "bottom" ? 100000 : a === "page" ? n * 160 : a === "scroll" ? n * 80 : n * 40)
      return true
    }
    if (res.action === "act.run") { if (st.sub === "report") Actions.report(); return true }
    var s = { sub: st.sub, zone: st.zone, row: ks.row, col: ks.col, period: ks.period, weekOff: ks.weekOff, detail: ks.detail, scroll: ks.scroll }
    var r = M.nav(s, res.action, res.arg, M.dims(parsed.doc, s, extras()))
    if (r.effect === "openDay") {
      var day = M.cursorDay(parsed.doc, s)
      if (day !== "") r.st = M.openDay(r.st, parsed.doc, day)
    }
    pg.applyNav(r, st)
    if (r.effect === "copy") reportTab.copy()
    else if (r.effect === "export") reportTab.save()
    else if (r.effect === "snooze" || r.effect === "done") pg.reminderAct(r.effect)
    else if (r.effect === "jump") pg.agentJump(agentsTab.current().live)
    return true
  }

  readonly property var tabs: ["Today", "Week", "Days", "Heatmap", "Focus zones", "Progress", "Report", "Screen and health", "Reminders", "Agents"]
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
  readonly property real dayElapsed: CcState.loginTs > 0 ? Math.max(0, Feed.nowTs - CcState.loginTs) : -1

  // Header and sub-tabs are fixed. The page itself never scrolls: lists scroll inside their own
  // card, everything else fits and is clipped.
  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: 24
    spacing: 16

    RowLayout {
      Layout.fillWidth: true
      spacing: 16
      Flow {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
          model: pg.tabs
          Seg { required property string modelData; objectName: "timeTab"; text: modelData; h: 28; pad: 12; on: CcState.timeTab === modelData; focused: on && CcState.pane === "tabs"; onColor: Theme.color.outlineVariant; onClicked: CcState.timeTab = modelData }
        }
      }
      DText {
        objectName: "timeStamp"
        visible: pg.sub !== "today"
        text: pg.stampAge < 0 ? "" : (pg.stampAge > (pg.sub === "agents" ? AM.STALE_SEC : M.STALE_SEC) ? "stale, updated " : "updated ") + M.ago(pg.stampAge)
        role: "caption"
        font.capitalization: Font.MixedCase
        font.letterSpacing: 0
        color: pg.stampAge > (pg.sub === "agents" ? AM.STALE_SEC : M.STALE_SEC) ? Theme.color.waiting : Theme.color.fgDim
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
              FocusRing { kind: "pane"; focused: pg.inList && pg.sub === "today"; radius: Theme.radius.card }
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

    WeekTab {
      id: weekTab
      visible: pg.sub === "week"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
      legacyProjects: pg.weekRows; legacyItems: pg.weekItems
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
    }
    DaysTab {
      visible: pg.sub === "days"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList; inDetail: pg.inDetail
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
      onOpen: { pg.setKs({ detail: true, scroll: 0 }); CcState.pane = "detail" }
    }
    HeatTab {
      id: heatTab
      visible: pg.sub === "heatmap"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
      legacyDays: Feed.heatDoc ? Feed.heatDoc.days : []
      loaded: pg.metricsTried
      legacy: pg.heat
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
    }
    ZonesTab {
      visible: pg.sub === "zones"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
      onWindowPicked: function (p) { pg.setKs({ period: p, row: 0 }) }
    }
    ProgressTab {
      visible: pg.sub === "progress"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
      onPeriodPicked: function (p) { pg.setKs({ period: p }) }
    }
    ReportTab {
      id: reportTab
      visible: pg.sub === "report"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
      onPeriodPicked: function (p) { pg.setKs({ period: p }) }
    }
    ScreenTab {
      id: screenTab
      visible: pg.sub === "screen"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList
    }
    AgentsTab {
      id: agentsTab
      visible: pg.sub === "agents"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: CcState.agentMetrics; ks: pg.ks; inList: pg.inList; titles: CcState.refTitles; liveRows: CcState.agents
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
      onPeriodPicked: function (p) { pg.setKs({ period: p, row: 0 }) }
      onJumpAsked: function (live) { pg.agentJump(live) }
    }
    RemindersTab {
      visible: pg.sub === "reminders"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.maximumHeight: 100000
      parsed: pg.parsed; ks: pg.ks; inList: pg.inList; hidden: pg.hiddenRem; now: pg.docNow; status: pg.remStatus
      onPick: function (row, c) { pg.setKs({ row: row, col: c }) }
    }

    HintBar {
      objectName: "timeHints"
      Layout.fillWidth: true
      Layout.preferredHeight: 22
      hints: M.hints(pg.sub, CcState.pane)
    }
  }
}
