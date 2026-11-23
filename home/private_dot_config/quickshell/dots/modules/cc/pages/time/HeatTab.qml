pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview.parts as Ov
import "../../js/Metrics.js" as M

// Heatmap: the last 120 days as weeks in columns (h l move a week, j k a day), the month
// totals under it, and on the right the improvement metrics: trends, ratios, streaks,
// punctuality. Without metrics.json it falls back to the activity heatmap alone.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property var legacyDays: []
  property bool loaded: true
  property var legacy: ({ totalSec: 0, daysWorked: 0, avgSec: 0, best: null })
  signal pick(int row, int col)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "days")
  readonly property var grid: ok ? M.heatGrid(doc) : null
  readonly property var months: ok ? M.monthRows(doc, 5) : []
  readonly property var weekly: ok ? M.weekRows(doc, 7) : []
  readonly property var im: M.improve(doc)
  readonly property var cur: grid ? (grid.cells[Math.max(0, Math.min(grid.cols - 1, ks.col)) * 7 + Math.max(0, Math.min(6, ks.row))] || null) : null
  readonly property real cell: grid ? Math.max(8, Math.min(26, Math.floor((heatCard.width - 32 - 40 - 4 * (grid.cols - 1)) / grid.cols))) : 12
  readonly property var levelA: [0, 0.28, 0.5, 0.75, 1]

  objectName: "timeHeat"

  function nudge(f, dy) { if (f) f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY + dy)) }
  function scrollBy(dy) { nudge(leftFlick, dy); nudge(impFlick, dy) }
  spacing: 16

  // ---- left: the grid and the months. Both cards keep their full height; the column scrolls
  Flickable {
    id: leftFlick
    objectName: "monthsScroll"
    Layout.fillWidth: true
    Layout.preferredWidth: 3
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    clip: true
    contentWidth: width
    contentHeight: leftCol.height
    boundsBehavior: Flickable.StopAtBounds
    Column {
    id: leftCol
    width: leftFlick.width
    spacing: 16

    Card {
      id: heatCard
      width: parent.width
      clip: true
      implicitHeight: t.ok ? gridCol.implicitHeight + 32 : Math.max(gridCol.implicitHeight + 32, leftFlick.height)
      Column {
        id: gridCol
        width: parent.width
        spacing: 10
        Cap { text: t.ok ? "LAST " + t.grid.days + " DAYS" : "LAST 119 DAYS" }
        // metrics grid: weeks across, Monday at the top
        Item {
          id: mg
          objectName: "heatGrid"
          visible: t.ok
          width: parent.width
          height: t.ok ? 16 + 7 * (t.cell + 4) : 0
          Repeater {
            model: t.ok ? t.grid.months : []
            DText { required property var modelData; x: 40 + modelData.col * (t.cell + 4); text: modelData.label; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
          }
          Repeater {
            model: ["Mon", "Wed", "Fri"]
            DText { required property string modelData; required property int index; x: 0; y: 16 + index * 2 * (t.cell + 4) + (t.cell - height) / 2; text: modelData; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
          }
          Repeater {
            model: t.ok ? t.grid.cells : []
            Rectangle {
              id: hc
              required property var modelData
              readonly property bool sel: t.cur !== null && t.cur.day === modelData.day
              objectName: "cell"
              visible: !modelData.empty || modelData.day <= t.doc.today
              x: 40 + modelData.col * (t.cell + 4)
              y: 16 + modelData.row * (t.cell + 4)
              width: t.cell
              height: t.cell
              radius: 3
              color: modelData.level > 0 ? Qt.alpha(Theme.color.accent, t.levelA[modelData.level]) : (modelData.has ? Qt.alpha(Theme.color.fgDim, 0.1) : "transparent")
              border.width: modelData.has && modelData.level === 0 && modelData.kind === "working" ? 1 : 0
              border.color: Theme.color.outlineVariant
              FocusRing { focused: hc.sel && t.inList; radius: 5 }
              Rectangle { visible: hc.sel && !t.inList; anchors.fill: parent; radius: 3; color: "transparent"; border.width: 1; border.color: Theme.color.fgDim }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(hc.modelData.row, hc.modelData.col) }
            }
          }
        }
        // legacy grid from heatmap.json
        Loader {
          active: !t.ok && t.loaded
          visible: active
          sourceComponent: Ov.Heatmap {
            objectName: "heatGrid"
            gap: 4
            labels: true
            cellSize: Math.max(8, Math.min(28, Math.floor((gridCol.width - 56 - 16 * 4) / 17)))
            days: t.legacyDays
          }
        }
        DText {
          visible: t.ok
          objectName: "heatReadout"
          width: parent.width
          elide: Text.ElideRight
          role: "bodyS"
          text: {
            if (!t.cur || !t.cur.has) return "No day under the cursor."
            var c = t.cur
            return M.dayLabel(c.day) + (M.kindText(c.kind) ? ", " + M.kindText(c.kind) : "") + (M.num(c.workedMin) && c.workedMin > 0 ? ": " + M.hm(c.workedMin) + " worked" + (c.targetMin > 0 ? " of " + M.hm(c.targetMin) : "") : "")
          }
        }
        Flow {
          visible: !t.ok
          width: parent.width
          spacing: 40
          Column { Cap { text: "TOTAL" } DText { text: M.hmSec(t.legacy.totalSec); role: "headline" } }
          Column { Cap { text: "DAYS WORKED" } DText { text: String(t.legacy.daysWorked); role: "headline" } }
          Column { Cap { text: "DAILY AVERAGE" } DText { text: M.hmSec(t.legacy.avgSec); role: "headline" } }
          Column { Cap { text: "BEST DAY" } DText { text: t.legacy.best ? M.hmSec(t.legacy.best.sec) + ", " + t.legacy.best.d : "-"; role: "headline" } }
        }
      }
    }

    Card {
      id: monthsCard
      objectName: "monthsCard"
      visible: t.ok
      width: parent.width
      clip: true
      implicitHeight: Math.max(monthsCol.height + 40, leftFlick.height - heatCard.height - leftCol.spacing)    // fills a tall window, whole when short
      readonly property var widths: [96, 76, 76, 62, 100, 56, 92, 76, 56]
      Column {
        id: monthsCol
        width: parent.width
        spacing: 2
        Cap { text: "MONTH BY MONTH" }
        Item { width: 1; height: 4 }
        Row {
          height: 22
          Repeater {
            model: ["Month", "Worked", "Target", "Met", "Avg a day", "Days", "Vs last", "Focus", "Tasks"]
            Cap { required property string modelData; required property int index; width: monthsCard.widths[index]; text: modelData }
          }
        }
        Repeater {
          model: t.months
          Row {
            id: mr
            required property var modelData
            height: 28
            DText { width: monthsCard.widths[0]; text: mr.modelData.label + (mr.modelData.partial ? "*" : ""); role: "bodyS"; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[1]; text: M.hm(mr.modelData.workedMin); role: "bodyS"; mono: true; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[2]; text: M.hm(mr.modelData.targetMin); role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[3]; text: M.pct(mr.modelData.attainmentPct); role: "bodyS"; mono: true; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[4]; text: M.hm(mr.modelData.avgMin); role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[5]; text: String(mr.modelData.daysWorked); role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
            Item {
              width: monthsCard.widths[6]; height: parent.height
              Delta { visible: M.num(mr.modelData.deltaMin); anchors.verticalCenter: parent.verticalCenter; dir: M.dirOf(mr.modelData.deltaMin); tone: M.toneOf(mr.modelData.deltaMin, 1); text: M.signedHm(mr.modelData.deltaMin) }
            }
            DText { width: monthsCard.widths[7]; text: M.hm(mr.modelData.focusMin); role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
            DText { width: monthsCard.widths[8]; text: String(mr.modelData.tasksDone); role: "bodyS"; mono: true; dim: true; anchors.verticalCenter: parent.verticalCenter }
          }
        }
        DText { text: "* the month is not complete"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; visible: t.months.some(function (m) { return m.partial }) }
        Item { width: 1; height: 10 }
        Cap { text: "WEEK BY WEEK, WORKED AGAINST TARGET" }
        Item { width: 1; height: 4 }
        Repeater {
          model: t.weekly
          Item {
            id: wr
            required property var modelData
            width: parent.width
            height: 24
            DText { width: 84; anchors.verticalCenter: parent.verticalCenter; text: "From " + wr.modelData.label; role: "bodyS" }
            Meter { x: 96; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 96 - 200; value: wr.modelData.ratio * 100 / 1.25; fill: wr.modelData.ratio >= 1 ? Theme.color.accent : Theme.color.fgDim }
            Rectangle { visible: wr.modelData.targetMin > 0; x: 96 + (parent.width - 96 - 200) * 0.8; width: 1; height: 12; anchors.verticalCenter: parent.verticalCenter; color: Theme.color.fg; opacity: 0.5 }
            DText { anchors.right: parent.right; anchors.rightMargin: 96; anchors.verticalCenter: parent.verticalCenter; text: M.hm(wr.modelData.workedMin); role: "bodyS"; mono: true }
            Item {
              anchors.right: parent.right
              width: 90
              height: parent.height
              Delta { visible: M.num(wr.modelData.deltaMin); anchors.verticalCenter: parent.verticalCenter; dir: M.dirOf(wr.modelData.deltaMin); tone: M.toneOf(wr.modelData.deltaMin, 1); text: M.signedHm(wr.modelData.deltaMin) }
            }
          }
        }
      }
    }
    }
  }

  // ---- right: improvement metrics
  Flickable {
    id: impFlick
    objectName: "improveScroll"
    visible: t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 2
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    clip: true
    contentWidth: width
    contentHeight: impCol.height
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: impCol
      width: impFlick.width
      spacing: 16
    NoData {
      width: parent.width
      visible: t.im === null
      title: "Improvement"
      text: M.emptyText(t.parsed, "improve")
    }

    Card {
      objectName: "trendCard"
      width: parent.width
      visible: t.im !== null
      clip: true
      Column {
        width: parent.width
        spacing: 4
        Cap { text: "TRENDS, SLOPE PER WORKING DAY" }
        Item { width: 1; height: 4 }
        Row {
          height: 20
          Cap { width: parent.parent.width * 0.4; text: "" }
          Cap { width: parent.parent.width * 0.3; text: "7 days" }
          Cap { width: parent.parent.width * 0.3; text: "30 days" }
        }
        Repeater {
          model: t.im ? t.im.trends : []
          Row {
            id: tr
            required property var modelData
            height: 26
            DText { width: tr.parent.width * 0.4; text: tr.modelData.label; role: "bodyS"; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
              model: tr.modelData.cells
              Item {
                required property var modelData
                width: tr.parent.width * 0.3
                height: tr.height
                Delta { visible: parent.modelData.has; anchors.verticalCenter: parent.verticalCenter; dir: parent.modelData.dir; tone: parent.modelData.tone; text: parent.modelData.slope }
                DText { visible: !parent.modelData.has; anchors.verticalCenter: parent.verticalCenter; text: "no data"; role: "bodyS"; dim: true }
              }
            }
          }
        }
        Item { width: 1; height: 8 }
        Cap { text: "RATIOS" }
        Repeater {
          model: t.im ? t.im.ratios : []
          Item {
            id: ra
            required property var modelData
            width: parent.width
            height: 22
            DText { width: parent.width * 0.4 - 8; text: ra.modelData.label; role: "bodyS"; elide: Text.ElideRight }
            DText { x: parent.width * 0.4; width: parent.width * 0.3; text: ra.modelData.w7; role: "bodyS"; mono: true }
            DText { x: parent.width * 0.7; width: parent.width * 0.3; text: ra.modelData.w30; role: "bodyS"; mono: true }
          }
        }
        DText { visible: t.im && t.im.ratios.length === 0; text: "No ratios yet."; role: "bodyS"; dim: true }
      }
    }

    Card {
      objectName: "streakCard"
      width: parent.width
      visible: t.im !== null
      clip: true
      Column {
        width: parent.width
        spacing: 4
        Cap { text: "STREAKS, IN DAYS" }
        Repeater {
          model: t.im ? t.im.streaks : []
          Item {
            id: sk
            required property var modelData
            width: parent.width
            height: 24
            DText { width: parent.width * 0.5; text: sk.modelData.label; role: "bodyS"; elide: Text.ElideRight }
            DText { x: parent.width * 0.5; text: String(sk.modelData.cur); role: "bodyS"; mono: true; font.weight: Font.DemiBold }
            DText { anchors.right: parent.right; text: sk.modelData.best !== undefined ? "best " + sk.modelData.best : ""; role: "bodyS"; mono: true; dim: true }
          }
        }
        DText { visible: t.im && t.im.streaks.length === 0; text: "No streaks yet."; role: "bodyS"; dim: true }
        Item { width: 1; height: 8 }
        Cap { text: "PUNCTUALITY" }
        Item {
          visible: t.im && t.im.punctuality !== null
          width: parent.width
          height: 24
          DText { text: "On time, target " + (t.im && t.im.punctuality ? t.im.punctuality.target : ""); role: "bodyS" }
          DText { anchors.right: parent.right; text: t.im && t.im.punctuality ? t.im.punctuality.onTime : ""; role: "bodyS"; mono: true }
        }
        Meter { visible: t.im && t.im.punctuality !== null && M.num(t.im.punctuality.onTimePct); width: parent.width; value: t.im && t.im.punctuality && M.num(t.im.punctuality.onTimePct) ? t.im.punctuality.onTimePct : 0 }
        Item {
          visible: t.im && t.im.punctuality !== null
          width: parent.width
          height: 24
          DText { text: "Average lateness"; role: "bodyS"; dim: true }
          DText { anchors.right: parent.right; text: t.im && t.im.punctuality ? t.im.punctuality.late : ""; role: "bodyS"; mono: true }
        }
        DText { visible: t.im && t.im.punctuality === null; text: "No login log yet."; role: "bodyS"; dim: true }
        Item { width: 1; height: 8 }
        Cap { text: "BEST AND WORST, LAST 30 DAYS" }
        Item {
          visible: t.im && t.im.bestDay !== null
          width: parent.width
          height: 24
          DText { text: "Best " + (t.im && t.im.bestDay ? t.im.bestDay.label : ""); role: "bodyS" }
          DText { anchors.right: parent.right; text: t.im && t.im.bestDay ? t.im.bestDay.value : ""; role: "bodyS"; mono: true }
        }
        Item {
          visible: t.im && t.im.worstDay !== null
          width: parent.width
          height: 24
          DText { text: "Lowest " + (t.im && t.im.worstDay ? t.im.worstDay.label : ""); role: "bodyS" }
          DText { anchors.right: parent.right; text: t.im && t.im.worstDay ? t.im.worstDay.value : ""; role: "bodyS"; mono: true }
        }
      }
    }
    }
  }

  // the legacy heatmap leaves the right column empty; say why the rest is missing
  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 2
    Layout.alignment: Qt.AlignTop
    title: "Monthly totals and improvement"
    text: M.emptyText(t.parsed, "days")
  }
}
