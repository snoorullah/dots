pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview

// Agents: one row per agent the feed knows about, then the run summaries. Data is whatever
// the overview files carry; fields they lack (tokens, cost, gaps) say so instead of guessing.
Flickable {
  id: pg
  property bool dim: false
  clip: true
  contentWidth: width
  contentHeight: col.height + 48
  boundsBehavior: Flickable.StopAtBounds

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
        model: [["STATE", 190], ["FOR", 70], ["AGENT", 160], ["WORKING ON", 0], ["LAST", 220], ["", 90]]
        Cap { required property var modelData; Layout.preferredWidth: modelData[1] > 0 ? modelData[1] : -1; Layout.fillWidth: modelData[1] === 0; Layout.leftMargin: 8; text: modelData[0] }
      }
    }
    Repeater {
      model: CcState.agents
      Item {
        id: ar
        required property var modelData
        objectName: "agentRow"
        Layout.fillWidth: true
        Layout.preferredHeight: 49
        Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
        RowLayout {
          anchors.fill: parent
          anchors.topMargin: 1
          spacing: 0
          Row {
            Layout.preferredWidth: 190
            Layout.leftMargin: 8
            spacing: 8
            StatusMark { visible: ar.modelData.tone === "wait"; level: "waiting"; size: 14; anchors.verticalCenter: parent.verticalCenter }
            DText { text: ar.modelData.state; role: "bodyS"; font.weight: ar.modelData.tone === "wait" ? Font.DemiBold : Font.Normal; color: ar.modelData.tone === "wait" ? Theme.color.waiting : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          }
          DText { Layout.preferredWidth: 70; Layout.leftMargin: 8; text: ar.modelData.age; role: "bodyS" }
          DText { Layout.preferredWidth: 160; Layout.leftMargin: 8; text: ar.modelData.name; role: "body"; font.weight: Font.Medium; elide: Text.ElideRight }
          DText { Layout.fillWidth: true; Layout.leftMargin: 8; text: ar.modelData.task; role: "bodyS"; elide: Text.ElideRight }
          DText { Layout.preferredWidth: 220; Layout.leftMargin: 8; text: ar.modelData.last; role: "bodyS"; dim: true; elide: Text.ElideRight }
          Item {
            Layout.preferredWidth: 90
            Layout.fillHeight: true
            Btn {
              visible: ar.modelData.action !== ""
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              small: true
              text: ar.modelData.action
              blocked: !ar.modelData.item || (!ar.modelData.item.jump && !ar.modelData.item.url)
              onClicked: Actions.jump(ar.modelData.item.raw)
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
        Layout.fillWidth: true
        Layout.preferredWidth: 7
        Layout.alignment: Qt.AlignTop
        pad: 16
        Column {
          id: g1
          width: parent.width
          spacing: 10
          Cap { text: "WHILE YOU WERE AWAY, 7 DAYS" }
          DText { text: "No gaps recorded yet. The feed carries no away history."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
        }
      }
      Card {
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
            Column { Cap { text: "RUNS" } DText { text: String(Feed.today ? Feed.today.byAgent.length : 0); role: "headline" } }
            Column { Cap { text: "TOKENS" } DText { text: "no data"; role: "bodyS"; dim: true; topPadding: 6 } }
            Column { Cap { text: "COST" } DText { text: "no data"; role: "bodyS"; dim: true; topPadding: 6 } }
          }
        }
      }
    }
  }
}
