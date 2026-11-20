import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "../services"
import "../modules/moments/js/Moments.js" as Moments
import "../modules/moments"

// `qs ipc call dots.<surface> <fn> [arg]`. These are also the keybind twins of every
// conditional surface: a zero-width chip has no click target, so each one has a call here.
// (The overview registers dots.overview itself.)
Scope {
  id: root

  property var notifs: null
  property var toasts: null
  property var capture: null
  property var launcher: null
  property var winSwitcher: null

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
      Lamp.fire(5000);
      Overview.lamp(5000);
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

    function toggle(): void { root.openPopout("system", 0.93); }
  }

  IpcHandler {
    target: "dots.system"

    function toggle(): void { root.openPopout("system", 0.93); }
  }
  // Centred cards: screen from the focused monitor, then Ui.toggle (no notch to point at).
  function toggleCard(name) {
    var s = root.screenFor();
    Ui.toggle(name, s ? s.name : "", -1);
  }

  IpcHandler {
    target: "dots.launcher"

    // prefix: "" for All, or a mode prefix such as "c:" (clipboard) or "d:" (dictionary)
    function toggle(prefix: string): void {
      if (!root.launcher) return;
      root.launcher.startMode = prefix;
      root.toggleCard("launcher");
    }
    // open with text already typed (the workspace switcher's "Open in launcher" row)
    function query(text: string): void {
      if (!root.launcher) return;
      var s = root.screenFor();
      if (s) Ui.screenName = s.name;
      root.launcher.openWith(text);
    }
  }

  IpcHandler {
    target: "dots.away"

    function toggle(): void { root.toggleCard("away"); }
  }

  IpcHandler {
    target: "dots.session"

    function toggle(): void { root.openPopout("session", 0.93); }
  }

  IpcHandler {
    target: "dots.winswitch"

    // held-Alt cycling: Alt+Tab calls next/prev, the Alt release calls release (commit() picks now)
    function next(): void { if (root.winSwitcher) root.winSwitcher.next(); }
    function prev(): void { if (root.winSwitcher) root.winSwitcher.prev(); }
    function release(): void { if (root.winSwitcher) root.winSwitcher.release(); }
    function commit(): void { if (root.winSwitcher) root.winSwitcher.ctl.commit(); }
  }

  IpcHandler {
    target: "dots.wallpaper"

    function toggle(): void { root.toggleCard("wallpaper"); }
  }

  IpcHandler {
    target: "dots.logomenu"

    function toggle(): void { root.openPopout("logomenu", 0.03); }
  }

  IpcHandler {
    target: "dots.scratchpad"

    function toggle(): void { root.toggleCard("scratchpad"); }
  }

  IpcHandler {
    target: "dots.restore"

    // ask "Restore yesterday's layout?" (the windows module also asks once at login by itself)
    function prompt(): void { root.toggleCard("restore"); }
  }

  IpcHandler {
    target: "dots.tiling"

    function toggle(): void { root.toggleCard("tiling"); }
  }

  IpcHandler {
    target: "dots.workspaces"

    function toggle(): void { root.openPopout("workspaces", 0.12); }
  }

  IpcHandler {
    target: "dots.cc"

    // tab: queue | inbox | agents | work | time (empty: the last tab)
    function toggle(tab: string): void {
      var s = root.screenFor();
      if (s) Ui.screenName = s.name;
      Ui.toggleCc(tab);
    }
  }

  IpcHandler {
    target: "dots.sidebar"

    function toggle(): void {
      var s = root.screenFor();
      if (s) Ui.screenName = s.name;
      Ui.toggleSidebar();
    }
  }

  IpcHandler {
    target: "dots.capture"

    function toggle(): void { if (root.capture) root.capture.toggle(); }
  }

  IpcHandler {
    target: "dots.ret"

    // back to the task: only while a detour is active. The workspace its terminal was on,
    // then dots-jump <ref> (local); both argv-only, in MomentState.back()
    function back(): void { MomentState.back(); }
  }

  IpcHandler {
    target: "dots.notif"

    function toggle(): void { root.openPopout("center", 0.9); }
    function dnd(): void { if (root.notifs) root.notifs.dnd = !root.notifs.dnd; }
    // test hook: how many toasts are on screen right now
    function count(): int { return root.toasts ? root.toasts.visibleCount() : 0; }
    // test hook: notifications held in the centre (-1: another daemon owns the bus)
    function stored(): int { return !root.notifs ? 0 : root.notifs.held ? -1 : root.notifs.count; }
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
