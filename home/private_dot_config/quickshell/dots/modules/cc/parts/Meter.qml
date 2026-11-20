import QtQuick
import qs.modules.theme

// A horizontal share bar: accent fill on the track colour.
Item {
  id: m
  property real value: 0      // 0..100
  property int barHeight: 6
  property color fill: Theme.color.accent
  implicitHeight: barHeight
  Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.color.outlineVariant }
  Rectangle { width: Math.max(0, Math.min(1, m.value / 100)) * parent.width; height: parent.height; radius: height / 2; color: m.fill }
}
