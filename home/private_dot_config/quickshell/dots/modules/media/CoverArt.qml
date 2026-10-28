import QtQuick
import "../theme"

// Cover art, rounded, with a quiet placeholder when the player supplies none.
Item {
  property string source: ""

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.chip
    color: Theme.color.surfaceContainer
  }
  Image {
    id: img
    anchors.fill: parent
    source: parent.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: 128
    sourceSize.height: 128
    visible: status === Image.Ready
  }
}
