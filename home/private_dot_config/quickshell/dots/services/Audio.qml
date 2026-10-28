pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Default sink volume and mute. `ready` is false when there is no sink (or no PipeWire),
// and the volume chip then shows a hollow "?" rather than a number it cannot vouch for.
Singleton {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool ready: sink !== null && sink.audio !== null
  readonly property real volume: ready ? sink.audio.volume : 0
  readonly property bool muted: ready ? sink.audio.muted : false

  function setVolume(v) {
    if (ready) sink.audio.volume = Math.max(0, Math.min(1, v));
  }
  function toggleMute() {
    if (ready) sink.audio.muted = !sink.audio.muted;
  }

  PwObjectTracker {
    objects: root.sink ? [root.sink] : []
  }
}
