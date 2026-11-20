import QtQuick
import Quickshell.Io
import "js/Parse.js" as Parse

// The facts the existing services do not carry, each from one local read-only command
// (argv, never a shell string). Read when the panel opens and after an action; there
// is no polling. Every property is empty or null until its command has answered.
Item {
  id: root

  property string uptimeText: ""
  property string host: ""
  property var nets: []
  property var wired: null
  property var vpnConns: []
  property string profile: ""
  property var mic: null
  property var ts: null          // null = binary missing or output unreadable
  property var gpu: null

  function refresh() {
    var all = [pUptime, pHost, pWifi, pWired, pVpn, pProfile, pMic, pTs, pGpu];
    for (var i = 0; i < all.length; i++)
      if (!all[i].running) all[i].running = true;
  }

  Process {
    id: pUptime
    command: ["cat", "/proc/uptime"]
    stdout: StdioCollector { onStreamFinished: root.uptimeText = text }
  }
  Process {
    id: pHost
    command: ["hostname"]
    stdout: StdioCollector { onStreamFinished: root.host = text.trim() }
  }
  Process {
    id: pWifi
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list"]
    stdout: StdioCollector { onStreamFinished: root.nets = Parse.wifiList(text) }
  }
  Process {
    id: pWired
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
    stdout: StdioCollector { onStreamFinished: root.wired = Parse.wired(text) }
  }
  Process {
    id: pVpn
    command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
    stdout: StdioCollector { onStreamFinished: root.vpnConns = Parse.vpnList(text) }
  }
  Process {
    id: pProfile
    command: ["powerprofilesctl", "get"]
    stdout: StdioCollector { onStreamFinished: root.profile = Parse.profile(text) }
  }
  Process {
    id: pMic
    command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
    stdout: StdioCollector { onStreamFinished: root.mic = Parse.mic(text) }
  }
  Process {
    id: pTs
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector { onStreamFinished: root.ts = Parse.tailscale(text) }
  }
  Process {
    id: pGpu
    command: ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total",
              "--format=csv,noheader,nounits"]
    stdout: StdioCollector { onStreamFinished: root.gpu = Parse.gpu(text) }
  }
}
