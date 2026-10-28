import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "../services"

// `qs ipc call dots.<surface> <fn> [arg]`. These are also the keybind twins of every
// conditional surface: a zero-width chip has no click target, so each one has a call here.
// (The overview registers dots.overview itself.)
Scope {
  id: root

  property var notifs: null
  property var toasts: null

  function screenFor() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  // open a popout on the focused screen, hanging from `frac` of its width
  function openPopout(name, frac) {
    var s = root.screenFor();
    if (!s) return;
    Ui.toggle(name, s.name, s.width * frac);
  }

  IpcHandler {
    target: "dots.bar"

    function reload(): void { Quickshell.reload(true); }
    function lamp(): void {
      Lamp.fire(1200);
      Overview.lamp(1200);
    }
    function calendar(): void { root.openPopout("calendar", 0.5); }
    function media(): void { root.openPopout("media", 0.5); }
    function caffeine(): void { Caffeine.toggle(); }
    function ctx(): void {
      Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/waybar-ctx.sh", "cycle"]);
    }
  }

  IpcHandler {
    target: "dots.quick"

    function toggle(): void { root.openPopout("quick", 0.93); }
  }

  IpcHandler {
    target: "dots.notif"

    function toggle(): void { root.openPopout("center", 0.9); }
    function dnd(): void { if (root.notifs) root.notifs.dnd = !root.notifs.dnd; }
    // test hook: how many toasts are on screen right now
    function count(): int { return root.toasts ? root.toasts.visibleCount() : 0; }
  }

  IpcHandler {
    target: "dots.osd"

    // `dots-shell key` sets the level through wpctl/brightnessctl, then asks for the OSD.
    // Not called "show": the CLI reads `ipc call t show x` as its own `ipc show` subcommand.
    function display(kind: string): void {
      if (kind === "brightness") {
        Brightness.refresh();
        Hud.show("brightness", Brightness.value, false);
      } else {
        Hud.show("volume", Audio.volume, Audio.muted);
      }
    }
  }
}
