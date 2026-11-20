import QtQuick
import Quickshell
import "modules/system"
import "services"

// Wiring smoke test: the real SystemPanel against the real services, Popout stubbed.
// Proves the state object builds, the panel opens on Ui.open, an open act changes the view
// and an argv act runs. Prints `SMOKE {json}` and quits.
ShellRoot {
    SystemPanel { id: p }

    property var out: ({})
    Timer {
        interval: 600; running: true
        onTriggered: {
            Ui.open = "system"
            out.wantedAfterOpen = p.wanted
        }
    }
    Timer {
        interval: 1800; running: true
        onTriggered: {
            out.keys = Object.keys(p.st).sort()
            out.tiles = p.st.wifi !== undefined && p.st.perf !== undefined
            out.vpnIsArray = Array.isArray(p.st.vpn.conns)
            p.run({ op: "open", id: "perf" })
            out.view = p.view
            p.run({ op: "argv", argv: ["true"] })
            p.run({ op: "off", why: "x" })
            p.run({ op: "nope" })
            Ui.open = ""
            out.viewAfterClose = p.view
            console.log("SMOKE " + JSON.stringify(out))
            Qt.quit()
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.log("SMOKE TIMEOUT"); Qt.quit() } }
}
