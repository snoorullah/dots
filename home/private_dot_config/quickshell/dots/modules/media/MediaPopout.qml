pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../../services"

// Now playing: cover art, title and artist, and three controls. Opens from the clock slab
// (middle-click, or `qs ipc call dots.bar media`). No player -> it does not open.
Popout {
  id: win

  readonly property var player: Mpris.active

  name: "media"
  panelWidth: 340

  Row {
    width: parent.width
    spacing: Theme.space.xl

    CoverArt {
      width: 72
      height: 72
      source: win.player ? win.player.trackArtUrl : ""
    }

    Column {
      width: parent.width - 72 - Theme.space.xl
      spacing: Theme.space.s

      DText {
        width: parent.width
        text: win.player ? win.player.trackTitle : ""
        role: "title"
        elide: Text.ElideRight
      }
      DText {
        width: parent.width
        text: win.player ? win.player.trackArtist : ""
        dim: true
        elide: Text.ElideRight
      }
      Row {
        spacing: Theme.space.xl

        Repeater {
          model: [
            { icon: "skip_previous", act: "previous" },
            { icon: win.player && win.player.isPlaying ? "pause" : "play_arrow", act: "toggle" },
            { icon: "skip_next", act: "next" }
          ]

          MouseArea {
            id: btn
            required property var modelData
            width: 28
            height: 28
            onClicked: {
              if (!win.player) return;
              if (btn.modelData.act === "previous") win.player.previous();
              else if (btn.modelData.act === "next") win.player.next();
              else win.player.togglePlaying();
            }
            Rectangle {
              anchors.fill: parent
              radius: Theme.radius.chip
              color: Qt.alpha(Theme.color.fg, btn.containsMouse ? Theme.alpha.hover : 0)
            }
            Icon {
              anchors.centerIn: parent
              text: btn.modelData.icon
              size: Theme.font.size.headline
            }
            hoverEnabled: true
          }
        }
      }
    }
  }
}
