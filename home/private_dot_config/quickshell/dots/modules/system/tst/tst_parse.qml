import QtQuick
import QtTest
import "../js/Parse.js" as P

TestCase {
    name: "Parse"

    function test_uptime() {
        compare(P.uptime("68400.12 1234.5"), "up 19h")
        compare(P.uptime("2520.0 1"), "up 42m")
        compare(P.uptime("90000 1"), "up 1d 1h")
        compare(P.uptime("30 1"), "up 0m")
        compare(P.uptime(""), "")
        compare(P.uptime("junk"), "")
    }

    function test_wifi_list() {
        var raw = "*:Home 5G:92:WPA3:5180 MHz\n"
            + " :Home 2.4:80:WPA2:2437 MHz\n"
            + " :Guest:55: :2412 MHz\n"
            + " :Weak\\:Net:20:WPA2:2412 MHz\n"
            + " ::70:WPA2:2412 MHz\n"
            + " :Home 2.4:30:WPA2:2437 MHz\n"
        var l = P.wifiList(raw)
        compare(l.length, 4)
        compare(l[0].ssid, "Home 5G"); verify(l[0].cur); verify(l[0].lock)
        compare(l[0].sub, "5 GHz, strong, WPA3")
        compare(l[1].ssid, "Home 2.4"); compare(l[1].signal, 80)
        compare(l[1].sub, "2.4 GHz, strong, WPA2")
        compare(l[2].ssid, "Guest"); verify(!l[2].lock)
        compare(l[2].sub, "2.4 GHz, ok, open network")
        compare(l[3].ssid, "Weak:Net")
        compare(l[3].sub, "2.4 GHz, weak, WPA2")
        compare(P.wifiList("").length, 0)
    }

    function test_profile_and_mic() {
        compare(P.profile("balanced\n"), "balanced")
        compare(P.profile("performance"), "performance")
        compare(P.profile("rm -rf"), "")
        var m = P.mic("Volume: 0.70 [MUTED]\n")
        compare(m.v, 70); verify(m.muted)
        m = P.mic("Volume: 0.35")
        compare(m.v, 35); verify(!m.muted)
        compare(P.mic("nope"), null)
    }

    function test_vpn() {
        var raw = "Work:wireguard:no\nTravel:vpn:yes\nWired:802-3-ethernet:yes\nlo:loopback:no\n"
        var l = P.vpnList(raw)
        compare(l.length, 2)
        compare(l[0].name, "Work"); verify(!l[0].cur)
        compare(l[1].name, "Travel"); verify(l[1].cur)
    }

    function test_tailscale() {
        var j = JSON.stringify({ BackendState: "Running", Self: { HostName: "desk" },
            Peer: {
                a: { HostName: "laptop", Online: true, CurAddr: "1.2.3.4:5", TailscaleIPs: ["100.64.0.2"] },
                b: { HostName: "phone", Online: true, CurAddr: "", Relay: "fra", TailscaleIPs: ["100.64.0.3"] },
                c: { HostName: "nas", Online: false, TailscaleIPs: ["100.64.0.4"] }
            } })
        var t = P.tailscale(j)
        verify(t.on)
        compare(t.peers.length, 3)
        compare(t.peers[0].name, "laptop"); compare(t.peers[0].sub, "online, direct"); verify(t.peers[0].cur)
        compare(t.peers[1].sub, "online, relayed")
        compare(t.peers[2].sub, "offline"); verify(!t.peers[2].cur)
        compare(t.peers[0].ip, "100.64.0.2")
        compare(P.tailscale("garbage"), null)
        verify(!P.tailscale(JSON.stringify({ BackendState: "Stopped", Peer: {} })).on)
    }

    function test_gpu() {
        var g = P.gpu("54, 18, 9318, 24564\n")
        compare(g.temp, 54); compare(g.busy, 18)
        compare(g.vramPct, 38)
        compare(g.vramLabel, "9.1 of 24 GB")
        compare(P.gpu(""), null)
    }

    function test_pct_kelvin() {
        compare(P.clampPct(0.456), 46)
        compare(P.clampPct(-1), 0)
        compare(P.clampPct(7), 100)
        compare(P.warmthToKelvin(0), 6500)
        compare(P.warmthToKelvin(100), 2500)
        compare(P.kelvinToWarmth(4300), 55)
        compare(P.kelvinToWarmth(9999), 0)
    }

    function test_wired() {
        var w = P.wired("lo:loopback:unmanaged:\neth0:ethernet:connected:Wired connection 1\nwlan0:wifi:connected:Home 5G\n")
        compare(w.name, "Ethernet"); compare(w.sub, "connected")
        compare(P.wired("eth0:ethernet:unavailable:\n"), null)
        compare(P.wired(""), null)
    }
}
