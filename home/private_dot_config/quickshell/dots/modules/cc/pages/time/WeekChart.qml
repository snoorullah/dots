pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import "../../js/Metrics.js" as M

// Seven bars, Monday first: worked time stacked by focus zone, the rest of the day in a quiet
// fill, a target line across, and the selected day ringed. Heights come from the week model.
Item {
  id: c
  property var week: null          // M.weekModel()
  property int selCol: -1
  property int selSlot: -1         // a zone to emphasise, -1 for all
  property bool focused: false
  signal picked(int col)

  readonly property real axisW: 44
  readonly property real labelH: 36
  readonly property real topPad: 22
  readonly property real plotH: Math.max(10, height - labelH - topPad)
  readonly property real plotW: Math.max(10, width - axisW)
  readonly property real colW: plotW / 7
  readonly property real barW: Math.max(14, Math.min(72, colW * 0.56))
  readonly property real maxMin: week ? Math.max(60, week.maxMin) : 60
  readonly property real step: maxMin > 600 ? 180 : (maxMin > 300 ? 120 : 60)
  function py(min) { return plotH * (1 - min / maxMin) + topPad }
  function tone(slot) { var s = M.series(slot); return Qt.alpha(Theme.color[s.tok], s.a) }

  objectName: "weekChart"

  // gridlines and hour labels
  Repeater {
    model: Math.floor(c.maxMin / c.step) + 1
    Item {
      required property int index
      readonly property real min: index * c.step
      x: 0
      y: c.py(min)
      width: c.width
      height: 1
      Rectangle { x: c.axisW; width: parent.width - c.axisW; height: 1; color: Theme.color.outlineVariant; opacity: parent.min === 0 ? 1 : 0.5 }
      DText { x: 0; y: -height / 2; width: c.axisW - 8; horizontalAlignment: Text.AlignRight; text: Math.round(parent.min / 60) + "h"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
    }
  }

  Repeater {
    model: c.week ? c.week.rows : []
    Item {
      id: col
      required property var modelData
      required property int index
      readonly property bool sel: c.selCol === index
      x: c.axisW + index * c.colW
      width: c.colW
      height: c.height

      Rectangle {
        visible: col.sel
        x: 4
        y: c.topPad - 14
        width: parent.width - 8
        height: c.plotH + 14 + c.labelH - 4
        radius: Theme.radius.row
        color: Qt.alpha(Theme.color.fg, Theme.alpha.rest)
        FocusRing { focused: col.sel && c.focused }
      }

      // the day's bar: zone segments, then the unattributed rest
      Item {
        id: bar
        objectName: "weekBar"
        x: (col.width - c.barW) / 2
        width: c.barW
        y: c.py(col.modelData.workedMin || 0)
        height: Math.max(0, c.py(0) - y)
        visible: col.modelData.has && (col.modelData.workedMin || 0) > 0
        Column {
          anchors.bottom: parent.bottom
          width: parent.width
          spacing: 0
          Rectangle {
            width: parent.width
            height: c.plotH * col.modelData.restMin / c.maxMin
            visible: height > 0.5
            radius: 3
            color: Theme.color.outline
            opacity: 0.55
          }
          Repeater {
            model: col.modelData.segs
            Rectangle {
              required property var modelData
              width: bar.width
              height: Math.max(1, c.plotH * modelData.min / c.maxMin)
              color: c.tone(modelData.slot)
              opacity: (c.selSlot < 0 || c.selSlot === modelData.slot) ? 1 : 0.25
              border.width: 1
              border.color: Theme.color.surface
            }
          }
        }
      }
      // future, off and missing days keep their slot
      Rectangle {
        visible: !bar.visible
        x: (col.width - c.barW) / 2
        y: c.py(0) - 3
        width: c.barW
        height: 3
        radius: 1.5
        color: Theme.color.outlineVariant
        opacity: col.modelData.future ? 0.4 : 0.9
      }
      DText {
        visible: bar.visible
        x: 0
        y: bar.y - height - 1
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: M.hm(col.modelData.workedMin)
        role: "bodyS"
        mono: true
        font.weight: col.modelData.isToday ? Font.DemiBold : Font.Normal
        color: col.modelData.met ? Theme.color.accent : Theme.color.fg
        style: Text.Outline
        styleColor: Theme.color.surface
      }
      DText {
        visible: !bar.visible && !col.modelData.future && col.modelData.has
        x: 0
        y: c.py(0) - height - 6
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: M.kindText(col.modelData.kind) || "none"
        role: "caption"
        font.capitalization: Font.MixedCase
        font.letterSpacing: 0
        dim: true
      }
      Column {
        x: 0
        y: c.py(0) + 6
        width: parent.width
        DText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: col.modelData.label; role: "bodyS"; font.weight: col.modelData.isToday ? Font.DemiBold : Font.Normal; color: col.modelData.isToday ? Theme.color.accent : Theme.color.fg }
        DText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: col.modelData.num; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: c.picked(col.index) }
    }
  }

  // the target line, drawn over the bars
  Item {
    visible: c.week && c.week.targetLineMin > 0
    objectName: "targetLine"
    x: c.axisW
    y: c.py(c.week ? c.week.targetLineMin : 0)
    width: c.plotW
    height: 1
    z: 3
    Repeater {
      model: Math.ceil(c.plotW / 12)
      Rectangle { required property int index; x: index * 12; width: 7; height: 1; color: Theme.color.accent }
    }
    DText {
      anchors.right: parent.right
      y: -height - 1
      text: "target " + M.hm(c.week ? c.week.targetLineMin : 0)
      role: "caption"
      font.capitalization: Font.MixedCase
      font.letterSpacing: 0
      color: Theme.color.accent
    }
  }
}
