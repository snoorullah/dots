pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Screen and health. Both halves are private: they live in metrics.json (mode 0600) and are drawn
// only here, never on the bar, the lock screen or in a notification. Each half says by itself
// which source is missing.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false

  readonly property var doc: parsed ? parsed.doc : null
  readonly property var scr: M.screenModel(doc)
  readonly property var hl: M.healthModel(doc, M.todayOf(doc))
  function outcomeColor(o) {
    if (o === "answered") return Theme.color.accent
    if (o === "timeout") return Theme.color.waiting
    if (o === "skipped") return Qt.alpha(Theme.color.fgDim, 0.55)
    return "transparent"
  }

  objectName: "timeScreen"

  function nudge(f, dy) { if (f) f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY + dy)) }
  function scrollBy(dy) { nudge(scrFlick, dy); nudge(hlFlick, dy) }
  spacing: 16

  // ---- screen
  NoData {
    visible: t.scr === null
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    title: "Screen time"
    icon: "app-window"
    text: M.emptyText(t.parsed, "screen")
  }
  Card {
    objectName: "screenCard"
    visible: t.scr !== null
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    implicitHeight: 0
    clip: true
    Flickable {
      id: scrFlick
      objectName: "screenScroll"
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: scrCol.height
      boundsBehavior: Flickable.StopAtBounds
    Column {
      id: scrCol
      width: scrFlick.width
      spacing: 10
      Row {
        spacing: 8
        Head { text: "Screen time"; icon: "app-window" }
        Icon { name: "lock-simple"; size: 14; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
        DText { text: "private"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; anchors.verticalCenter: parent.verticalCenter }
      }
      DText { objectName: "screenToday"; text: t.scr && t.scr.today !== "" ? t.scr.today : "no data"; role: "display"; mono: true }
      DText { text: "active today" + (t.scr && t.scr.idle !== "" ? ", " + t.scr.idle + " idle" : ""); role: "bodyS"; dim: true }
      Meter { visible: t.scr && M.num(t.scr.activePct); width: parent.width; value: t.scr && M.num(t.scr.activePct) ? t.scr.activePct : 0 }
      Item { width: 1; height: 4 }
      Repeater {
        model: t.scr ? [["This week" + (t.scr.weekCover !== "" ? ", " + t.scr.weekCover : ""), t.scr.week, false], ["Late night, 22:00 to 05:00", t.scr.late, t.scr.lateHigh], ["Longest stretch", t.scr.longest, false]] : []
        Item {
          required property var modelData
          width: parent.width
          height: 24
          DText { text: parent.modelData[0]; role: "bodyS"; dim: true }
          DText { anchors.right: parent.right; text: parent.modelData[1] !== "" ? parent.modelData[1] : "no data"; role: "bodyS"; mono: true; color: parent.modelData[2] ? Theme.color.waiting : Theme.color.fg; opacity: parent.modelData[1] !== "" ? 1 : 0.5 }
        }
      }
      Item { width: 1; height: 4 }
      Cap { text: "SESSIONS TODAY" }
      Repeater {
        model: t.scr ? t.scr.sessions : []
        Item {
          id: ss
          required property var modelData
          width: parent.width
          height: 24
          DText { text: ss.modelData.start + " to " + ss.modelData.end; role: "bodyS"; mono: true }
          DText { anchors.right: parent.right; text: ss.modelData.active + " active"; role: "bodyS"; mono: true; dim: true }
        }
      }
      DText { visible: t.scr && t.scr.sessions.length === 0; text: "No session split yet."; role: "bodyS"; dim: true }
    }
    }
  }

  // ---- health
  NoData {
    visible: t.hl === null
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    title: "Health"
    icon: "smiley"
    text: M.emptyText(t.parsed, "health")
  }
  Card {
    objectName: "healthCard"
    visible: t.hl !== null
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    implicitHeight: 0
    clip: true
    Flickable {
      id: hlFlick
      objectName: "healthScroll"
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: hlCol.height
      boundsBehavior: Flickable.StopAtBounds
    Column {
      id: hlCol
      width: hlFlick.width
      spacing: 8
      Row {
        spacing: 8
        Head { text: "Health checkpoints"; icon: "smiley" }
        Icon { name: "lock-simple"; size: 14; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
        DText { text: "private"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; anchors.verticalCenter: parent.verticalCenter }
      }
      Row {
        spacing: 24
        Column { Cap { text: "SCORE, 7 DAYS" } DText { text: t.hl && t.hl.avg7 !== "" ? t.hl.avg7 : "no data"; role: "headline"; mono: true } }
        Column { Cap { text: "DOSE TO FIRST CHECK" } DText { text: t.hl && t.hl.doseToFirst !== "" ? t.hl.doseToFirst : "no data"; role: "headline"; mono: true } }
      }
      Item { width: 1; height: 2 }
      // 14 days by five slots
      Row {
        spacing: 0
        Item { width: 64; height: 18 }
        Repeater {
          model: t.hl ? t.hl.slots : []
          DText { required property string modelData; width: 46; horizontalAlignment: Text.AlignHCenter; text: modelData; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
        }
      }
      Repeater {
        model: t.hl ? t.hl.rows : []
        Row {
          id: hr
          required property var modelData
          spacing: 0
          DText { width: 64; height: 20; text: hr.modelData.label; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
          Repeater {
            model: hr.modelData.cells
            Item {
              required property var modelData
              width: 46
              height: 20
              Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                radius: 6
                color: t.outcomeColor(parent.modelData.outcome)
                border.width: parent.modelData.outcome === "pending" || !parent.modelData.has ? 1 : 0
                border.color: Theme.color.outlineVariant
              }
            }
          }
        }
      }
      Row {
        spacing: 14
        Repeater {
          model: [["answered", "answered"], ["skipped", "skipped"], ["timeout", "no reply"], ["pending", "waiting"]]
          Row {
            required property var modelData
            spacing: 6
            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: t.outcomeColor(parent.modelData[0]); border.width: parent.modelData[0] === "pending" ? 1 : 0; border.color: Theme.color.outlineVariant }
            DText { text: parent.modelData[1]; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }
    }
    }
  }
}
