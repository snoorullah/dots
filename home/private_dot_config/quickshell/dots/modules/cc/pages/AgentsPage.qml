pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../js/AgentMetrics.js" as AM

// Agents: one row per agent the feed knows about, then the run summaries. Data is whatever
// the overview files carry; fields they lack (tokens, cost, gaps) say so instead of guessing.
Flickable {
  id: pg
  objectName: "agentsPage"
  property bool dim: false
  clip: true
  contentWidth: width
  contentHeight: col.height + 48
  boundsBehavior: Flickable.StopAtBounds

  // keep the keyboard row inside the viewport
  function reveal(row) {
    var y = row.mapToItem(pg.contentItem, 0, 0).y
    if (y < pg.contentY) pg.contentY = Math.max(0, y - 24)
    else if (y + row.height > pg.contentY + pg.height) pg.contentY = y + row.height - pg.height + 24
  }

  readonly property var today: AM.todayCard(CcState.agentMetrics.doc)
  readonly property var away: CcState.awayModel
  readonly property int waiting: { var n = 0; CcState.agents.forEach(function (a) { if (a.tone === "wait") n++ }); return n }

  ColumnLayout {
    id: col
    x: 24
    y: 24
    width: pg.width - 48
    spacing: 16

    Row {
      spacing: 12
      DText { text: "Agents"; role: "headline"; anchors.verticalCenter: parent.verticalCenter }
      DText { text: CcState.agents.length + " listed, " + pg.waiting + " waits on you"; role: "body"; dim: true; anchors.verticalCenter: parent.verticalCenter }
    }

    // header row
    RowLayout {
      Layout.fillWidth: true
      spacing: 0
      Repeater {
        model: [["STATE", 150], ["FOR", 170], ["AGENT", 140], ["WORKING ON", 0], ["LAST", 150], ["", 90]]
        Cap { required property var modelData; Layout.preferredWidth: modelData[1] > 0 ? modelData[1] : -1; Layout.fillWidth: modelData[1] === 0; Layout.leftMargin: 8; text: modelData[0] }
      }
    }
    Repeater {
      model: CcState.agentsShown
      Item {
        id: ar
        required property var modelData
        required property int index
        objectName: "agentRow"
        readonly property bool current: CcState.agentCur === index
        onCurrentChanged: if (current) pg.reveal(ar)
        Layout.fillWidth: true
        Layout.preferredHeight: 49
        Rectangle { anchors.fill: parent; radius: Theme.radius.row; color: Theme.color.surfaceContainer; visible: ar.current }
        Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
        FocusRing { focused: ar.current; anchors.margins: 0; radius: Theme.radius.row }
        RowLayout {
          anchors.fill: parent
          anchors.topMargin: 1
          spacing: 0
          Row {
            Layout.preferredWidth: 150
            Layout.leftMargin: 8
            spacing: 8
            StatusMark { visible: ar.modelData.tone === "wait"; level: "waiting"; size: 14; anchors.verticalCenter: parent.verticalCenter }
            DText { text: ar.modelData.state; role: "bodyS"; font.weight: ar.modelData.tone === "wait" ? Font.DemiBold : Font.Normal; color: ar.modelData.tone === "wait" ? Theme.color.waiting : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          }
          DText { objectName: "agentFor"; Layout.preferredWidth: 170; Layout.leftMargin: 8; text: ar.modelData.forRef; role: "bodyS"; elide: Text.ElideRight }
          DText { Layout.preferredWidth: 140; Layout.leftMargin: 8; text: ar.modelData.name; role: "body"; font.weight: Font.Medium; elide: Text.ElideRight }
          DText { objectName: "agentWork"; Layout.fillWidth: true; Layout.leftMargin: 8; text: ar.modelData.task; role: "bodyS"; elide: Text.ElideRight }
          DText { Layout.preferredWidth: 150; Layout.leftMargin: 8; text: ar.modelData.last; role: "bodyS"; dim: true; elide: Text.ElideRight }
          Item {
            Layout.preferredWidth: 90
            Layout.fillHeight: true
            Btn {
              visible: ar.modelData.action !== ""
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              small: true
              text: ar.modelData.action
              objectName: "agentJump"
              blocked: !ar.modelData.item || (!ar.modelData.item.jump && !ar.modelData.item.url)
              onClicked: CcState.jumpRow(ar.modelData)
            }
          }
        }
      }
    }
    DText { objectName: "agentsEmpty"; visible: CcState.agents.length === 0; text: "No agents in the feed."; role: "title"; font.weight: Font.Normal; dim: true; topPadding: 16 }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 0
      spacing: 16
      Card {
        objectName: "awayCard"
        Layout.fillWidth: true
        Layout.preferredWidth: 7
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          id: g1
          width: parent.width
          spacing: 10
          Cap { text: "WHILE YOU WERE AWAY, 7 DAYS" }
          DText {
            objectName: "awaySummary"
            visible: pg.away.has
            text: pg.away.count + (pg.away.count === 1 ? " gap, " : " gaps, ") + AM.dur(pg.away.totalMin) + " in all, " + pg.away.unanswered + " not answered"
            role: "bodyS"
            dim: true
            width: parent.width
            wrapMode: Text.Wrap
          }
          Repeater {
            model: pg.away.rows.slice(0, 8)
            Row {
              id: aw
              required property var modelData
              objectName: "awayRow"
              width: g1.width
              spacing: 12
              Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: aw.modelData.answered ? Theme.color.fgDim : Theme.color.waiting }
              DText { width: 130; text: aw.modelData.when; role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
              DText { width: 70; text: aw.modelData.minText; role: "bodyS"; mono: true; color: aw.modelData.answered ? Theme.color.fg : Theme.color.waiting; anchors.verticalCenter: parent.verticalCenter }
              DText { width: parent.width - 8 - 130 - 70 - 36 - 96; text: aw.modelData.label; role: "bodyS"; elide: Text.ElideRight; color: aw.modelData.answered ? Theme.color.fg : Theme.color.waiting; anchors.verticalCenter: parent.verticalCenter }
              DText { width: 96; horizontalAlignment: Text.AlignRight; text: aw.modelData.answered ? "answered" : "not answered"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: aw.modelData.answered ? Theme.color.fgDim : Theme.color.waiting; anchors.verticalCenter: parent.verticalCenter }
            }
          }
          DText { visible: pg.away.rows.length > 8; text: "and " + (pg.away.rows.length - 8) + " older"; role: "bodyS"; dim: true }
          DText { objectName: "awayEmpty"; visible: !pg.away.has; text: pg.away.state === "ok" ? "No gaps in the last 7 days." : "No away history yet. dots-overview writes away.json on its next run."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        }
      }
      Card {
        objectName: "metricsCard"
        Layout.fillWidth: true
        Layout.preferredWidth: 5
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          id: g2
          width: parent.width
          spacing: 10
          Cap { text: "AGENT METRICS, TODAY" }
          Row {
            spacing: 32
            Column { Cap { text: "RUNS" } DText { objectName: "metricRuns"; text: pg.today.runs; role: "headline"; mono: true; dim: !pg.today.has } }
            Column { Cap { text: "TOKENS" } DText { objectName: "metricTokens"; text: pg.today.tokens; role: "headline"; mono: true; dim: !pg.today.has } }
            Column { Cap { text: "COST, LIST PRICE" } DText { objectName: "metricCost"; text: pg.today.cost; role: "headline"; mono: true; dim: !pg.today.has } }
          }
          DText { visible: pg.today.has; text: pg.today.active + " active, a list price estimate rather than a bill"; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
          DText { visible: !pg.today.has; text: AM.emptyText(CcState.agentMetrics); role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
          Btn { objectName: "openTimeAgents"; text: "Time, Agents"; icon: "clock"; keyHint: "t"; small: true; onClicked: CcState.openTimeAgents() }
        }
      }
    }
  }
}
