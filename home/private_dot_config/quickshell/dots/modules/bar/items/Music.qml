import QtQuick
import "../../theme"
import "../../common"
import ".."

// Album disc, song over artist, equalizer. Paused: the bars hold still and the song dims.
// Fixed 270 wide so the pill does not breathe when a title changes.
Chip {
  id: root

  property var music: ({ present: false, playing: false, title: "", artist: "", art: "" })
  property real eqTime: -1
  property int blockWidth: 270      // the pill gives some back when it is crowded
  readonly property int art: Theme.space.xxxl + Theme.space.m - Theme.space.s     // 28

  objectName: "music"
  padX: 0
  spacing: Theme.space.l + 2
  hoverable: false
  visible: music.present

  Rectangle {
    id: disc
    anchors.verticalCenter: parent.verticalCenter
    width: root.art
    height: root.art
    radius: Theme.radius.pill
    color: Qt.alpha(Theme.color.accent, 0.3)
    border.width: 1
    border.color: Qt.alpha(Theme.color.fg, Theme.alpha.divider - 0.04)
    clip: true

    Image {
      anchors.fill: parent
      visible: status === Image.Ready
      source: root.music.art
      fillMode: Image.PreserveAspectCrop
      sourceSize: Qt.size(root.art * 2, root.art * 2)
      asynchronous: true
    }
  }

  Column {
    anchors.verticalCenter: parent.verticalCenter
    width: root.blockWidth - root.art - eq.width - 2 * root.spacing

    DText {
      objectName: "songTitle"
      width: parent.width
      elide: Text.ElideRight
      font.pixelSize: Theme.font.size.caption
      font.weight: Theme.font.weight.label
      lineHeight: 15
      text: root.music.title
      color: root.music.playing ? Theme.color.fg : Theme.color.fgDim
    }
    DText {
      objectName: "songArtist"
      width: parent.width
      elide: Text.ElideRight
      font.pixelSize: Theme.font.size.caption
      lineHeight: 15
      dim: true
      text: root.music.artist
    }
  }

  Equalizer {
    id: eq
    objectName: "eq"
    anchors.verticalCenter: parent.verticalCenter
    playing: root.music.playing
    time: root.eqTime
  }
}
