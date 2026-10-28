import QtQuick
import "../theme"
import "../common"

// A labelled switch. On is a neutral lift; `held` marks a state I keep open on purpose
// (do-not-disturb, night light), which is the one case that spends colour: an amber wash.
MouseArea {
  id: root

  property string icon: ""
  property string label: ""
  property bool on: false
  property bool held: false
  property bool available: true

  width: 140
  height: 44
  visible: available
  hoverEnabled: true

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.chip
    color: root.on && root.held ? Qt.alpha(Theme.color.amber, Theme.alpha.wash)
         : Qt.alpha(Theme.color.fg, root.on ? Theme.alpha.on : (root.containsMouse ? Theme.alpha.hover : Theme.alpha.rest))
  }
  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.chip
    color: Qt.alpha(Theme.color.fg, Theme.alpha.pressed)
    visible: root.pressed
  }
  Row {
    anchors.verticalCenter: parent.verticalCenter
    x: Theme.space.xl
    spacing: Theme.space.l
    Icon {
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon
      size: Theme.font.size.title
      color: root.on && root.held ? Theme.color.amber : Theme.color.fg
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      role: "bodyS"
    }
  }
}
