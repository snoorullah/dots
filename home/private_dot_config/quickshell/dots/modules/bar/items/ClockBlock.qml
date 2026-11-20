import QtQuick
import "../../theme"
import "../../common"
import ".."

// Time, date and the next prayer. Clicking the time or date opens the calendar, the prayer
// opens its own popout. The amber dot is the board's; it carries no status.
Row {
  id: root

  property string clock: ""
  property string date: ""
  property string salah: ""
  signal activated(string popout, real x)

  height: parent ? parent.height : Theme.space.xxxl
  spacing: Theme.space.s

  Chip {
    id: when
    objectName: "clockChip"
    anchors.verticalCenter: parent.verticalCenter
    padX: Theme.space.m
    spacing: Theme.space.l + 2

    DText {
      objectName: "clockText"
      anchors.verticalCenter: parent.verticalCenter
      mono: true
      role: "title"
      font.weight: Theme.font.weight.display
      text: root.clock
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 3
      height: 3
      radius: 1.5
      color: Theme.color.waiting
      visible: root.date !== ""
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      role: "bodyS"
      text: root.date
      visible: root.date !== ""
    }
    onClicked: b => root.activated("calendar", when.mapToItem(null, when.width / 2, 0).x)
  }

  Chip {
    id: prayer
    objectName: "salahChip"
    anchors.verticalCenter: parent.verticalCenter
    visible: root.salah !== ""
    padX: Theme.space.m
    spacing: Theme.space.l + 2

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 3
      height: 3
      radius: 1.5
      color: Theme.color.fgDim
    }
    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      name: "mosque"
      box: 15
      color: Qt.alpha(Theme.color.fg, 0.85)
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      role: "bodyS"
      text: root.salah
      color: Qt.alpha(Theme.color.fg, 0.85)
    }
    onClicked: b => root.activated("salah", prayer.mapToItem(null, prayer.width / 2, 0).x)
  }
}
