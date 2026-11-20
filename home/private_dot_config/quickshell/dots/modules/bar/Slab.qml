import QtQuick
import "../theme"

// One pill of the bar: ground at alpha.panel, a hairline, fully round. Children go in a
// Row; the pill is as wide as they are plus its padding.
Rectangle {
  id: slab

  default property alias items: row.data
  property int padLeft: Theme.space.xl
  property int padRight: Theme.space.xl
  property int gap: Theme.space.m
  readonly property int pillHeight: Theme.space.xxxl + Theme.space.xxl   // 40

  implicitHeight: pillHeight
  implicitWidth: row.implicitWidth + padLeft + padRight
  height: implicitHeight
  radius: Theme.radius.pill
  color: Qt.alpha(Theme.color.bg, Theme.alpha.panel)
  border.width: 1
  border.color: Qt.alpha(Theme.color.fg, Theme.alpha.hover + 0.04)

  Row {
    id: row
    x: slab.padLeft
    height: parent.height
    spacing: slab.gap
  }
}
