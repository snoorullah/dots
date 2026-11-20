import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/launcher/providers" as Prov   // qualified: the real Math provider type would shadow the JS Math object

// Test scene for tests/launcher-modes.sh: quickshell -p <root> on Qt's offscreen platform. For every
// case in $CASES it creates the REAL provider, points it at the case's wrapper bin dir (real Python
// helper, fixture env), replays the steps, draws the result with the test Frame, logs
// `PROBE <tag> {json}` and saves a PNG. No compositor, no network.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    function read(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    readonly property var cases: JSON.parse(read(Quickshell.env("CASES")))
    readonly property var names: ({ files: "Files", dict: "Dictionary", fonts: "Fonts + icons", windows: "Windows", snippets: "Snippets",
                                    emoji: "Emoji", hosts: "SSH hosts", kube: "Kube" })

    property int idx: 0
    property var cur: null            // case
    property var prov: null           // provider instance
    property string toastText: ""
    property var confirmSpec: null
    property int selIndex: 0
    property var lastAct: null
    property var queue: []
    property double readyAt: 0
    property var events: []

    Component { id: cFiles; Prov.Files {} }
    Component { id: cDict; Prov.Dictionary {} }
    Component { id: cFonts; Prov.Fonts {} }
    Component { id: cWindows; Prov.Windows {} }
    Component { id: cSnippets; Prov.Snippets {} }
    Component { id: cEmoji; Prov.Emoji {} }
    Component { id: cHosts; Prov.Hosts {} }
    Component { id: cKube; Prov.Kube {} }
    readonly property var comps: ({ files: cFiles, dict: cDict, fonts: cFonts, windows: cWindows, snippets: cSnippets, emoji: cEmoji, hosts: cHosts, kube: cKube })

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function measure() {
        var m = { names: {}, card: { w: frame.width, h: frame.height }, meta: {} }
        walk(frame, function (it) {
            if (!it.objectName) return
            var p = it.mapToItem(frame, 0, 0)
            var vis = it.visible && it.opacity > 0 && it.width > 0 && it.height > 0
            var r = { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height), visible: vis }
            if (it.text !== undefined) r.text = String(it.text)
            if (it.plain !== undefined) r.plain = String(it.plain)
            if (!m.names[it.objectName]) m.names[it.objectName] = []
            m.names[it.objectName].push(r)
        })
        var p = sc.prov
        m.meta = { rows: p.rows.length, keys: p.rows.map(function (r) { return r.key }), error: p.error, hint: p.hint, busy: p.busy,
                   toast: sc.toastText, confirm: sc.confirmSpec, sel: sc.selIndex, events: sc.events,
                   banner: p.banner !== undefined && p.banner ? p.banner.title : "",
                   tray: p.tray !== undefined ? p.tray.length : -1, adding: p.adding === true, sensitiveHold: p.sensitiveHold === true,
                   view: p.view !== undefined ? p.view : "", kubeState: p.kubeState !== undefined ? p.kubeState : "",
                   note: p.note !== undefined ? p.note : "", mismatch: p.mismatch === true,
                   actions: p.rows.length ? p.rows[Math.min(sc.selIndex, p.rows.length - 1)].actions.map(function (a) { return a.label + (a.disabled ? "!" : "") }) : [],
                   pendingKey: p.pendingKey !== undefined ? p.pendingKey : "" }
        return m
    }

    function indexOfKey(k) {
        for (var i = 0; i < prov.rows.length; i++) if (prov.rows[i].key === k) return i
        return -1
    }

    function startCase() {
        if (sc.idx >= sc.cases.length) { Qt.quit(); return }
        var c = sc.cases[sc.idx]
        sc.cur = c
        sc.toastText = (c.frame && c.frame.toast) || ""
        sc.confirmSpec = null
        sc.lastAct = null
        sc.events = []
        if (sc.prov) { sc.prov.destroy(); sc.prov = null }
        var p = sc.comps[c.mode].createObject(sc, { bin: c.bin })
        var props = (c.frame && c.frame.props) || {}
        for (var k in props) p[k] = props[k]
        p.done.connect(function (close, toast) { sc.toastText = toast; sc.events = sc.events.concat(["done:" + close + ":" + toast]) })
        p.confirmRequested.connect(function (spec) { sc.confirmSpec = spec; sc.events = sc.events.concat(["confirm"]) })
        sc.prov = p
        sc.selIndex = c.sel || 0
        sc.queue = [{ op: "query", text: c.query }].concat(c.steps || [])
        sc.readyAt = Date.now() + 250
        pump.restart()
    }

    function doStep(s) {
        var p = sc.prov
        if (s.op === "query") { p.query(s.text); sc.readyAt = Date.now() + 260 }
        else if (s.op === "select") { var i = sc.indexOf(s.key); sc.selIndex = i >= 0 ? i : 0; sc.readyAt = Date.now() + 30 }
        else if (s.op === "activate") {
            var row = s.key !== undefined ? sc.indexOf(s.key) : s.row
            sc.lastAct = { row: row, action: s.action }
            p.activate(row, s.action)
            sc.readyAt = Date.now() + 300
        }
        else if (s.op === "confirm") { sc.confirmSpec = null; p.activate(sc.lastAct.row, sc.lastAct.action); sc.readyAt = Date.now() + 300 }
        else if (s.op === "fill") { p.fill(s.row, s.name, s.value); sc.readyAt = Date.now() + 250 }
        else if (s.op === "beginAdd") { p.beginAdd(); sc.readyAt = Date.now() + 250 }
        else if (s.op === "toast") { sc.toastText = s.text; sc.readyAt = Date.now() + 30 }
    }
    function indexOf(k) { return indexOfKey(k) }

    Timer {
        id: pump
        interval: 60
        repeat: true
        onTriggered: {
            if (Date.now() < sc.readyAt || sc.prov.busy) return
            if (sc.queue.length > 0) {
                var s = sc.queue[0]
                sc.queue = sc.queue.slice(1)
                sc.doStep(s)
                return
            }
            pump.stop()
            settle.restart()
        }
    }

    FloatingWindow {
        id: win
        implicitWidth: 1040
        implicitHeight: 660
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            Frame {
                id: frame
                x: 20; y: 20
                p: sc.prov
                prefix: sc.cur ? ((sc.cur.frame && sc.cur.frame.prefix) || "") : ""
                query: sc.cur ? sc.cur.query : ""
                sel: sc.selIndex
                toast: sc.toastText
                confirm: sc.confirmSpec
                closed: sc.cur && sc.cur.frame && sc.cur.frame.closed ? sc.cur.frame.closed : null
                actionsOpen: !!(sc.cur && sc.cur.frame && sc.cur.frame.actionsOpen)
                layoutKind: sc.cur && sc.cur.frame && sc.cur.frame.layout ? sc.cur.frame.layout : "list"
                modeName: sc.cur ? sc.names[sc.cur.mode] : ""
            }
        }
    }

    Timer {
        id: settle
        interval: 500
        onTriggered: {
            var c = sc.cur
            console.log("PROBE " + c.tag + " " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outDir + "/launcher-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.startCase()
            })
        }
    }

    Component.onCompleted: Qt.callLater(startCase)
}
