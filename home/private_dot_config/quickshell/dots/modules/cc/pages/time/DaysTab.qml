pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Days: every day the tracker has, newest first, with login and logout, worked against target,
// focus, breaks, tasks and a two-week sparkline. Enter opens the day on the right.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property bool inDetail: false
  signal pick(int row, int col)
  signal open()

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "days")
  readonly property var rows: ok ? M.dayRows(doc) : []
  readonly property var detail: (ok && ks.detail && rows[ks.row]) ? M.dayDetail(doc, rows[ks.row].day) : null
  readonly property real wDay: 112
  readonly property real wSess: 116
  readonly property real wWorked: 62
  readonly property real wBar: 96
  readonly property real wFocus: 62
  readonly property real wBreak: 62
  readonly property real wTasks: 52
  readonly property real wSpark: 14 * 6

  onKsChanged: {
    if (ok && ks.row >= 0 && ks.row < rows.length) list.positionViewAtIndex(ks.row, ListView.Contain)
    if (detailFlick) detailFlick.contentY = Math.max(0, Math.min(ks.scroll, detailFlick.contentHeight - detailFlick.height))
  }

  objectName: "timeDays"
  spacing: 16

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    title: "Days"
    text: M.emptyText(t.parsed, "days")
  }

  Card {
    id: listCard
    objectName: "daysCard"
    visible: t.ok
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    Layout.preferredWidth: 2
    implicitHeight: 0
    pad: 16
    clip: true
    FocusRing { parent: listCard; kind: "pane"; focused: t.inList && !t.inDetail; radius: Theme.radius.card }

    Row {
      id: hdr
      width: parent.width
      height: 22
      spacing: 0
      Cap { width: t.wDay; text: "Day" }
      Cap { width: t.wSess; text: "In / out" }
      Cap { width: t.wWorked; text: "Worked" }
      Cap { width: t.wBar; text: "Of target" }
      Cap { width: t.wFocus; text: "Focus" }
      Cap { width: t.wBreak; text: "Breaks" }
      Cap { width: t.wTasks; text: "Tasks" }
      Cap { text: "14 days" }
    }
    ListView {
      id: list
      objectName: "daysScroll"
      anchors.top: hdr.bottom
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      model: t.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: t.ks.row
      highlightFollowsCurrentItem: false
      delegate: Item {
        id: dr
        required property var modelData
        required property int index
        readonly property bool cur: t.ks.row === index
        readonly property bool off: !modelData.working
        width: ListView.view.width
        height: 34
        objectName: "dayRow"
        Rectangle { anchors.fill: parent; anchors.bottomMargin: 2; radius: Theme.radius.chip; color: dr.cur ? Theme.color.surfaceContainer : (rowHover.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent") }
        FocusRing { anchors.bottomMargin: 2; focused: dr.cur && t.inList && !t.inDetail }
        Row {
          x: 0
          height: parent.height - 2
          opacity: dr.off ? 0.55 : 1
          Item {
            width: t.wDay; height: parent.height
            DText { anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 8; text: dr.modelData.label; role: "bodyS"; elide: Text.ElideRight; font.weight: dr.modelData.isToday ? Font.DemiBold : Font.Normal; color: dr.modelData.isToday ? Theme.color.accent : Theme.color.fg }
          }
          Item {
            width: t.wSess; height: parent.height
            DText { anchors.verticalCenter: parent.verticalCenter; text: dr.modelData.login !== "" ? dr.modelData.login + " " + (dr.modelData.logout !== "" ? dr.modelData.logout : "") : M.kindText(dr.modelData.kind); role: "bodyS"; mono: true; dim: dr.modelData.login === "" }
          }
          Item { width: t.wWorked; height: parent.height; DText { anchors.verticalCenter: parent.verticalCenter; text: dr.modelData.working || dr.modelData.workedMin > 0 ? M.hm(dr.modelData.workedMin) : ""; role: "bodyS"; mono: true } }
          Item {
            width: t.wBar; height: parent.height
            Meter { visible: dr.modelData.targetMin > 0; anchors.verticalCenter: parent.verticalCenter; width: t.wBar - 14; value: dr.modelData.ratio * 100; fill: dr.modelData.ratio >= 1 ? Theme.color.accent : Theme.color.fgDim }
          }
          Item { width: t.wFocus; height: parent.height; DText { anchors.verticalCenter: parent.verticalCenter; text: dr.modelData.working ? M.hm(dr.modelData.focusMin) : ""; role: "bodyS"; mono: true; dim: true } }
          Item { width: t.wBreak; height: parent.height; DText { anchors.verticalCenter: parent.verticalCenter; text: dr.modelData.working ? M.hm(dr.modelData.deductionMin) : ""; role: "bodyS"; mono: true; dim: true } }
          Item { width: t.wTasks; height: parent.height; DText { anchors.verticalCenter: parent.verticalCenter; text: dr.modelData.working && M.num(dr.modelData.tasksDone) ? String(dr.modelData.tasksDone) : ""; role: "bodyS"; mono: true; dim: true } }
          Item {
            width: t.wSpark; height: parent.height
            Spark { anchors.verticalCenter: parent.verticalCenter; height: 20; barW: 4; gap: 2; values: dr.modelData.spark }
          }
        }
        MouseArea {
          id: rowHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { t.pick(dr.index, 0); t.open() }
        }
      }
    }
  }

  // the day, opened with Enter
  Card {
    id: detailCard
    objectName: "dayDetail"
    visible: t.ok && t.detail !== null
    Layout.preferredWidth: 1
    Layout.fillWidth: true
    Layout.minimumWidth: 320
    Layout.maximumWidth: 460
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    implicitHeight: 0
    pad: 16
    clip: true
    FocusRing { parent: detailCard; kind: "pane"; focused: t.inDetail; radius: Theme.radius.card }
    Head { id: dHead; text: t.detail ? t.detail.title : ""; icon: "calendar-check" }
    DText { visible: t.detail && t.detail.kind !== ""; anchors.right: parent.right; anchors.verticalCenter: dHead.verticalCenter; text: t.detail ? t.detail.kind : ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
    Flickable {
      id: detailFlick
      objectName: "dayDetailScroll"
      anchors.top: dHead.bottom
      anchors.topMargin: 12
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      contentWidth: width
      contentHeight: dCol.height
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: dCol
        width: detailFlick.width
        spacing: 12
        Repeater {
          model: t.detail ? t.detail.groups : []
          Column {
            id: grp
            required property var modelData
            width: dCol.width
            spacing: 2
            Cap { text: grp.modelData.cap }
            Repeater {
              model: grp.modelData.rows
              Item {
                required property var modelData
                width: grp.width
                height: 20
                DText { text: parent.modelData.k; role: "bodyS"; dim: true; width: parent.width - 90; elide: Text.ElideRight }
                DText { anchors.right: parent.right; text: parent.modelData.v; role: "bodyS"; mono: true; dim: parent.modelData.dim; opacity: parent.modelData.dim ? 0.6 : 1 }
              }
            }
          }
        }
      }
    }
  }
}
