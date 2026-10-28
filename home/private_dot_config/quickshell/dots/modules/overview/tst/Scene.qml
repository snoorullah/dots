import QtQuick
import Quickshell
import qs.modules.overview
import qs.modules.overview.parts

// Test scene for tests/overview-ui.sh, run with `quickshell -p <root>` on the
// offscreen Qt platform. It renders the REAL overview components next to mock
// neighbours, logs `PROBE <tag> {json}` measurements, saves PNGs of the stage and
// quits. SCENARIO picks the stage: pill | card | panel. No compositor is needed.
ShellRoot {
    id: sc

    readonly property string scenario: Quickshell.env("SCENARIO") || "pill"
    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string page: Quickshell.env("PAGE") || "today"
    readonly property bool live: Quickshell.env("LIVE") === "1"
    readonly property string clicks: Quickshell.env("CLICK_NAMES") || ""
    readonly property bool lampTest: Quickshell.env("LAMP") === "1"

    property var shots: []

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
        if (item.contentItem && kids.indexOf(item.contentItem) < 0) walk(item.contentItem, fn)
    }

    function find(name) {
        var out = []
        walk(stage, function (it) { if (it.objectName === name) out.push(it) })
        return out
    }

    function box(it) {
        if (!it) return null
        var p = it.mapToItem(stage, 0, 0)
        return { x: p.x, y: p.y, w: it.width, h: it.height, visible: it.visible }
    }

    function measure() {
        var m = { scenario: sc.scenario, page: sc.page }
        var pill = find("overviewPill")[0]
        if (pill) {
            m.pill = box(pill)
            m.pill.implicitWidth = pill.implicitWidth
            m.pill.implicitHeight = pill.implicitHeight
            m.pill.cx = m.pill.x + pill.width / 2
            m.slabW = slab.width
            m.leftX = find("mockLeft")[0].mapToItem(stage, 0, 0).x
            m.rightX = find("mockRight")[0].mapToItem(stage, 0, 0).x
            m.chips = {}
            var names = ["focusChip", "failedChip", "waitingChip", "staleChip"]
            for (var i = 0; i < names.length; i++) {
                var c = find(names[i])[0]
                m.chips[names[i]] = c ? { visible: c.visible, w: c.width } : null
            }
        }
        var card = find("overviewCard")[0]
        if (card) {
            var wrap = find("cardWrap")[0], notch = find("notch")[0]
            m.card = { w: wrap.width, h: wrap.height, radius: wrap.radius, x: wrap.mapToItem(stage, 0, 0).x, y: wrap.mapToItem(stage, 0, 0).y }
            var np = notch.mapToItem(stage, notch.width / 2, 0)
            m.notchCx = np.x
            m.notchW = notch.width
            m.notchH = notch.height
            m.rows = find("attnRow").length
            var foot = find("cardFooter")[0], fade = find("cardFade")[0], sc2 = find("cardScroll")[0]
            m.foot = { x: foot.mapToItem(stage, 0, 0).x, y: foot.mapToItem(stage, 0, 0).y, w: foot.width, h: foot.height, visible: foot.visible,
                       buttons: find("openPanel").length + find("focusToggle").length }
            m.fadeVisible = fade.visible
            m.scroll = { y: sc2.mapToItem(stage, 0, 0).y, h: sc2.height, contentH: sc2.contentHeight }
            m.hasEmpty = find("empty").length
        }
        var cells = find("cell")
        if (cells.length > 0) {
            var cs = cells[0].width
            var xs = {}, ys = {}, x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, ok = true, pts = []
            for (var k = 0; k < cells.length; k++) {
                var b = cells[k].mapToItem(stage, 0, 0)
                if (cells[k].width !== cs || cells[k].height !== cs) ok = false
                xs[b.x] = 1; ys[b.y] = 1
                x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y)
                x1 = Math.max(x1, b.x + cs); y1 = Math.max(y1, b.y + cs)
                pts.push([Math.round(b.x + cs / 2), Math.round(b.y + cs / 2)])
            }
            var xl = Object.keys(xs).map(Number).sort(function (a, b) { return a - b })
            var yl = Object.keys(ys).map(Number).sort(function (a, b) { return a - b })
            m.heat = { count: cells.length, sizeOk: ok, x: x0, y: y0, w: x1 - x0, h: y1 - y0,
                       cell: cs, gapX: xl.length > 1 ? xl[1] - xl[0] - cs : -1, gapY: yl.length > 1 ? yl[1] - yl[0] - cs : -1,
                       cols: xl.length, rows: yl.length, centres: pts }
        }
        var hmv = find("heatmap")[0]
        if (hmv) {
            var hb = hmv.mapToItem(stage, 0, 0)
            var wl = find("weekdayLabel"), ml = find("monthLabel")
            m.heatBox = { x: hb.x, y: hb.y, w: hmv.width, h: hmv.height }
            m.heatLabels = { weekdays: wl.map(function (t) { return t.text }), months: ml.map(function (t) { return t.text }) }
        }
        m.tiles = find("statTile").map(function (t) {
            var tp = t.mapToItem(stage, 0, 0)
            return { label: t.label, value: t.value, note: t.note, x: tp.x, y: tp.y, w: t.width, h: t.height }
        })
        m.look = { aPressed: Look.aPressed, aHover: Look.aHover }
        var panelItem = find("overviewPanel")[0]
        if (panelItem) m.panelBox = box(panelItem)
        var ring = find("ring")
        if (ring.length > 0) {
            var r = ring[ring.length - 1]
            var rb = r.mapToItem(stage, 0, 0)
            m.ring = { cx: rb.x + r.width / 2, cy: rb.y + r.height / 2, d: r.diameter, stroke: r.stroke, angle: r.angle }
        }
        m.stale = find("staleMark").filter(function (s) { return s.visible && s.width > 0 }).length
        m.dim = Feed.dim
        return m
    }

    function shoot(tag, last) {
        var m = measure()
        console.log("PROBE " + tag + " " + JSON.stringify(m))
        stage.grabToImage(function (res) {
            res.saveToFile(sc.outDir + "/" + sc.scenario + "-" + tag + ".png")
            console.log("SHOT " + tag)
            if (last) Qt.quit()
        })
    }

    Component.onCompleted: {
        Feed.selectedId = Quickshell.env("SELECT") || ""
        if (lampTest) Feed.lampFor(20000)
    }

    function pressButton(name) {
        var b = find(name)[0]
        if (b) b.clicked()
        else console.log("NOBUTTON " + name)
    }

    FloatingWindow {
        implicitWidth: 980
        implicitHeight: 720
        color: "#1a1a2e"

        Item {
            id: stage
            anchors.fill: parent

            // mock bar slab: grows with its content, like the real right slab
            Rectangle {
                id: slab
                visible: sc.scenario !== "panel"
                x: 40
                y: 0
                height: Look.barHeight
                width: row.implicitWidth + 20
                color: Look.withAlpha(Look.surface, 0.78)
                Row {
                    id: row
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Rectangle { objectName: "mockLeft"; width: 40; height: 14; radius: 4; color: "#5a5d70" }
                    OverviewPill { id: pill; screenName: "HL-1" }
                    Rectangle { objectName: "mockRight"; width: 40; height: 14; radius: 4; color: "#5a5d70" }
                }
            }

            Loader {
                active: sc.scenario === "card"
                sourceComponent: OverviewCard {
                    animate: false
                    shown: true
                    notchX: Feed.anchorX - x
                    x: Math.max(8, Feed.anchorX - Look.cardWidth / 2)
                    y: Feed.anchorBottom
                }
            }

            Loader {
                active: sc.scenario === "heatcompact"
                sourceComponent: Rectangle {
                    x: 10
                    y: 10
                    width: 255
                    height: 115
                    color: Look.surface
                    Heatmap {
                        x: 10
                        y: 10
                        days: Feed.heatDoc ? Feed.heatDoc.days : []
                    }
                }
            }

            Loader {
                active: sc.scenario === "panel"
                sourceComponent: OverviewPanel {
                    animate: false
                    shown: true
                    page: sc.page
                    x: 20
                    y: 20
                }
            }
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            if (sc.clicks !== "") {
                sc.clicks.split(",").forEach(function (n) { sc.pressButton(n) })
                console.log("CLICKED")
                quitT.start()
            } else if (sc.live) {
                sc.shoot("before", false)
                liveT.start()
            } else {
                sc.shoot("main", true)
            }
        }
    }
    Timer { id: liveT; interval: 2600; onTriggered: sc.shoot("after", true) }
    Timer { id: quitT; interval: 800; onTriggered: Qt.quit() }
}
