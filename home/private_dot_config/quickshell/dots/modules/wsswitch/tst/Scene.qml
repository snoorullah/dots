import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/wsswitch"
import "modules/wsswitch/js/Model.js" as M

// Test scene for tests/wsswitch-ui.sh: quickshell -p <root> on Qt's offscreen platform. It
// renders the REAL WsPanel from the fixture, one case after another, logs
// `PROBE <tag> {json}` (every objectName'd item's box and text) and saves a PNG per case.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string fixPath: Quickshell.env("FIXTURE")

    function read(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    readonly property var fix: JSON.parse(read(fixPath))

    // case: { tag, st, strip, edit(fixture) }
    function cases() {
        var dev = { focus: "Dev", sel: "0xd2" }
        function c(tag, st, o) { return { tag: tag, st: st, strip: !!(o && o.strip === false ? false : true), edit: o && o.edit } }
        var moved = function (f) { f.windows.forEach(function (w) { if (w.addr === "0xf2") w.wsId = 3 }) }
        var list = [
            c("pop-default", dev),
            c("pop-hover", { hover: "Web" }),
            c("pop-move", { focus: "Dev", sel: "0xf2", moved: "0xf2", toast: "Moved Terminal to Dev." }, { edit: moved }),
            c("pop-empty", { focus: "Notes" }),
            c("pop-needs", { focus: "Agents", sel: "0xa1" }),
            c("pop-salah", { focus: "Dev", salah: true }),
            c("pop-error", { focus: "Dev", sel: "0xd3", err: "0xd3" }),
            c("pop-locked", { locked: true }),
            c("full-default", { variant: "a", mode: "full", focus: "Dev", sel: "0xd2" }),
            c("full-filter", { variant: "a", mode: "full", query: "term" }),
            c("full-nomatch", { variant: "a", mode: "full", query: "zzz" }),
            c("grid-default", { variant: "b", focus: "Dev", sel: "0xd2" }),
            c("grid-move", { variant: "b", focus: "Dev", sel: "0xf2", moved: "0xf2", toast: "Moved Terminal to Dev." }, { edit: moved }),
            c("grid-needs", { variant: "b", focus: "Agents", sel: "0xa1" }),
            c("grid-filter", { variant: "b", query: "term" }),
            c("grid-salah", { variant: "b", salah: true }),
            c("map-default", { variant: "c", focus: "Dev", sel: "0xd2" }),
            c("map-needs", { variant: "c", focus: "Agents", sel: "0xa1" }),
            c("map-empty", { variant: "c", focus: "Notes" }),
            c("map-comms", { variant: "c", focus: "Comms", wsIdx: 1 }),
            c("map-filter", { variant: "c", focus: "Dev", query: "term" })
        ]
        return list
    }

    property var caseList: cases()
    property int idx: 0

    function mk(c) {
        var f = JSON.parse(JSON.stringify(fix))
        if (c.edit) c.edit(f)
        f.st = c.st
        return M.build(f)
    }

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function measure() {
        var m = { names: {}, card: { w: panel.width, h: panel.height } }
        walk(stage, function (it) {
            if (!it.objectName) return
            var p = it.mapToItem(stage, 0, 0)
            var vis = it.visible && it.opacity > 0
            var q = it.parent
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
        implicitWidth: 1000
        implicitHeight: 640
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            WsPanel {
                id: panel
                x: 60
                y: 40
                readOnly: true
                notchX: 120
                strip: sc.caseList[Math.min(sc.idx, sc.caseList.length - 1)].strip
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
                res.saveToFile(sc.outDir + "/wsswitch-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
