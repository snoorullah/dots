import QtQuick
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts

// One KPI: label, the value, the previous period's value with the change and its direction, and
// a 30-day sparkline. `has` false says "no data" instead of a zero.
Card {
  id: k
  property string label: ""
  property string icon: ""
  property bool has: true
  property string value: ""
  property string prev: ""
  property string prevLabel: "before"
  property string delta: ""
  property string dir: "flat"
  property string tone: "neutral"
  property string note: ""
  property var spark: []
  property bool sparkFromZero: true
  property real sparkFrac: 0.42        // the share of the card width the sparkline may take
  property bool focused: false
  property bool picked: false
  pad: 12
  objectName: "kpiCard"
  implicitHeight: 92
  color: k.picked ? Theme.color.surfaceContainer : Theme.color.surface
  FocusRing { parent: k; focused: k.focused; radius: Theme.radius.card + 4 }
  Column {
    id: txt
    width: parent.width
    spacing: 2
    Row {
      spacing: 6
      Icon { visible: k.icon !== ""; name: k.icon; size: 16; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
      DText { text: k.label; role: "bodyS"; dim: true; anchors.verticalCenter: parent.verticalCenter }
    }
    DText { objectName: "kpiValue"; text: k.has ? k.value : "no data"; role: "headline"; mono: true; font.weight: Font.Medium; opacity: k.has ? 1 : 0.5 }
    Row {
      visible: k.has && k.delta !== ""
      spacing: 8
      Delta { dir: k.dir; tone: k.tone; text: k.delta; anchors.verticalCenter: parent.verticalCenter }
      DText { visible: k.prev !== ""; text: k.prevLabel + " " + k.prev; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true; anchors.verticalCenter: parent.verticalCenter }
    }
    DText { objectName: "kpiNote"; visible: k.has && k.note !== ""; text: k.note; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; dim: true }
  }
  Spark {
    visible: k.has && k.spark.length > 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 4
    height: 34
    width: Math.min(Math.floor(parent.width * k.sparkFrac), Math.max(0, k.spark.length * 4.5 - 1.5))
    gap: 1.5
    barW: Math.max(1, Math.min(3, (width - gap * Math.max(0, k.spark.length - 1)) / Math.max(1, k.spark.length)))   // the bars always fit the width
    values: k.spark
    fromZero: k.sparkFromZero
  }
}
