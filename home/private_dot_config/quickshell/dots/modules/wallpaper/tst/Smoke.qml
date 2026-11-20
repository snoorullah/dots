import QtQuick
import Quickshell
import "modules/wallpaper"
import "services"

// Wiring smoke for tests/menus-ui.sh: the real WallCtl (the picker minus its layer-shell window) is opened through Ui.open
// on the offscreen platform. WALLPAPER_DIR points at generated images, so the scan, the Dispatcher
// round trip, the palette request and the model all run for real. Nothing is applied.
ShellRoot {
    id: sc
    property int step: 0

    FloatingWindow { implicitWidth: 100; implicitHeight: 100; WallCtl { id: wp } }

    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            sc.step++
            if (sc.step === 1) Ui.open = "wallpaper"
            else if (sc.step === 4) {
                console.log("SMOKE open=" + Ui.open + " wanted=" + wp.wanted + " items=" + wp.items.length + " folder=" + wp.folder.exists); console.log("SMOKE wallpaper mode=" + wp.m.mode + " tiles=" + wp.m.tiles.length + " folder=" + wp.m.folder.name + " sel=" + (wp.m.selName !== ""))
                Ui.open = ""
            }
            else if (sc.step === 5) Qt.quit()
        }
    }
}
