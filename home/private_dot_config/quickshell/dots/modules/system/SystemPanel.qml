pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import "../theme"
import "../common"
import "../../services"
import "js/Parse.js" as Parse
import "js/Menus.js" as Menus

// The system panel: quick tiles, meters, media, the log, and a drill-in menu for each
// setting. Shown when Ui.open === "system". Replaces modules/quick when it is wired in.
// Every control either calls an existing service or runs a local argv; a control with
// no backend is disabled and says so. Nothing here sends anything anywhere.
Popout {
  id: win

  property var notifs: null            // NotifServer: dnd and the log
  property string view: ""             // "" | menu id | "session"

  name: "system"
  panelWidth: 400

  onWantedChanged: {
    if (wanted) { facts.refresh(); Net.refresh(); Brightness.refresh(); }
    else view = "";
  }

  SysState { id: facts }

  Timer {
    id: later
    interval: 700
    onTriggered: facts.refresh()
  }

  function btDevices(connected) {
    var out = [];
    try {
      var devs = Bt.adapter ? Bt.adapter.devices.values : [];
      for (var i = 0; i < devs.length; i++) {
        var d = devs[i];
        if (!!d.connected !== connected) continue;
        if (!connected && !d.paired) continue;
        var bat = d.batteryAvailable ? ", " + Math.round(d.battery * 100) + "%" : "";
        out.push({ addr: d.address, name: d.name || d.deviceName || d.address,
                   sub: connected ? "connected" + bat : "paired, not nearby", kind: d.icon || "" });
      }
    } catch (e) { }
    return out;
  }

  function notifLog() {
    var out = [];
    try {
      var v = notifs && notifs.model ? notifs.model.values : [];
      for (var i = v.length - 1; i >= 0 && out.length < 4; i--) out.push(String(v[i].summary || ""));
    } catch (e) { }
    return out;
  }

  function mediaState() {
    var p = Mpris.active;
    if (!p) return null;
    return { title: p.trackTitle, artist: p.trackArtist, art: p.trackArtUrl, playing: p.isPlaying };
  }

  function screensList() {
    var out = [];
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var s = Quickshell.screens[i];
      out.push({ name: s.name, label: s.name + " " + s.width + "x" + s.height });
    }
    return out;
  }

  // The state object js/Menus.js draws. Rebuilt when any input changes; cheap.
  readonly property var st: ({
    host: facts.host,
    uptime: Parse.uptime(facts.uptimeText),
    bright: { avail: Brightness.available, v: Parse.clampPct(Brightness.value) },
    vol: { avail: Audio.ready, v: Parse.clampPct(Audio.volume), muted: Audio.muted, out: "" },
    mic: { avail: facts.mic !== null, v: facts.mic ? facts.mic.v : 0, muted: facts.mic ? facts.mic.muted : false,
           inputs: [], using: [], ptt: "Off", denoise: false },
    wifi: { avail: Net.available, on: Net.wifi,
            ssid: (function () { for (var i = 0; i < facts.nets.length; i++) if (facts.nets[i].cur) return facts.nets[i].ssid; return ""; })(),
            nets: facts.nets, wired: facts.wired },
    bt: { avail: Bt.available, on: Bt.powered, connected: btDevices(true), paired: btDevices(false) },
    quiet: { avail: win.notifs !== null, on: win.notifs ? win.notifs.dnd : false, held: 0 },
    vpn: { conns: facts.vpnConns },
    ts: { installed: facts.ts !== null, on: facts.ts ? facts.ts.on : false, peers: facts.ts ? facts.ts.peers : [], exit: "None" },
    night: { avail: NightLight.available, on: NightLight.on, kelvin: NightLight.kelvin, until: "" },
    awake: { on: Caffeine.on, command: "" },
    perf: { profile: facts.profile, gpu: facts.gpu, models: [] },
    theme: { source: Theme.source, swatches: [] },
    screens: screensList(),
    media: mediaState(),
    notifs: notifLog(),
    session: { blocker: "", logoutNote: "Ends your day" }
  })

  // An act from the view: a service call, or one local argv.
  function run(act) {
    if (!act) return;
    switch (act.op) {
    case "argv": Quickshell.execDetached(act.argv); break;
    case "wifi": Net.setWifi(act.on); break;
    case "bt": Bt.setPowered(act.on); break;
    case "dnd": if (notifs) notifs.dnd = act.on; break;
    case "nightlight": NightLight.toggle(); break;
    case "caffeine": Caffeine.toggle(); break;
    case "open": view = act.id; break;
    case "btdev": btAct(act); break;
    default: return;
    }
    later.restart();
  }

  function btAct(act) {
    try {
      var devs = Bt.adapter.devices.values;
      for (var i = 0; i < devs.length; i++) {
        if (devs[i].address !== act.addr) continue;
        if (act.does === "disconnect") devs[i].disconnect();
        else if (act.does === "forget") devs[i].forget();
      }
    } catch (e) { }
  }

  function setLevel(which, f) {
    if (which === "bright") { Brightness.set(f); Hud.show("brightness", f, false); }
    else if (which === "vol") { Audio.setVolume(f); Hud.show("volume", f, Audio.muted); }
    else if (which === "mic") Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", f.toFixed(2)]);
  }

  function slide(act, f) {
    if (act.op === "volume") setLevel("vol", f);
    else if (act.op === "brightness") setLevel("bright", f);
    else if (act.op === "micvol") setLevel("mic", f);
    else if (act.op === "kelvin") {
      var k = Parse.warmthToKelvin(Math.round(f * 100));
      NightLight.kelvin = k;
      if (NightLight.on) Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(k)]);
    }
  }

  function mediaCommand(what) {
    var p = Mpris.active;
    if (!p) return;
    if (what === "previous") p.previous();
    else if (what === "next") p.next();
    else p.togglePlaying();
  }

  SystemView {
    width: parent.width
    st: win.st
    view: win.view
    env: ({ sessionId: Quickshell.env("XDG_SESSION_ID") || "", user: Quickshell.env("USER") || "" })
    onViewRequested: v => win.view = v
    onActivated: act => win.run(act)
    onMoved: (act, f) => win.slide(act, f)
    onMeterMoved: (which, f) => win.setLevel(which, f)
    onMediaCommand: what => win.mediaCommand(what)
  }
}
