import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/barpop/js/Salah.js" as Salah
import "modules/barpop/js/Waiting.js" as Waiting
import "modules/barpop/js/Agents.js" as Agents
import "modules/barpop/js/Tray.js" as Tray
import "modules/calendar/js/Cal.js" as Cal

// Test scene for tests/barpop-ui.sh: quickshell -p <root> on Qt's offscreen platform. It
// renders the REAL panel bodies of the five bar popups inside a card like Popout's, one
// case after another, logs `PROBE <tag> {json}` (every objectName'd item's box and text)
// and saves a PNG per case. PANEL = salah | waiting | agent | tray | calendar.
ShellRoot {
    id: sc

    readonly property string panel: Quickshell.env("PANEL") || "salah"
    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string fixDir: Quickshell.env("FIXDIR")
    readonly property string calFix: Quickshell.env("CALFIX")

    function read(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    function json(path) { return JSON.parse(read(path)) }

    function at(iso) { var p = iso.split(/[-T:]/); return new Date(+p[0], +p[1] - 1, +p[2], +p[3], +p[4], 0) }
    readonly property var days: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // ---- cases --------------------------------------------------------------------
    function cases() {
        var out = []
        if (panel === "salah") {
            var conf = read(fixDir + "/prayer-times.conf")
            var mk = function (tag, iso, confText) {
                var d = at(iso)
                out.push({ tag: tag, file: "modules/barpop/SalahPanel.qml", w: 328,
                           props: { model: Salah.build(Salah.parseConf(confText || conf), d),
                                    dateText: days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear() } })
            }
            mk("normal", "2026-11-03T14:37")
            mk("soon", "2026-11-03T15:31")
            mk("now", "2026-11-03T15:58")
            mk("friday", "2026-11-06T10:35", conf.replace("2026-11-03", "2026-11-06"))
            mk("stale", "2026-11-09T14:37")
            out.push({ tag: "nofile", file: "modules/barpop/SalahPanel.qml", w: 328, props: { model: Salah.build(Salah.parseConf(""), at("2026-11-03T14:37")), dateText: "Tue 3 Nov 2026" } })
        } else if (panel === "waiting") {
            var att = json(fixDir + "/attention.json").items
            var noAlert = att.filter(function (i) { return i.kind !== "alert" })
            var many = noAlert.slice()
            for (var k = 0; k < 4; k++) many.push({ id: "x" + k, kind: "mail", title: "Extra " + k, ref: "x", src: "mail", url: "", urgency: "active", waiting: true, ageSec: 600 + k * 60, actor: "Z", jump: null })
            var wk = function (tag, items, opts) {
                out.push({ tag: tag, file: "modules/barpop/WaitingPanel.qml", w: 328, props: { model: Waiting.build(items, opts) } })
            }
            wk("default", noAlert, { filter: "all", focusFirst: true, prayerIn: 12 })
            wk("problem", att, { filter: "all", focusFirst: true })
            wk("empty", [], { filter: "all" })
            wk("stale", noAlert, { filter: "all", focusFirst: true, stale: true })
            wk("chat", noAlert, { filter: "chat", focusFirst: true })
            wk("overflow", many, { filter: "all", focusId: "e1" })
        } else if (panel === "agent") {
            var items = json(fixDir + "/attention.json").items
            var doc = json(fixDir + "/agents.json")
            var ag = function (tag, its, d, o) { out.push({ tag: tag, file: "modules/barpop/AgentPanel.qml", w: 388, props: { model: Agents.build(its, d, o) } }) }
            ag("needs", items, doc, {})
            ag("second", items, doc, { focusId: "h2" })
            ag("quiet", [], doc, {})
            ag("empty", [], null, {})
        } else if (panel === "tray") {
            var t = json(fixDir + "/tray.json")
            var tp = function (tag, apps, q, extra) {
                var p = { model: Tray.build(apps, q) }
                for (var k in extra) p[k] = extra[k]
                out.push({ tag: tag, file: "modules/barpop/TrayPanel.qml", w: 328, props: p })
            }
            tp("list", t.apps, "", { selId: "vpn" })
            tp("filtered", t.apps, "sy", {})
            tp("drill", t.apps, "", { drill: t.drill })
            tp("empty", [], "", {})
        } else if (panel === "calendar") {
            var base = json(calFix)
            var conf2 = read(fixDir + "/prayer-times.conf")
            var cm = function (tag, iso, o) {
                o = o || {}
                var d = at(iso)
                var doc2 = o.noDoc ? null : JSON.parse(JSON.stringify(base))
                if (doc2) {
                    doc2.ts = o.staleAt ? at(o.staleAt).getTime() / 1000 : d.getTime() / 1000 - 60
                    if (o.noEvents) doc2.events = []
                }
                var cf = o.conf || conf2
                var model = Cal.build(doc2, Salah.parseConf(cf), d, { openId: o.openId || "", month: o.month })
                out.push({ tag: tag, file: "modules/calendar/CalendarPanel.qml", w: 368, props: { model: model, view: o.view || "day" } })
            }
            cm("default", "2026-11-03T09:18", { openId: "e2" })
            cm("soon", "2026-11-03T09:24")
            cm("meeting", "2026-11-03T09:42")
            cm("prayer", "2026-11-03T15:47")
            cm("stale", "2026-11-03T14:48", { staleAt: "2026-11-03T14:02" })
            cm("freeday", "2026-11-03T10:20", { noEvents: true })
            cm("month", "2026-11-03T09:18", { view: "month" })
            cm("unverified", "2026-11-03T14:48", { conf: conf2.replace("2026-11-03", "2026-10-29") })
        }
        return out
    }

    // ---- measuring ----------------------------------------------------------------
    property var caseList: cases()
    property int idx: 0

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function measure() {
        var m = { names: {}, card: { w: card.width, h: card.height }, panel: { w: ld.item ? ld.item.width : 0, h: ld.item ? ld.item.implicitHeight : 0 } }
        walk(stage, function (it) {
            if (!it.objectName) return
            var p = it.mapToItem(stage, 0, 0)
            var r = { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height), visible: it.visible && it.opacity > 0 }
            if (it.text !== undefined) r.text = String(it.text)
            if (it.paintedPx !== undefined) r.px = it.paintedPx; if (it.box !== undefined) r.box = it.box
            if (!m.names[it.objectName]) m.names[it.objectName] = []
            m.names[it.objectName].push(r)
        })
        return m
    }

    function show(c) {
        ld.active = false
        ld.source = c.file
        ld.active = true
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

            Surface {
                id: card
                x: 20
                y: 20
                width: (sc.caseList.length > 0 ? sc.caseList[Math.min(sc.idx, sc.caseList.length - 1)].w : 328) + 32
                height: (ld.item ? ld.item.implicitHeight : 0) + 32
                Loader {
                    id: ld
                    x: 16
                    y: 16
                    active: false
                    onLoaded: {
                        var c = sc.caseList[sc.idx]
                        for (var k in c.props) item[k] = c.props[k]
                        item.width = c.w
                    }
                }
            }
        }
    }

    function next() {
        if (sc.idx >= sc.caseList.length) { Qt.quit(); return }
        sc.show(sc.caseList[sc.idx])
        settle.restart()
    }

    Timer {
        id: settle
        interval: 350
        onTriggered: {
            var c = sc.caseList[sc.idx]
            console.log("PROBE " + c.tag + " " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outDir + "/" + sc.panel + "-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
