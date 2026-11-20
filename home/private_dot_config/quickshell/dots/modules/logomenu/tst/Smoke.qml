import QtQuick
import Quickshell
import "modules/logomenu"
import "services"

// Wiring smoke for tests/menus-ui.sh: the real LogoCtl (the menu minus its layer-shell window) is opened through Ui.open on the
// offscreen platform. The mode is read through py/recover.py (a temp state dir); no recovery
// action, lock or logout is run.
ShellRoot {
    id: sc
    property int step: 0

    FloatingWindow { implicitWidth: 100; implicitHeight: 100; LogoCtl { id: lm } }

    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            sc.step++
            if (sc.step === 1) Ui.open = "logomenu"
            else if (sc.step === 3) {
                console.log("SMOKE logomenu head=" + lm.m.head.t + " rows=" + lm.m.rowCount + " mode=" + lm.mode + " sel=" + lm.m.sel)
                Ui.open = ""
            }
            else if (sc.step === 4) Qt.quit()
        }
    }
}
