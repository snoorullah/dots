pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The player to show: the one that is playing, else the first. No player, no popout.
Singleton {
  id: root

  readonly property var players: Mpris.players.values
  readonly property var active: {
    var v = Mpris.players.values;
    for (var i = 0; i < v.length; i++)
      if (v[i].isPlaying) return v[i];
    return v.length > 0 ? v[0] : null;
  }
  readonly property bool present: active !== null
}
