pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Week: four headline numbers against last week, a bar per day stacked by focus zone with the
// target line, and the selected day and the zone legend on the right. p and P step the week.
ColumnLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property var legacyProjects: []
  property var legacyItems: []
  signal pick(int row, int col)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "days")
  readonly property var week: ok ? M.weekModel(doc, ks.weekOff) : null
  readonly property var periodWeek: (ok && ks.weekOff === 0 && doc.periods && doc.periods.week) ? doc.periods.week : null
  readonly property var selDay: week ? week.rows[Math.max(0, Math.min(6, ks.col))] : null
  readonly property int selSlot: (week && ks.row > 0 && ks.row <= week.legend.length) ? week.legend[ks.row - 1].slot : -1

  function card(key, kind, good) {
    var k = periodWeek ? periodWeek[key] : null
    if (!k || typeof k !== "object" || !M.num(k.value)) return { has: false }
    var d = M.num(k.delta) ? k.delta : (M.num(k.prev) ? k.value - k.prev : NaN)     // prev and delta may both be left out
    return { has: true, value: M.fmt(kind, k.value), prev: M.num(k.prev) ? M.fmt(kind, k.prev) : "", delta: M.num(d) ? M.fmtDelta(kind, d) : "", dir: M.dirOf(d), tone: M.toneOf(d, good) }
  }
  function tone(slot) { var s = M.series(slot); return Qt.alpha(Theme.color[s.tok], s.a) }

  objectName: "timeWeek"

  function nudge(f, dy) { if (f) f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY + dy)) }
  function scrollBy(dy) { nudge(sideFlick, dy) }
  spacing: 16

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    title: "Week"
    text: M.emptyText(t.parsed, "days")
  }

  // headline numbers
  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    spacing: 16
    KpiCard {
      Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
      label: t.week ? t.week.label : "Week"; icon: "calendar-blank"
      has: t.week && M.num(t.week.totalMin)
      value: t.week ? M.hm(t.week.totalMin) + " of " + M.hm(t.week.targetMin) : ""
      delta: t.week && M.num(t.week.deltaMin) ? M.signedHm(t.week.deltaMin) + (M.num(t.week.deltaPct) ? " (" + M.signedNum(t.week.deltaPct, "%") + ")" : "") : ""
      dir: t.week ? M.dirOf(t.week.deltaMin) : "flat"; tone: t.week ? M.toneOf(t.week.deltaMin, 1) : "neutral"
      prev: t.week && M.num(t.week.prevMin) ? M.hm(t.week.prevMin) : ""; prevLabel: "last week"
    }
    KpiCard {
      readonly property var c: t.card("focusMin", "min", 1)
      Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
      label: "Focus"; icon: "crosshair"; has: c.has; value: c.value || ""; delta: c.delta || ""; dir: c.dir || "flat"; tone: c.tone || "neutral"; prev: c.prev || ""; prevLabel: "last week"
    }
    KpiCard {
      readonly property var c: t.card("deepWorkMin", "min", 1)
      Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
      label: "Deep work"; icon: "hourglass-medium"; has: c.has; value: c.value || ""; delta: c.delta || ""; dir: c.dir || "flat"; tone: c.tone || "neutral"; prev: c.prev || ""; prevLabel: "last week"
    }
    KpiCard {
      Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
      label: "Left to target"; icon: "gauge"
      has: t.week && t.week.targetMin > 0
      value: t.week ? M.hm(t.week.leftMin) : ""
      delta: t.week && t.week.targetMin > 0 ? Math.round(100 * Math.min(1, (t.week.totalMin || 0) / t.week.targetMin)) + "% done" : ""
      dir: "flat"; tone: "neutral"
    }
  }

  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    spacing: 16

    Card {
      objectName: "weekCard"
      Layout.fillWidth: true
      Layout.preferredWidth: 2
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.minimumWidth: 0
      implicitHeight: 0
      clip: true
      Head { id: wkHead; text: "Worked, by focus zone"; icon: "calendar-dots" }
      DText { anchors.right: parent.right; anchors.verticalCenter: wkHead.verticalCenter; text: t.week && !t.week.isCurrent ? "P older week, p newer week" : "P older week"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
      WeekChart {
        anchors.top: wkHead.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        week: t.week
        selCol: t.ks.col
        selSlot: t.selSlot
        focused: t.inList
        onPicked: function (col) { t.pick(t.ks.row, col) }
      }
    }

    // the long column: two whole cards in their own clipped scroll, never cut mid-card
    Flickable {
      id: sideFlick
      objectName: "weekSideScroll"
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.minimumWidth: 0
      clip: true
      contentWidth: width
      contentHeight: sideCol.height
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: sideCol
        objectName: "weekSide"
        width: sideFlick.width
        spacing: 16
        Card {
          objectName: "weekZones"
          width: parent.width
          pad: 16
          Column {
            width: parent.width
            spacing: 6
            Cap { text: "ZONES THIS WEEK" }
            Repeater {
              model: t.week ? [{ zone: "All zones", min: t.week.legend.reduce(function (a, z) { return a + z.min }, 0), slot: -1, idx: 0 }].concat(t.week.legend.map(function (z, i) { return { zone: z.zone, min: z.min, slot: z.slot, idx: i + 1 } })) : []
              Item {
                id: lg
                required property var modelData
                readonly property bool sel: t.ks.row === modelData.idx
                width: parent.width
                height: 26
                Rectangle { anchors.fill: parent; radius: Theme.radius.chip; color: lg.sel ? Theme.color.surfaceContainer : "transparent" }
                FocusRing { focused: lg.sel && t.inList }
                Row {
                  x: 8
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 8
                  Rectangle {
                    visible: lg.modelData.slot >= 0
                    width: 10; height: 10; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: t.tone(lg.modelData.slot)
                  }
                  DText { text: lg.modelData.zone; role: "bodyS"; width: lg.width - 90; elide: Text.ElideRight }
                }
                DText { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: M.hm(lg.modelData.min); role: "bodyS"; mono: true; dim: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(lg.modelData.idx, t.ks.col) }
              }
            }
            DText { visible: t.week && t.week.legend.length === 0; text: "No zone minutes this week."; role: "bodyS"; dim: true }
          }
        }
        Card {
          objectName: "weekDay"
          width: parent.width
          pad: 16
          Column {
            width: parent.width
            spacing: 6
            Cap { text: t.selDay ? M.dayLabel(t.selDay.day).toUpperCase() : "DAY" }
            Repeater {
              model: t.selDay ? [
                ["Login", t.selDay.loginTs ? M.clockTs(t.selDay.loginTs) : "-"], ["Logout", t.selDay.logoutTs ? M.clockTs(t.selDay.logoutTs) : "-"],
                ["Worked", M.num(t.selDay.workedMin) ? M.hm(t.selDay.workedMin) : "-"], ["Target", M.num(t.selDay.targetMin) ? M.hm(t.selDay.targetMin) : "-"],
                ["Focus", M.num(t.selDay.focusMin) ? M.hm(t.selDay.focusMin) : "-"], ["Away", M.num(t.selDay.deductionMin) ? M.hm(t.selDay.deductionMin) : "-"],
                ["Tasks done", M.num(t.selDay.tasksDone) ? String(t.selDay.tasksDone) : "-"]] : []
              Item {
                required property var modelData
                width: parent.width
                height: 20
                DText { text: parent.modelData[0]; role: "bodyS"; dim: true }
                DText { anchors.right: parent.right; text: parent.modelData[1]; role: "bodyS"; mono: true }
              }
            }
          }
        }
      }
    }
  }

  // the activity files still carry week totals when metrics.json is missing
  Card {
    objectName: "weekCard"
    visible: !t.ok
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    implicitHeight: 0
    clip: true
    Item {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: (parent.width - 32) / 2
      Cap { id: wpCap; text: "BY PROJECT" }
      Flickable {
        objectName: "weekScroll"
        anchors.top: wpCap.bottom; anchors.topMargin: 8; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        clip: true; contentWidth: width; contentHeight: wpCol.height; boundsBehavior: Flickable.StopAtBounds
        Column {
          id: wpCol
          width: parent.width
          spacing: 8
          Repeater { model: t.legacyProjects; TimeRow { required property var modelData; width: wpCol.width; n: modelData.n; v: modelData.v } }
          DText { visible: t.legacyProjects.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
        }
      }
    }
    Item {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: (parent.width - 32) / 2
      Cap { id: wiCap; text: "BY ITEM" }
      Flickable {
        objectName: "weekScroll"
        anchors.top: wiCap.bottom; anchors.topMargin: 8; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        clip: true; contentWidth: width; contentHeight: wiCol.height; boundsBehavior: Flickable.StopAtBounds
        Column {
          id: wiCol
          width: parent.width
          spacing: 8
          Repeater { model: t.legacyItems; TimeRow { required property var modelData; width: wiCol.width; n: modelData.n; v: modelData.v } }
          DText { visible: t.legacyItems.length === 0; text: "Nothing recorded yet."; role: "bodyS"; dim: true }
        }
      }
    }
  }
}
