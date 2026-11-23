pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// A small bar sparkline: one thin bar per value, the latest in the accent token. `fromZero`
// scales bars against 0; off (clock times) they scale between the lowest and highest value.
Item {
  id: s
  property var values: []
  property real barW: 4
  property real gap: 2
  property bool fromZero: true
  property color tint: Theme.color.fgDim
  property color latest: Theme.color.accent
  readonly property real maxVal: {
    var m = 0
    for (var i = 0; i < values.length; i++) m = Math.max(m, values[i])
    return m
  }
  readonly property real minVal: {
    if (fromZero || values.length === 0) return 0
    var m = values[0]
    for (var i = 1; i < values.length; i++) m = Math.min(m, values[i])
    return m
  }
  objectName: "spark"
  implicitHeight: 28
  implicitWidth: Math.max(0, values.length * (barW + gap) - gap)
  Repeater {
    model: s.values
    Rectangle {
      required property var modelData
      required property int index
      readonly property real span: s.maxVal - s.minVal
      x: index * (s.barW + s.gap)
      width: s.barW
      height: span > 0 ? Math.max(2, (s.height - 3) * (modelData - s.minVal) / span + 3) : 3
      y: s.height - height
      radius: 1
      color: index === s.values.length - 1 ? s.latest : s.tint
      opacity: index === s.values.length - 1 ? 1 : 0.7
    }
  }
}
