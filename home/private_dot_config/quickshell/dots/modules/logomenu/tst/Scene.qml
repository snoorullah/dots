import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/logomenu"
import "modules/logomenu/js/Menu.js" as M

// Test scene for tests/menus-ui.sh: quickshell -p <root> on Qt's offscreen platform. It renders
// the REAL LogoPanel in every state of the board, logs `PROBE <tag> {json}` and saves a PNG each.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"

    function cases() {
        var ok = { state: "ok", fix: "", up: "2d 4h" }
        var c = function (tag, st, o) { return { tag: tag, st: st || {}, o: o || {} } }
        return [
            c("healthy", {}, { health: ok }),
            c("focus-note", { focusNote: true }, { health: ok, mode: "Focus" }),
            c("degraded", {}, { health: { state: "degraded", fix: "reload", up: "2d 4h" } }),
            c("degraded-hypr", { ai: true }, { health: { state: "degraded", fix: "hypr", up: "5h 1m" }, hint: "Hint: Hyprland stopped answering. Reload it, then check the log." }),
            c("safe", {}, { health: { state: "safe", fix: "", up: "" } }),
            c("filter", { query: "re" }, { health: ok }),
            c("filter-none", { query: "zz" }, { health: ok }),
            c("logout", { sel: "logout", logout: 3 }, { health: ok }),
            c("logout-2", { sel: "logout", logout: 2 }, { health: ok }),
            c("salah", {}, { health: ok, salah: { on: true, ends: "13:42", next: "Asr 16:05" } }),
            c("selected", { sel: "scratchpad" }, { health: ok })
        ]
    }

    property var caseList: cases()
    property int idx: 0

    function mk(cs) {
        var st = { sel: "", query: "", logout: 0, ai: false, focusNote: false, focusSeen: false, toast: "" }
        for (var k in cs.st) st[k] = cs.st[k]
        var inp = { health: { state: "ok", fix: "", up: "" }, mode: "Heavy work", salah: { on: false } }
        for (var e in cs.o) inp[e] = cs.o[e]
        inp.st = st
        return M.build(inp)
    }

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function measure() {
        var m = { names: {}, card: { w: panel.width, h: panel.height, visible: panel.visible } }
        walk(stage, function (it) {
            if (!it.objectName) return
            var p = it.mapToItem(stage, 0, 0)
            var vis = it.visible && it.opacity > 0
            var q = it.parent
            while (vis && q && q !== stage) { vis = vis && q.visible; q = q.parent }
            var r = { x: Math.round(p.x - panel.x), y: Math.round(p.y - panel.y), w: Math.round(it.width), h: Math.round(it.height), visible: vis }
            if (it.text !== undefined) r.text = String(it.text)
            if (it.paintedPx !== undefined) r.px = it.paintedPx; if (it.box !== undefined) r.box = it.box
            if (!m.names[it.objectName]) m.names[it.objectName] = []
            m.names[it.objectName].push(r)
        })
        return m
    }

    FloatingWindow {
        id: win
        implicitWidth: 520
        implicitHeight: 780
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            LogoPanel {
                id: panel
                x: 24
                y: 20
                readOnly: true
                m: sc.mk(sc.caseList[Math.min(sc.idx, sc.caseList.length - 1)])
            }
        }
    }

    function next() {
        if (sc.idx >= sc.caseList.length) { Qt.quit(); return }
        settle.restart()
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: {
            var c = sc.caseList[sc.idx]
            console.log("PROBE " + c.tag + " " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outDir + "/logomenu-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
