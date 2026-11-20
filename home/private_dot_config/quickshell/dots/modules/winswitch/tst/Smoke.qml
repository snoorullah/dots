import QtQuick
import Quickshell
import "modules/winswitch"
import "services"

// Wiring smoke for tests/menus-ui.sh: the real WinCtl (the whole behaviour, minus the layer-shell window) is loaded
// on the offscreen platform with the real services, and driven through a quick flip and a held
// Alt+Tab. There is no compositor, so there are no windows: it proves the bindings, the
// Dispatcher round trips and the lock probe run without a QML error. Logs `SMOKE ...` lines.
ShellRoot {
    id: sc
    property int step: 0

    FloatingWindow { implicitWidth: 100; implicitHeight: 100; WinCtl { id: ws } }

    Timer {
        id: t
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            sc.step++
            if (sc.step === 1) { ws.next(); ws.release(); console.log("SMOKE flip phase=" + ws.flow.phase) }
            else if (sc.step === 2) { ws.next(); console.log("SMOKE pressed phase=" + ws.flow.phase) }
            else if (sc.step === 4) { console.log("SMOKE held phase=" + ws.flow.phase + " probeDone=" + ws.probeDone + " locked=" + ws.lockedNow + " shown=" + ws.shown + " open=" + Ui.open + " mode=" + ws.m.mode); ws.release() }
            else if (sc.step === 5) { console.log("SMOKE released phase=" + ws.flow.phase + " open=" + ws.name + ":" + Ui.open); ws.unlocked(); ws.next(); ws.cancel() }
            else if (sc.step === 6) { console.log("SMOKE redact=" + ws.redactUntil.toString().length + " done"); Qt.quit() }
        }
    }
}
