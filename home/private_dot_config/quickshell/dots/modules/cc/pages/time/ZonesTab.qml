pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Focus zones: where focused time went, ranked for the week or the month (p P switch), the
// twelve-week trend stacked by zone, and the projects with how much of each the agents ran.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  signal pick(int row, int col)
  signal windowPicked(int period)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "zones")
  readonly property string win: ks.period === 2 ? "month" : "week"
  readonly property var ranks: ok ? M.zoneRanks(doc, win) : ({ rows: [], totalMin: 0 })
  readonly property var weeks: ok ? M.zoneWeeks(doc, ranks) : ({ weeks: [], maxMin: 60 })
  readonly property var projects: ok ? M.projectRows(doc) : []
  readonly property var zdays: ok ? M.zoneDays(doc, ranks, 14) : ({ days: [], maxMin: 60 })
  readonly property var cur: ok && doc.zones.current ? doc.zones.current : null
  readonly property int selSlot: !inList ? -1 : (ks.row >= 0 && ks.row < ranks.rows.length) ? ranks.rows[ks.row].slot : -1
  function tone(slot) { var s = M.series(slot); return Qt.alpha(Theme.color[s.tok], s.a) }

  onKsChanged: if (ok && ks.row >= 0 && ks.row < ranks.rows.length) rankFlick.ensure(ks.row * 34, 34)

  objectName: "timeZones"
  spacing: 16

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    title: "Focus zones"
    icon: "crosshair"
    text: M.emptyText(t.parsed, "zones")
  }

  ColumnLayout {
    visible: t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    spacing: 16
    Card {
      id: rankCard
      objectName: "zoneRank"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.minimumWidth: 0
      implicitHeight: 0
      clip: true
      FocusRing { parent: rankCard; kind: "pane"; focused: t.inList; radius: Theme.radius.card }
      Column {
        id: rankHead
        width: parent.width
        spacing: 10
        Head { text: "Focus zones"; icon: "crosshair" }
        Row {
          spacing: 2
          Seg { objectName: "zoneWin"; text: "Last 7 days"; h: 24; pad: 10; on: t.win === "week"; onColor: Theme.color.outlineVariant; onClicked: t.windowPicked(1) }
          Seg { objectName: "zoneWin"; text: "Last 30 days"; h: 24; pad: 10; on: t.win === "month"; onColor: Theme.color.outlineVariant; onClicked: t.windowPicked(2) }
        }
        Row {
          spacing: 8
          Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: t.cur && t.cur.state === "running" ? Theme.color.accent : Theme.color.fgDim }
          DText {
            text: t.cur ? "Now: " + (t.cur.zone || "no zone") + ", " + (t.cur.state || "idle") : "No focus session is running."
            role: "bodyS"
            dim: true
          }
        }
        DText { text: M.hm(t.ranks.totalMin) + " focused in " + (t.win === "week" ? "7 days" : "30 days"); role: "bodyS"; dim: true }
      }
      Flickable {
        id: rankFlick
        objectName: "zoneScroll"
        anchors.top: rankHead.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: rankCol.height
        boundsBehavior: Flickable.StopAtBounds
        function ensure(y, h) {
          if (y < contentY) contentY = y
          else if (y + h > contentY + height) contentY = Math.min(Math.max(0, contentHeight - height), y + h - height)
        }
        Column {
          id: rankCol
          width: rankFlick.width
          Repeater {
            model: t.ranks.rows
            Item {
              id: zr
              required property var modelData
              required property int index
              readonly property bool sel: t.ks.row === index
              width: rankCol.width
              height: 34
              Rectangle { anchors.fill: parent; anchors.bottomMargin: 2; radius: Theme.radius.chip; color: zr.sel ? Theme.color.surfaceContainer : "transparent" }
              FocusRing { anchors.bottomMargin: 2; focused: zr.sel && t.inList }
              Rectangle { x: 8; width: 10; height: 10; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: t.tone(zr.modelData.slot) }
              DText { x: 28; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.3; text: zr.modelData.zone; role: "bodyS"; elide: Text.ElideRight }
              Meter { x: parent.width * 0.3 + 36; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.7 - 36 - 130; value: zr.modelData.share; fill: t.tone(zr.modelData.slot) }
              DText { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: M.hm(zr.modelData.min) + "  " + Math.round(zr.modelData.share) + "%"; role: "bodyS"; mono: true; dim: true }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(zr.index, 0) }
            }
          }
          DText { visible: t.ranks.rows.length === 0; text: "No focus time in this window."; role: "bodyS"; dim: true }
        }
      }
    }

    Card {
      objectName: "zoneDays"
      Layout.fillWidth: true
      Layout.preferredHeight: 200
      Layout.minimumHeight: 0
      clip: true
      Cap { id: dCap; text: "FOCUS BY DAY, LAST 14 DAYS" }
      Item {
        id: dbox
        anchors.top: dCap.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        readonly property real colW: width / 14
        Repeater {
          model: t.zdays.days
          Item {
            id: dc
            required property var modelData
            required property int index
            x: index * dbox.colW
            width: dbox.colW
            height: dbox.height
            Column {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 18
              x: 3
              width: parent.width - 6
              Repeater {
                model: dc.modelData.segs
                Rectangle {
                  required property var modelData
                  width: dc ? Math.max(0, dc.width - 6) : 0
                  height: Math.max(1, (dbox.height - 18) * modelData.min / t.zdays.maxMin)
                  color: t.tone(modelData.slot)
                  opacity: (t.selSlot < 0 || t.selSlot === modelData.slot) ? 1 : 0.2
                  border.width: 1
                  border.color: Theme.color.surface
                }
              }
            }
            DText { anchors.bottom: parent.bottom; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dc.modelData.label; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
          }
        }
      }
    }
  }

  ColumnLayout {
    visible: t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    spacing: 16

    Card {
      objectName: "zoneWeeks"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      implicitHeight: 0
      clip: true
      Cap { id: wkCap; text: "TWELVE WEEKS, BY ZONE" }
      DText { anchors.right: parent.right; anchors.verticalCenter: wkCap.verticalCenter; visible: t.selSlot >= 0; text: t.ranks.rows.length > t.ks.row ? t.ranks.rows[t.ks.row].zone : ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.accent }
      Item {
        id: wbox
        anchors.top: wkCap.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        readonly property real colW: width / Math.max(1, t.weeks.weeks.length)
        readonly property real plotH: height - 18
        Repeater {
          model: t.weeks.weeks
          Item {
            id: wc
            required property var modelData
            required property int index
            x: index * wbox.colW
            width: wbox.colW
            height: wbox.height
            Column {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 18
              x: 3
              width: parent.width - 6
              Repeater {
                model: wc.modelData.segs
                Rectangle {
                  required property var modelData
                  width: wc ? Math.max(0, wc.width - 6) : 0
                  height: Math.max(1, wbox.plotH * modelData.min / t.weeks.maxMin)
                  color: t.tone(modelData.slot)
                  opacity: (t.selSlot < 0 || t.selSlot === modelData.slot) ? 1 : 0.2
                  border.width: 1
                  border.color: Theme.color.surface
                }
              }
            }
            DText { anchors.bottom: parent.bottom; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: wc.index % 2 === 0 ? wc.modelData.label : ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; elide: Text.ElideRight }
          }
        }
        DText { visible: t.weeks.weeks.length === 0; text: "No weekly history yet."; role: "bodyS"; dim: true }
      }
    }

    Card {
      objectName: "zoneProjects"
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(260, 56 + t.projects.length * 28)
      Layout.minimumHeight: 0
      clip: true
      Column {
        width: parent.width
        spacing: 2
        Cap { text: "PROJECTS, LAST 30 DAYS, AND HOW MUCH THE AGENTS RAN" }
        Item { width: 1; height: 6 }
        Repeater {
          model: t.projects
          Item {
            id: pr
            required property var modelData
            width: parent.width
            height: 26
            DText { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.32; text: pr.modelData.project; role: "bodyS"; elide: Text.ElideRight }
            Meter { x: parent.width * 0.32 + 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.68 - 8 - 112; value: M.num(pr.modelData.agentPct) ? pr.modelData.agentPct : 0 }
            DText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: M.hm(pr.modelData.min) + "  " + (M.num(pr.modelData.agentPct) ? Math.round(pr.modelData.agentPct) + "%" : "-"); role: "bodyS"; mono: true; dim: true }
          }
        }
        DText { visible: t.projects.length === 0; text: "No terminal time by project yet."; role: "bodyS"; dim: true }
      }
    }
  }
}
