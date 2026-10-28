import QtQuick
import ".."
import "../../theme"
import "../../common"
import "../../../services"

// Output volume. Always present (the quiet right slab is volume and tray). No sink,
// or PipeWire not answering -> a hollow "?" instead of a number it cannot vouch for.
// Scroll adjusts, click mutes, right-click opens the quick panel.
Chip {
  id: chip

  readonly property int pct: Math.round(Audio.volume * 100)

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.space.s

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      visible: Audio.ready
      text: Audio.muted || chip.pct === 0 ? "volume_off" : (chip.pct < 40 ? "volume_down" : "volume_up")
      size: Theme.font.size.title
    }
    DText {
      anchors.verticalCenter: parent.verticalCenter
      mono: true
      visible: Audio.ready && !Audio.muted
      text: chip.pct + "%"
    }
    Stale {
      anchors.verticalCenter: parent.verticalCenter
      on: !Audio.ready
    }
  }

  onClicked: button => {
    if (button === Qt.RightButton) chip.popout("quick");
    else if (Audio.ready) { Audio.toggleMute(); Hud.show("volume", Audio.volume, Audio.muted); }
  }
  onScrolled: dy => {
    if (!Audio.ready) return;
    Audio.setVolume(Audio.volume + (dy > 0 ? 0.02 : -0.02));
    Hud.show("volume", Audio.volume, Audio.muted);
  }
}
