import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/winswitch"
import "modules/winswitch/js/Switch.js" as S

// Test scene for tests/menus-ui.sh: quickshell -p <root> on Qt's offscreen platform. It renders
// the REAL WinPanel from the fixture, one board state after another, logs `PROBE <tag> {json}`
// (every objectName'd item's box and text) and saves a PNG per state.
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

    function many() {
        var cls = ["code", "foot", "zen-beta", "obsidian", "org.gnome.Nautilus", "slack", "thunderbird"]
        var out = []
        for (var i = 0; i < 24; i++)
            out.push({ addr: "0x" + (200 + i).toString(16), cls: cls[i % 7], title: "Window title number " + (i + 1),
                       wsId: 1 + (i % 6), focusHist: i, hidden: i >= 22 })
        return out
    }

    // state: { tag, st, extra(build input), mru, windows }
    function cases() {
        var m1 = ["0xa2", "0xa3", "0xa6", "0xa1"]
        var c = function (tag, st, o) { return { tag: tag, st: st || {}, o: o || {} } }
        return [
            c("cycle", { sel: 1 }, { mru: m1 }),
            c("cycle-wrap", { sel: 9 }, { mru: m1 }),
            c("group-closed", { scope: "all", sel: 0 }, { mru: ["0xa3"] }),
            c("group-open", { scope: "all", group: "0xa3", sel: 1 }, { mru: ["0xa3"] }),
            c("filter", { query: "notes", sel: 0 }, { mru: m1 }),
            c("nomatch", { query: "zzz", sel: 0 }, { mru: m1 }),
            c("single", {}, { windows: [{ addr: "0x1", cls: "foot", title: "Terminal", wsId: 3 }], activeWs: 3 }),
            c("many", { sel: 11, scope: "all" }, { windows: many(), activeWs: 1 }),
            c("locked", { sel: 1 }, { mru: m1, locked: true }),
            c("unlock", { sel: 1, scope: "all" }, { mru: m1, redacted: true }),
            c("ai-thinking", { query: "which window was I using for the spec review?", sel: 0, scope: "all", ai: { phase: "thinking", ids: [] } }, { mru: m1 }),
            c("ai-done", { query: "which window was I using for the spec review?", sel: 0, scope: "all", ai: { phase: "done", ids: ["0xa6", "0xa1", "0xa3"] } }, { mru: m1 }),
            c("ai-fallback", { query: "which window was I using for the spec review?", sel: 0, scope: "all", ai: { phase: "fallback", ids: ["0xa6", "0xa1"] } }, { mru: m1 }),
            c("confirm", { sel: 0, scope: "all", confirm: "0xa4" }, { mru: ["0xa4"] }),
            c("undo", { sel: 1, scope: "all", undo: { addr: "0xa1", title: "switcher.qml - dots" }, closed: ["0xa1"] }, { mru: m1 }),
            c("msg", { sel: 1, msg: "Pinned to TICKET-123. Stored locally only." }, { mru: m1 }),
            c("list", { sel: 2, layout: "list", scope: "all" }, { mru: m1 }),
            c("grid", { sel: 2, layout: "grid", scope: "all" }, { mru: m1 })
        ]
    }

    property var caseList: cases()
    property int idx: 0

    function mk(cs) {
        var st = S.initial()
        for (var k in cs.st) st[k] = cs.st[k]
        var inp = { windows: sc.fix.windows, activeWs: sc.fix.activeWs, activeAddr: sc.fix.activeAddr, pins: sc.fix.pins, mru: [], st: st }
        for (var e in cs.o) inp[e] = cs.o[e]
        return S.build(inp)
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
        implicitWidth: 1000
        implicitHeight: 640
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            WinPanel {
                id: panel
                x: Math.round((parent.width - width) / 2)
                y: 40
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
                res.saveToFile(sc.outDir + "/winswitch-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
