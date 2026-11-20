pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// The compact now-playing row: art disc, title, artist, previous / play-pause / next.
// `media` is {title, artist, art, playing} or null (no player = no row).
Rectangle {
  id: root

  property var media: null
  signal command(string what)      // previous | toggle | next

  visible: media !== null
  implicitHeight: visible ? 60 : 0
  radius: 12
  color: Qt.alpha(Theme.color.fg, 0.06)

  Row {
    anchors { fill: parent; margins: 10 }
    spacing: 10
    Rectangle {
      id: disc
      width: 40; height: 40; radius: 20
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.alpha(Theme.color.accent, 0.3)
      clip: true
      Image {
        anchors.fill: parent
        source: root.media && root.media.art ? root.media.art : ""
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
      }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - disc.width - controls.width - 20
      SText { width: parent.width; text: root.media ? root.media.title : ""; font.weight: 600; elide: Text.ElideRight }
      SText { width: parent.width; text: root.media ? root.media.artist : ""; dim: true; elide: Text.ElideRight }
    }
    Row {
      id: controls
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.xl
      Repeater {
        model: [
          { icon: "prev", what: "previous", size: 16 },
          { icon: root.media && root.media.playing ? "pause" : "play", what: "toggle", size: 18 },
          { icon: "next", what: "next", size: 16 }
        ]
        Item {
          id: btn
          required property var modelData
          width: 24; height: 24
          SIcon { anchors.centerIn: parent; key: btn.modelData.icon; boardSize: btn.modelData.size; active: true }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.command(btn.modelData.what) }
        }
      }
    }
  }
}
