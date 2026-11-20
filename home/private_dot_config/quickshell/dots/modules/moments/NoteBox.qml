import QtQuick
import "../theme"

// The board's inset note: panel fill, radius 10, content padded and stacked.
Rectangle {
  id: root

  property int padX: Theme.space.xl
  property int padY: Theme.space.xl
  property int gap: Theme.space.m
  default property alias content: inner.data

  width: parent ? parent.width : 400
  implicitHeight: inner.implicitHeight + 2 * padY
  height: implicitHeight
  color: Theme.color.surface
  radius: Theme.radius.row

  Column {
    id: inner
    x: root.padX
    y: root.padY
    width: root.width - 2 * root.padX
    spacing: root.gap
  }
}
