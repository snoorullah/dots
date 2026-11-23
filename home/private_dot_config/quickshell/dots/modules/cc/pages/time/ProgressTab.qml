pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Progress: every KPI as a card with the value, the previous period, the change with its
// arrow and a 30-day sparkline. h j k l move between cards, p P change the period.
ColumnLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  signal pick(int row, int col)
  signal periodPicked(int period)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "periods")
  readonly property string period: M.PERIODS[Math.max(0, Math.min(3, ks.period))]
  readonly property var cards: ok ? M.kpiCards(doc, period) : []
  readonly property real cardH: 108
  readonly property real gap: 12

  onKsChanged: {
    if (!ok) return
    var y = ks.row * (cardH + gap)
    if (y < flick.contentY) flick.contentY = y
    else if (y + cardH > flick.contentY + flick.height) flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), y + cardH - flick.height)
  }

  objectName: "timeProgress"
  spacing: 12

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    title: "Progress"
    icon: "gauge"
    text: M.emptyText(t.parsed, "periods")
  }

  RowLayout {
    visible: t.ok
    Layout.fillWidth: true
    spacing: 12
    Row {
      spacing: 2
      Repeater {
        model: M.PERIODS
        Seg {
          required property string modelData
          required property int index
          objectName: "periodSeg"
          text: M.PERIOD_NAME[modelData]
          h: 26
          pad: 12
          on: t.ks.period === index
          onColor: Theme.color.outlineVariant
          onClicked: t.periodPicked(index)
        }
      }
    }
    DText { text: "against " + M.PERIOD_PREV[t.period]; role: "bodyS"; dim: true }
    Item { Layout.fillWidth: true }
    DText { text: "sparklines: last 30 days, working days"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
  }

  Flickable {
    id: flick
    objectName: "progressScroll"
    visible: t.ok
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    clip: true
    contentWidth: width
    contentHeight: Math.ceil(t.cards.length / 4) * (t.cardH + t.gap)
    boundsBehavior: Flickable.StopAtBounds
    Repeater {
      model: t.cards
      KpiCard {
        id: kc
        required property var modelData
        required property int index
        readonly property int r: Math.floor(index / 4)
        readonly property int c: index % 4
        x: c * (flick.width + t.gap) / 4
        y: r * (t.cardH + t.gap)
        width: (flick.width - 3 * t.gap) / 4
        height: t.cardH
        implicitHeight: t.cardH
        picked: t.ks.row === r && t.ks.col === c
        focused: picked && t.inList
        label: modelData.label
        icon: modelData.icon
        has: modelData.has
        value: modelData.value
        prev: modelData.prev
        prevLabel: M.PERIOD_PREV[t.period]
        delta: modelData.delta
        note: modelData.note
        dir: modelData.dir
        tone: modelData.tone
        spark: modelData.spark
        sparkFromZero: modelData.kind !== "clock"
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.pick(kc.r, kc.c) }
      }
    }
  }
}
