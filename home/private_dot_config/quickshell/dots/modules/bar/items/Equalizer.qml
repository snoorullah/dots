pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../js/Eq.js" as Eq

// 36 hairline bars. In the shell they should follow the audio output; until a spectrum
// source exists they imitate it from js/Eq.js. Paused: they hold at rest height, dim.
// This is the only thing in the bar that moves by itself.
Item {
  id: root

  property bool playing: true
  property real time: -1            // fixed time for tests; -1 follows the clock
  property real now: 0
  readonly property int barH: Theme.space.xxxl

  width: Eq.count * 2 - 1
  height: barH
  opacity: playing ? 1 : 0.55

  Timer {
    interval: 50
    running: root.playing && root.time < 0 && root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now() / 1000
  }

  Row {
    spacing: 1
    anchors.fill: parent

    Repeater {
      model: Eq.count

      Item {
        id: bar
        objectName: "eqBar"
        required property int index
        width: 1
        height: root.barH

        Rectangle {
          width: 1
          radius: 0.5
          anchors.verticalCenter: parent.verticalCenter
          height: Math.max(1, root.barH * (root.playing ? Eq.scale(bar.index, root.time >= 0 ? root.time : root.now) : Eq.rest(bar.index)))
          color: Qt.alpha(Theme.color.fg, 0.85)
        }
      }
    }
  }
}
