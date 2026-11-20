pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// The wide now-playing card of the board (art, title, artist and album, progress, controls).
// Component only; the live popout for it is modules/media. `media` is
// {title, artist, album, art, playing, pos, len} in seconds, or null.
Surface {
  id: root

  property var media: null
  signal command(string what)

  implicitWidth: 440
  implicitHeight: 160
  width: implicitWidth
  height: implicitHeight
  corner: Theme.radius.card

  readonly property real frac: media && media.len > 0 ? Math.max(0, Math.min(1, media.pos / media.len)) : 0
  function clock(sec) {
    var s = Math.max(0, Math.floor(sec || 0));
    return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
  }

  Row {
    anchors { fill: parent; margins: 14 }
    spacing: 14

    Rectangle {
      id: art
      width: 132; height: 132
      radius: 12
      color: Qt.alpha(Theme.color.accent, 0.3)
      clip: true
      Image {
        anchors.fill: parent
        source: root.media && root.media.art ? root.media.art : ""
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
      }
    }

    Item {
      width: parent.width - art.width - parent.spacing
      height: parent.height

      Column {
        width: parent.width
        DText { width: parent.width; role: "headline"; text: root.media ? root.media.title : ""; elide: Text.ElideRight }
        SText { width: parent.width; dim: true; elide: Text.ElideRight
                text: root.media ? [root.media.artist, root.media.album].filter(function (x) { return x }).join(" · ") : "" }
      }

      Column {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 12 }
        spacing: 4
        Rectangle {
          width: parent.width; height: 3; radius: 2
          color: Qt.alpha(Theme.color.fg, 0.16)
          Rectangle { width: parent.width * root.frac; height: 3; radius: 2; color: Qt.alpha(Theme.color.fg, 0.8) }
        }
        SText { dim: true; text: root.media ? root.clock(root.media.pos) + " / " + root.clock(root.media.len) : ""; mono: true }
      }

      Row {
        anchors { left: parent.left; bottom: parent.bottom }
        spacing: 14
        Repeater {
          model: [
            { icon: "prev", what: "previous", size: 18 },
            { icon: root.media && root.media.playing ? "pause" : "play", what: "toggle", size: 22 },
            { icon: "next", what: "next", size: 18 }
          ]
          Item {
            id: b
            required property var modelData
            width: 28; height: 28
            SIcon { anchors.centerIn: parent; key: b.modelData.icon; boardSize: b.modelData.size; active: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.command(b.modelData.what) }
          }
        }
      }
    }
  }
}
