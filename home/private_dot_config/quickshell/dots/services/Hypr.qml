pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Workspaces and focus, read from Quickshell's Hyprland module.
//
// Switching is NOT Hyprland.dispatch(): Hyprland 0.56 runs a Lua config, wraps every
// dispatch payload server-side as hl.dispatch(<payload>), and rejects the legacy
// "workspace 3" form. The documented form below works on the raw socket and via hyprctl.
Singleton {
  id: root

  readonly property var workspaces: {
    var out = [];
    var v = Hyprland.workspaces.values;
    for (var i = 0; i < v.length; i++)
      if (v[i].id > 0) out.push({ id: v[i].id, name: v[i].name });
    out.sort(function (a, b) { return a.id - b.id; });
    return out;
  }
  readonly property int activeId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  function focus(n) {
    var id = parseInt(n);
    if (!(id > 0)) return;
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + id + "\" })"]);
  }
}
