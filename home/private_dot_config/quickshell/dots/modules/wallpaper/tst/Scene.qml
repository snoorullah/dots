import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/wallpaper"
import "modules/wallpaper/js/Wall.js" as W

// Test scene for tests/menus-ui.sh: quickshell -p <root> on Qt's offscreen platform. It renders
// the REAL WallPanel from the board's states and 16 generated wallpapers, logs
// `PROBE <tag> {json}` and saves a PNG per state.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string wallDir: Quickshell.env("WALL_DIR")

    function items(n, broken) {
        var out = []
        for (var i = 1; i <= n; i++) {
            var nn = i < 10 ? "0" + i : String(i)
            var src = ((i - 1) % 16 + 1) < 10 ? "0" + ((i - 1) % 16 + 1) : String((i - 1) % 16 + 1)
            out.push({ name: "wallpaper-" + nn, path: sc.wallDir + "/wallpaper-" + src + ".png", rel: "wallpaper-" + nn + ".png",
                       ok: broken.indexOf(i) < 0, fav: i === 2 || i === 7 })
        }
        return out
    }
    function pal(i, surface, text, ratio, tuned, tunedText, tags) {
        var nn = i < 10 ? "0" + i : String(i)
        var o = {}
        o[sc.wallDir + "/wallpaper-" + nn + ".png"] = { surface: surface, text: text, ratio: ratio, tuned: tuned, tunedText: tunedText, tags: tags }
        return o
    }
    function pals() {
        var out = {}
        var add = function (o) { for (var k in o) out[k] = o[k] }
        add(pal(1, "#10202a", "#e7edf0", 12.5, false, "#e7edf0", ["dark", "calm", "cool"]))
        add(pal(2, "#241a30", "#ece4f2", 12.0, false, "#ece4f2", ["dark", "calm", "cool"]))
        add(pal(3, "#0f1a1f", "#e7edf0", 14.1, false, "#e7edf0", ["dark", "calm", "cool"]))
        add(pal(4, "#2b1d14", "#efe2d6", 12.2, false, "#efe2d6", ["dark", "calm", "warm"]))
        add(pal(6, "#141436", "#e4e4f0", 12.9, false, "#e4e4f0", ["dark", "vivid", "cool"]))
        add(pal(8, "#c7d3d8", "#5f6f76", 2.6, true, "#1a2a31", ["light", "calm", "cool"]))
        return out
    }
    readonly property string p3: sc.wallDir + "/wallpaper-03.png"
    readonly property string p6: sc.wallDir + "/wallpaper-06.png"
    readonly property string p8: sc.wallDir + "/wallpaper-08.png"
    readonly property var folder: ({ name: "Wallpapers", count: 16, skipped: 0, exists: true })

    // case: { tag, st, o: build input overrides }
    function cases() {
        var c = function (tag, st, o) { return { tag: tag, st: st || {}, o: o || {} } }
        var base = { items: sc.items(16, []), pals: sc.pals(), folder: sc.folder, cur: sc.p3, monitors: ["DP-1", "HDMI-A-1"], lock: true }
        var ov = function (extra) { var r = {}; for (var k in base) r[k] = base[k]; for (var e in extra) r[e] = extra[e]; return r }
        return [
            c("default", {}, ov({})),
            c("preview", { sel: sc.p6 }, ov({})),
            c("committed", { sel: sc.p6, toast: true }, ov({ cur: sc.p6 })),
            c("empty", {}, ov({ items: [], folder: { name: "", count: 0, exists: false }, cur: "" })),
            c("loading", { loading: true }, ov({})),
            c("large", { query: "wallpaper-1" }, ov({ items: sc.items(48, []), folder: { name: "Wallpapers", count: 1284, skipped: 0, exists: true } })),
            c("tuned", { sel: sc.p8 }, ov({})),
            c("untuned", { sel: sc.p8, untuned: true }, ov({})),
            c("missing", {}, ov({ items: sc.items(16, [5, 12]), folder: { name: "Wallpapers", count: 16, skipped: 2, exists: true } })),
            c("shuffle", {}, ov({ shuffle: true, nextAt: "15:00" })),
            c("paused", {}, ov({ shuffle: true, focusMode: true })),
            c("monitors", { sel: sc.p6, monitor: 1 }, ov({})),
            c("modepal", { sel: sc.p6, extract: 2 }, ov({})),
            c("salah", { sel: sc.p6 }, ov({ salah: true })),
            c("ai", {}, ov({ suggest: sc.wallDir + "/wallpaper-10.png" })),
            c("keys", { keys: true }, ov({}))
        ]
    }

    property var caseList: cases()
    property int idx: 0

    function mk(cs) {
        var st = W.initial()
        for (var k in cs.st) st[k] = cs.st[k]
        var inp = {}
        for (var e in cs.o) inp[e] = cs.o[e]
        inp.st = st
        return W.build(inp)
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
        implicitWidth: 1040
        implicitHeight: 700
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            WallPanel {
                id: panel
                x: 40
                y: 30
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
        interval: 900                 // images decode asynchronously
        onTriggered: {
            var c = sc.caseList[sc.idx]
            console.log("PROBE " + c.tag + " " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outDir + "/wallpaper-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
