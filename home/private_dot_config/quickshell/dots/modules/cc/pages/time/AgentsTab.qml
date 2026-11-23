pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/AgentMetrics.js" as AM

// Agents: what the agents did, from agent-metrics.json. Runs, prompts, active time, time waiting
// on you, tokens and a list price cost estimate, each against the previous period; tokens by
// kind; tables by agent, ticket and model; 30 days of tokens and cost; subagent share; live
// counts. j k walk the table rows, p P switch period, Enter jumps to a live agent's pane.
// Tokens are always shown. Cost always says "est.".
ColumnLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property var titles: ({})
  property var liveRows: []          // CcState.agents: the rows with a pane to jump to
  signal pick(int row, int col)
  signal periodPicked(int period)
  signal jumpAsked(var live)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property int pi: Math.max(0, Math.min(AM.PERIODS.length - 1, ks.period))
  readonly property string period: AM.PERIODS[pi]
  readonly property bool ok: AM.has(doc, period)
  readonly property var m: ok ? AM.model(doc, period, titles) : null
  readonly property var nav: m ? m.nav : null
  readonly property var all: nav ? nav.all : []
  // input and output in the accent token, the two cache kinds in the dim text token: amber stays for "waiting"
  function kindTone(i) { return i === 0 ? Theme.color.accent : (i === 1 ? Qt.alpha(Theme.color.accent, 0.55) : (i === 2 ? Qt.alpha(Theme.color.fg, 0.7) : Qt.alpha(Theme.color.fg, 0.35))) }
  readonly property real rowH: 36
  readonly property real headH: 32

  // the live pane behind an agent row, or null
  function liveFor(row) {
    if (!row || row.kind !== "agent") return null
    for (var i = 0; i < liveRows.length; i++) {
      var a = liveRows[i]
      if (a && a.name === row.key && a.item && a.item.raw && a.item.jump) return a
    }
    return null
  }
  // the row Enter acts on: -> { row, live }
  function current() {
    var r = all[Math.min(ks.row, all.length - 1)] || null
    return { row: r, live: liveFor(r) }
  }
  function scrollBy(dy) { sideScroll.scrollBy(dy) }     // J K scroll the side cards
  function reveal(item) {
    var y = item.mapToItem(tableScroll.contentItem, 0, 0).y
    if (y < tableScroll.contentY) tableScroll.contentY = Math.max(0, y - headH)
    else if (y + item.height > tableScroll.contentY + tableScroll.height) tableScroll.contentY = y + item.height - tableScroll.height
  }

  objectName: "timeAgents"
  spacing: 12

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    title: "Agents"
    icon: "robot"
    text: t.doc ? "agent-metrics.json has no numbers for " + AM.PERIOD_NAME[t.period].toLowerCase() + " yet." : AM.emptyText(t.parsed)
  }

  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    spacing: 12
    Row {
      spacing: 2
      Repeater {
        model: AM.PERIODS
        Seg {
          required property string modelData
          required property int index
          objectName: "agentPeriodSeg"
          text: AM.PERIOD_NAME[modelData]
          h: 26
          pad: 12
          on: t.pi === index
          onColor: Theme.color.outlineVariant
          onClicked: t.periodPicked(index)
        }
      }
    }
    DText { text: t.m ? "against " + t.m.prevName + (t.m.range !== "" ? ", " + t.m.range : "") : ""; role: "bodyS"; dim: true }
    Item { Layout.fillWidth: true }
    DText { text: "cost is a list price estimate, not a bill"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
  }

  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    spacing: 12
    Repeater {
      model: t.m ? t.m.cards : []
      KpiCard {
        required property var modelData
        objectName: "agentKpi"
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        Layout.preferredHeight: 108
        implicitHeight: 108
        label: modelData.label
        icon: modelData.icon
        has: modelData.has
        value: modelData.value
        prev: modelData.prev
        prevLabel: t.m ? t.m.prevName : "before"
        delta: modelData.delta
        dir: modelData.dir
        tone: modelData.tone
        note: modelData.note
        spark: modelData.spark
        sparkFrac: 0.3
      }
    }
  }

  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    spacing: 16

    // ---- tables: their own scroll, j k walk the rows ------------------------------------------
    Card {
      id: tblCard
      objectName: "agentTables"
      Layout.fillWidth: true
      Layout.preferredWidth: 3
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.minimumWidth: 0
      implicitHeight: 0
      pad: 12
      clip: true
      FocusRing { parent: tblCard; kind: "pane"; focused: t.inList; radius: Theme.radius.card }
      Flickable {
        id: tableScroll
        objectName: "agentTableScroll"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: tcol.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: tcol
          width: tableScroll.width
          spacing: 0
          Repeater {
            model: t.all
            Column {
              id: tr
              required property var modelData
              required property int index
              readonly property bool sel: Math.min(t.ks.row, t.all.length - 1) === index
              readonly property bool first: index === 0 || modelData.kind !== t.all[index - 1].kind
              readonly property var live: t.liveFor(modelData)
              width: tcol.width
              onSelChanged: if (sel) t.reveal(rowBox)
              Item {
                visible: tr.first
                width: parent.width
                height: visible ? t.headH : 0
                Cap { x: 10; anchors.verticalCenter: parent.verticalCenter; text: tr.modelData.kind === "agent" ? "BY AGENT" : (tr.modelData.kind === "ticket" ? "BY TICKET" : "BY MODEL") }
                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  Cap { width: 56; horizontalAlignment: Text.AlignRight; text: tr.modelData.kind === "model" ? "" : "RUNS" }
                  Cap { width: 80; horizontalAlignment: Text.AlignRight; text: tr.modelData.kind === "model" ? "" : "ACTIVE" }
                  Cap { width: 84; horizontalAlignment: Text.AlignRight; text: "TOKENS" }
                  Cap { width: 120; horizontalAlignment: Text.AlignRight; text: "COST EST." }
                }
              }
              Item {
                id: rowBox
                objectName: "agentTblRow"
                width: parent.width
                height: t.rowH
                Rectangle { anchors.fill: parent; anchors.bottomMargin: 1; radius: Theme.radius.chip; color: tr.sel ? Theme.color.surfaceContainer : "transparent" }
                FocusRing { anchors.bottomMargin: 1; focused: tr.sel && t.inList }
                Rectangle {
                  x: 10
                  y: parent.height - 4
                  height: 2
                  radius: 1
                  width: Math.max(2, (parent.width - 20) * Math.min(1, tr.modelData.share))
                  color: Theme.color.accent
                  opacity: 0.35
                  visible: tr.modelData.share > 0
                }
                Rectangle { x: 10; width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; visible: tr.live !== null; color: Theme.color.accent }
                DText { x: 28; anchors.verticalCenter: parent.verticalCenter; width: Math.max(0, parent.width - 28 - 350 - 10 - (tr.sel && tr.live ? 70 : 0)); text: tr.modelData.label; role: "body"; elide: Text.ElideRight; font.weight: tr.modelData.kind === "agent" ? Font.Medium : Font.Normal }
                Btn {
                  objectName: "agentTblJump"
                  visible: tr.sel && tr.live !== null
                  small: true
                  text: "Jump"
                  anchors.verticalCenter: parent.verticalCenter
                  x: parent.width - 350 - 10 - 70
                  onClicked: t.jumpAsked(tr.live)
                }
                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  DText { width: 56; horizontalAlignment: Text.AlignRight; text: tr.modelData.kind === "model" ? "" : tr.modelData.runsText; role: "bodyS"; mono: true; dim: true }
                  DText { width: 80; horizontalAlignment: Text.AlignRight; text: tr.modelData.kind === "model" ? "" : tr.modelData.activeText; role: "bodyS"; mono: true; dim: true }
                  DText { width: 84; horizontalAlignment: Text.AlignRight; text: tr.modelData.tokText; role: "bodyS"; mono: true }
                  DText { width: 120; horizontalAlignment: Text.AlignRight; text: tr.modelData.costText; role: "bodyS"; mono: true; dim: tr.modelData.costUsd === null }
                }
                MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(tr.index, 0) }
              }
            }
          }
          DText { visible: t.all.length === 0; text: "No runs in " + (t.m ? t.m.name.toLowerCase() : "this period") + "."; role: "bodyS"; dim: true }
        }
      }
    }

    // ---- side: kinds, 30 days, subagents and live; scrolls when the window is short ---------------
    Flickable {
      id: sideScroll
      objectName: "agentSideScroll"
      Layout.fillWidth: true
      Layout.preferredWidth: 2
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.minimumWidth: 0
      clip: true
      contentWidth: width
      contentHeight: side.height
      boundsBehavior: Flickable.StopAtBounds
      function scrollBy(dy) { contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + dy)) }
      Column {
        id: side
        width: sideScroll.width
        spacing: 12

        Card {
          objectName: "agentKinds"
          width: parent.width
          pad: 16
          Column {
            width: parent.width
            spacing: 10
            Cap { text: "TOKENS BY KIND" }
            Item {
              id: kbar
              objectName: "kindBar"
              width: parent.width
              height: 22
              clip: true
              readonly property var segs: t.m ? t.m.kinds.segs : []
              Rectangle { anchors.fill: parent; radius: 4; color: Theme.color.outlineVariant; visible: kbar.segs.length === 0 }
              Repeater {
                model: kbar.segs
                Rectangle {
                  required property var modelData
                  required property int index
                  objectName: "kindSeg"
                  x: {
                    var sum = 0
                    for (var i = 0; i < index; i++) sum += Math.max(2, kbar.segs[i].frac * kbar.width)
                    return sum
                  }
                  width: Math.max(2, modelData.frac * kbar.width)
                  height: parent.height
                  radius: 2
                  color: t.kindTone(index)
                }
              }
            }
            Repeater {
              model: t.m ? t.m.kinds.segs : []
              Row {
                id: kl
                required property var modelData
                required property int index
                objectName: "kindLegend"
                width: parent.width
                spacing: 8
                Rectangle { width: 10; height: 10; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: t.kindTone(kl.index) }
                DText { width: parent.width - 18 - 80 - 48; text: kl.modelData.label; role: "bodyS"; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                DText { width: 80; horizontalAlignment: Text.AlignRight; text: kl.modelData.text; role: "bodyS"; mono: true; anchors.verticalCenter: parent.verticalCenter }
                DText { width: 48; horizontalAlignment: Text.AlignRight; text: kl.modelData.pct; role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
              }
            }
            DText { visible: t.m && t.m.kinds.segs.length === 0; text: "No tokens in " + (t.m ? t.m.name.toLowerCase() : "this period") + "."; role: "bodyS"; dim: true }
          }
        }

        Card {
          objectName: "agentDaily"
          width: parent.width
          pad: 16
          Column {
            id: dcol
            width: parent.width
            spacing: 8
            Cap { text: "LAST 30 DAYS" }
            DText { text: "Tokens per day" + (t.m && t.m.daily.peakTok > 0 ? ", busiest " + AM.tokens(t.m.daily.peakTok) : ""); role: "bodyS"; dim: true }
            Spark {
              objectName: "dailyTokens"
              width: dcol.width
              height: 44
              values: t.m ? t.m.daily.tokens : []
              gap: 2
              barW: Math.max(2, (width - gap * Math.max(0, values.length - 1)) / Math.max(1, values.length))
            }
            DText { text: "Cost per day, est." + (t.m && t.m.daily.hasCost ? ", busiest " + AM.cost(t.m.daily.peakCost) : ""); role: "bodyS"; dim: true }
            Spark {
              objectName: "dailyCost"
              visible: t.m && t.m.daily.hasCost
              width: dcol.width
              height: 44
              values: t.m ? t.m.daily.cost : []
              gap: 2
              barW: Math.max(2, (width - gap * Math.max(0, values.length - 1)) / Math.max(1, values.length))
            }
            DText { visible: t.m && !t.m.daily.hasCost; text: "No priced days in this file."; role: "bodyS"; dim: true }
            RowLayout {
              width: parent.width
              DText { text: t.m && t.m.daily.days.length ? t.m.daily.days[0] : ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; mono: true; dim: true }
              Item { Layout.fillWidth: true }
              DText { text: t.m && t.m.daily.days.length ? t.m.daily.days[t.m.daily.days.length - 1] : ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; mono: true; dim: true }
            }
          }
        }

        Card {
          objectName: "agentSubLive"
          width: parent.width
          pad: 16
          Column {
            width: parent.width
            spacing: 10
            Cap { text: "SUBAGENTS" }
            Row {
              width: parent.width
              spacing: 12
              DText { id: subTxt; objectName: "subShare"; text: t.m ? t.m.sub.text : "-"; role: "headline"; mono: true; anchors.verticalCenter: parent.verticalCenter }
              Meter { width: parent.width - subTxt.width - 12; anchors.verticalCenter: parent.verticalCenter; value: t.m ? t.m.sub.frac * 100 : 0; visible: t.m && t.m.sub.has }
            }
            DText { text: "of the tokens ran in subagents"; role: "bodyS"; dim: true; visible: t.m && t.m.sub.has }
            Cap { text: "LIVE NOW" }
            Row {
              objectName: "liveCounts"
              spacing: 28
              visible: t.m && t.m.live.has
              Column { Cap { text: "WORKING" } DText { objectName: "liveWorking"; text: t.m ? String(t.m.live.working) : "-"; role: "headline"; mono: true } }
              Column { Cap { text: "NEEDS YOU" } DText { objectName: "liveNeeds"; text: t.m ? String(t.m.live.needs) : "-"; role: "headline"; mono: true; color: t.m && t.m.live.needs > 0 ? Theme.color.waiting : Theme.color.fg } }
              Column { Cap { text: "IDLE" } DText { objectName: "liveIdle"; text: t.m ? String(t.m.live.idle) : "-"; role: "headline"; mono: true } }
            }
            DText { visible: t.m && !t.m.live.has; text: "No live counts: the agent list was not reachable when this file was written."; role: "bodyS"; dim: true; width: parent.width; wrapMode: Text.Wrap }
            DText { visible: t.m && t.m.unpriced > 0; text: AM.tokens(t.m ? t.m.unpriced : 0) + " tokens have no price. The cost is a floor."; role: "bodyS"; color: Theme.color.waiting; width: parent.width; wrapMode: Text.Wrap }
          }
        }
      }
    }
  }
}
