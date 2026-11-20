import QtQuick
import Quickshell
import "modules/theme"
import "modules/common"
import "modules/barpop"
import "modules/windows"
import "modules/windows/js/Presets.js" as P
import "modules/windows/js/Groups.js" as G
import "modules/windows/js/Restore.js" as R
import "modules/windows/js/Scratch.js" as S

// Test scene for tests/windows-ui.sh: quickshell -p <root> on Qt's offscreen platform. It renders
// the REAL TilingAssistant, TabsBar, RestorePrompt and ScratchPanel from the fixtures, one case
// after another, logs `PROBE <tag> {json}` (every objectName'd item's box and text) and saves a
// PNG per case. The host windows (WindowsPopout, TabsOverlay) are only linted: they need Hyprland.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    function read(path) {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + path, false)
        x.send()
        return x.responseText
    }
    readonly property var status: JSON.parse(read(Quickshell.env("STATUS"))).layout
    readonly property var grp: JSON.parse(read(Quickshell.env("CLIENTS")))

    function cases() {
        var st = function (patch) { var s = JSON.parse(JSON.stringify(sc.status)); for (var k in patch) s[k] = patch[k]; return s }
        function t(tag, inp) { return { tag: tag, kind: "tiling", m: P.build(inp) } }
        function g(tag, addr, mask, edit) {
            var cl = JSON.parse(JSON.stringify(sc.grp.clients))
            if (edit) edit(cl)
            return { tag: tag, kind: "tabs", m: G.build(cl, addr, mask) }
        }
        function r(tag, s, on, result) { return { tag: tag, kind: "restore", m: R.build(s, on), result: result || null } }
        function n(tag, inp) { return { tag: tag, kind: "scratch", m: S.build(inp) } }
        return [
            t("tiling-default", { n: 3 }),
            t("tiling-grid", { n: 3, selected: "grid" }),
            t("tiling-half", { n: 2, remembered: "code-review" }),
            t("tiling-single", { n: 1 }),
            g("tabs-default", "0xc2", false),
            g("tabs-first", "0xc1", false),
            g("tabs-two", "0xc1", false, function (cl) { cl.forEach(function (c) { if (c.grouped.length === 4) c.grouped = ["0xc1", "0xc2"] }) }),
            g("tabs-masked", "0xc1", true, function (cl) { cl[3].cls = "slack"; cl[3].title = "private thread" }),
            g("tabs-alone", "0xd1", false),
            r("restore-default", st({})),
            r("restore-toggled", st({}), { finished: true, agents: false }),
            r("restore-noagents", st({ panes: 0, agents: 0, finished: 0 })),
            r("restore-allclear", st({}), { layout: false, apps: false, panes: false, agents: false }),
            r("restore-result", st({}), {}, { launched: 11, failed: 0 }),
            r("restore-failed", st({}), {}, { launched: 9, failed: 2 }),
            n("scratch-note", { tab: "note", profile: "Dev", text: "db-02 needs two vCPUs tonight.\nCheck ballooning on db-03 first." }),
            n("scratch-empty", { tab: "note", profile: "Dev", text: "" }),
            n("scratch-stub", { tab: "math", profile: "Dev", text: "x" }),
            n("scratch-pinned", { tab: "note", profile: "Dev", text: "kept open", pinned: true })
        ]
    }

    property var caseList: cases()
    property int idx: 0
    readonly property var cur: caseList[Math.min(idx, caseList.length - 1)]

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function measure() {
        var m = { names: {}, card: { w: card.width, h: card.height } }
        walk(stage, function (it) {
            if (!it.objectName) return
            var p = it.mapToItem(stage, 0, 0)
            var vis = it.visible && it.opacity > 0
            var r = { x: Math.round(p.x - card.x), y: Math.round(p.y - card.y), w: Math.round(it.width), h: Math.round(it.height), visible: vis }
            if (it.text !== undefined) r.text = String(it.text)
            if (it.paintedPx !== undefined) r.px = it.paintedPx; if (it.box !== undefined) r.box = it.box
            if (it.color !== undefined && it.objectName === "thumbRect") r.on = String(it.color) === String(Theme.color.accent)
            if (!m.names[it.objectName]) m.names[it.objectName] = []
            m.names[it.objectName].push(r)
        })
        return m
    }

    FloatingWindow {
        id: win
        implicitWidth: 760
        implicitHeight: 640
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }
            Surface {
                id: card
                x: 60
                y: 40
                corner: Theme.radius.card
                width: inner.width + 2 * Theme.space.xxl
                height: inner.height + 2 * Theme.space.xxl
                Item {
                    id: inner
                    x: Theme.space.xxl
                    y: Theme.space.xxl
                    width: sc.cur.kind === "tiling" ? tiling.width : (sc.cur.kind === "tabs" ? tabs.width : (sc.cur.kind === "restore" ? restore.width : scratch.width))
                    height: sc.cur.kind === "tiling" ? tiling.height : (sc.cur.kind === "tabs" ? tabs.height + 8 + frame.height : (sc.cur.kind === "restore" ? restore.height : scratch.height))
                    TilingAssistant { id: tiling; visible: sc.cur.kind === "tiling"; m: sc.cur.kind === "tiling" ? sc.cur.m : P.build({ n: 0 }) }
                    Item {
                        id: tabsBox
                        visible: sc.cur.kind === "tabs"
                        width: tabs.width
                        height: tabs.height + 8 + frame.height
                        TabsBar { id: tabs; visible: sc.cur.kind === "tabs" && sc.cur.m.show; m: sc.cur.kind === "tabs" ? sc.cur.m : ({ show: false, tabs: [], n: 0, text: "" }) }
                        // test chrome only: the window the strip sits on
                        Rectangle {
                            id: frame
                            y: tabs.height + 8
                            width: tabs.width
                            height: 120
                            radius: 10
                            color: Theme.color.bg
                            border.width: 1
                            border.color: Theme.color.outlineVariant
                            Cap { x: 14; y: 12; text: sc.cur.kind === "tabs" && sc.cur.m.show ? "Active window fills the frame." : "A window on its own shows no strip."; dim: false }
                        }
                    }
                    RestorePrompt { id: restore; visible: sc.cur.kind === "restore"; m: sc.cur.kind === "restore" ? sc.cur.m : R.build(null); result: sc.cur.kind === "restore" ? sc.cur.result : null }
                    ScratchPanel { id: scratch; visible: sc.cur.kind === "scratch"; readOnly: true; m: sc.cur.kind === "scratch" ? sc.cur.m : S.build({}) }
                }
            }
        }
    }

    function next() {
        if (sc.idx >= sc.caseList.length) { Qt.quit(); return }
        settle.restart()
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: {
            var c = sc.caseList[sc.idx]
            console.log("PROBE " + c.tag + " " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outDir + "/windows-" + c.tag + ".png")
                console.log("SHOT " + c.tag)
                sc.idx++
                sc.next()
            })
        }
    }

    Component.onCompleted: Qt.callLater(next)
}
